"""
Pruebas de la logica de tokens y de verificacion de contrasenas.

No tocan la base de datos: crear_usuario y obtener_usuario_por_correo reciben
una Session, y aqui interesa la logica pura —firma, expiracion, periodo de
gracia y comparacion de contrasenas—, que es la que tiene reglas propias del
proyecto y la que se rompe con un cambio descuidado.
"""
from datetime import datetime, timedelta, timezone

import pytest
from jose import jwt

from src.config import settings
from src.services.auth_service import AuthService
from src.services.encryption_service import encryption_service


def _token_con_expiracion(minutos_desde_ahora: int, datos: dict | None = None) -> str:
    """
    Construye un token firmado con la llave real del servicio pero con el "exp"
    que necesite cada prueba. Es la forma de simular un token vencido sin
    esperar 30 minutos ni parchear el reloj del sistema.
    """
    payload = dict(datos or {'sub': 'maria@usac.edu.gt', 'rol': 'admin'})
    expira = datetime.utcnow() + timedelta(minutes=minutos_desde_ahora)
    payload.update({'exp': expira, 'iat': datetime.utcnow()})
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


class TestCrearToken:
    def test_el_token_tiene_las_tres_partes_de_un_jwt(self):
        token = AuthService.crear_token({'sub': 'maria@usac.edu.gt'})
        assert token.count('.') == 2

    def test_conserva_los_datos_que_se_le_pasan(self):
        token = AuthService.crear_token({'sub': 'maria@usac.edu.gt', 'rol': 'admin'})
        payload = AuthService.verificar_token(token)
        assert payload['sub'] == 'maria@usac.edu.gt'
        assert payload['rol'] == 'admin'

    def test_agrega_exp_e_iat(self):
        token = AuthService.crear_token({'sub': 'maria@usac.edu.gt'})
        payload = AuthService.verificar_token(token)
        assert 'exp' in payload
        assert 'iat' in payload

    def test_la_expiracion_respeta_la_configuracion(self):
        token = AuthService.crear_token({'sub': 'maria@usac.edu.gt'})
        payload = AuthService.verificar_token(token)
        vida_minutos = (payload['exp'] - payload['iat']) / 60
        assert vida_minutos == pytest.approx(settings.JWT_EXPIRATION_MINUTES, abs=1)

    def test_no_muta_el_diccionario_recibido(self):
        """
        crear_token hace data.copy() antes de agregar exp/iat. Si esa copia
        desapareciera, el llamador veria su diccionario contaminado.
        """
        datos = {'sub': 'maria@usac.edu.gt'}
        AuthService.crear_token(datos)
        assert datos == {'sub': 'maria@usac.edu.gt'}


class TestVerificarToken:
    def test_acepta_un_token_valido(self):
        token = AuthService.crear_token({'sub': 'maria@usac.edu.gt'})
        assert AuthService.verificar_token(token) is not None

    def test_rechaza_un_token_expirado(self):
        assert AuthService.verificar_token(_token_con_expiracion(-1)) is None

    def test_rechaza_un_token_firmado_con_otra_llave(self):
        """El caso que importa: un token falsificado no debe pasar."""
        falso = jwt.encode(
            {'sub': 'intruso', 'exp': datetime.utcnow() + timedelta(minutes=30)},
            'llave-del-atacante',
            algorithm=settings.JWT_ALGORITHM,
        )
        assert AuthService.verificar_token(falso) is None

    @pytest.mark.parametrize('basura', ['', 'no-es-un-token', 'a.b.c', 'a.b'])
    def test_rechaza_cadenas_que_no_son_jwt(self, basura):
        """Devuelve None en lugar de propagar la excepcion al endpoint."""
        assert AuthService.verificar_token(basura) is None


class TestPeriodoDeGracia:
    """
    renovar_token_si_aplica implementa la renovacion silenciosa: un token
    recien vencido, dentro de JWT_GRACE_PERIOD_MINUTES, se cambia por uno nuevo
    para que el usuario no pierda la sesion por unos segundos de diferencia.
    Pasado ese margen debe negarse, porque si no el periodo de gracia
    equivaldria a un token eterno.
    """

    def test_renueva_un_token_vencido_hace_poco(self):
        vencido_hace_2_min = _token_con_expiracion(-2)
        nuevo = AuthService.renovar_token_si_aplica(vencido_hace_2_min)
        assert nuevo is not None
        assert AuthService.verificar_token(nuevo) is not None

    def test_el_token_renovado_conserva_la_identidad(self):
        vencido = _token_con_expiracion(-2, {'sub': 'maria@usac.edu.gt', 'rol': 'admin'})
        nuevo = AuthService.renovar_token_si_aplica(vencido)
        payload = AuthService.verificar_token(nuevo)
        assert payload['sub'] == 'maria@usac.edu.gt'
        assert payload['rol'] == 'admin'

    def test_el_token_renovado_tiene_una_expiracion_futura(self):
        nuevo = AuthService.renovar_token_si_aplica(_token_con_expiracion(-2))
        payload = AuthService.verificar_token(nuevo)
        # El "exp" del JWT es un epoch UTC. Comparar contra
        # datetime.utcnow().timestamp() seria incorrecto: utcnow() devuelve un
        # datetime naive y .timestamp() lo interpreta como hora local, lo que en
        # Guatemala (UTC-6) desplaza la comparacion seis horas. Se usa un
        # datetime consciente de zona para obtener el epoch real.
        ahora_epoch = datetime.now(timezone.utc).timestamp()
        assert payload['exp'] > ahora_epoch

    def test_no_renueva_pasado_el_periodo_de_gracia(self):
        fuera_de_gracia = -(settings.JWT_GRACE_PERIOD_MINUTES + 5)
        assert AuthService.renovar_token_si_aplica(_token_con_expiracion(fuera_de_gracia)) is None

    def test_no_renueva_un_token_firmado_con_otra_llave(self):
        """
        Sin esta garantia, el periodo de gracia seria una puerta trasera: se
        decodifica con verify_exp=False, pero la firma se sigue validando.
        """
        falso = jwt.encode(
            {'sub': 'intruso', 'exp': datetime.utcnow() - timedelta(minutes=1)},
            'llave-del-atacante',
            algorithm=settings.JWT_ALGORITHM,
        )
        assert AuthService.renovar_token_si_aplica(falso) is None

    def test_no_renueva_un_token_sin_exp(self):
        sin_exp = jwt.encode(
            {'sub': 'maria@usac.edu.gt'},
            settings.JWT_SECRET_KEY,
            algorithm=settings.JWT_ALGORITHM,
        )
        assert AuthService.renovar_token_si_aplica(sin_exp) is None


class TestVerificarContrasena:
    def test_acepta_la_contrasena_correcta(self):
        cifrada = encryption_service.encrypt('mi-contrasena')
        assert AuthService.verificar_contrasena('mi-contrasena', cifrada) is True

    def test_rechaza_una_contrasena_incorrecta(self):
        cifrada = encryption_service.encrypt('mi-contrasena')
        assert AuthService.verificar_contrasena('otra-contrasena', cifrada) is False

    def test_distingue_mayusculas_de_minusculas(self):
        cifrada = encryption_service.encrypt('MiContrasena')
        assert AuthService.verificar_contrasena('micontrasena', cifrada) is False

    def test_devuelve_false_ante_un_dato_ilegible(self):
        """
        El registro pudo cifrarse con otra llave. Debe responder False, nunca
        propagar la excepcion hacia el endpoint de login.
        """
        assert AuthService.verificar_contrasena('lo-que-sea', 'no-descifrable') is False
