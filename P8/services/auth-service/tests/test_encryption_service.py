"""
Pruebas del cifrado AES-256-CBC que protege los datos personales del usuario.

Lo que interesa verificar no es que "AES funcione" —eso lo garantiza
pycryptodome— sino las tres decisiones propias del servicio: el formato
"iv:ciphertext", el uso de un IV distinto en cada operacion y que el par
encrypt/decrypt sea reversible para los datos que realmente se guardan.
"""
import base64

import pytest

from src.services.encryption_service import EncryptionService, encryption_service


class TestCifradoReversible:
    """encrypt seguido de decrypt debe devolver exactamente el dato original."""

    @pytest.mark.parametrize('original', [
        'maria@usac.edu.gt',
        'Maria Jose Tebalan Sanchez',
        'contrasena-secreta-123',
        # Un solo caracter obliga al relleno PKCS#7 a agregar 15 bytes.
        'a',
        # Exactamente 16 bytes: el caso borde del relleno, donde PKCS#7 debe
        # agregar un bloque completo en lugar de no agregar nada.
        '0123456789abcdef',
        # Acentos y enie: el servicio codifica en UTF-8, no en ASCII.
        'Maria Jose Tebalan Sanchez',
        'usuario+etiqueta@dominio.com',
    ])
    def test_ida_y_vuelta(self, original):
        cifrado = encryption_service.encrypt(original)
        assert encryption_service.decrypt(cifrado) == original

    def test_el_texto_cifrado_no_contiene_el_original(self):
        """Verificacion basica de que efectivamente se cifro."""
        secreto = 'contrasena-en-claro'
        cifrado = encryption_service.encrypt(secreto)
        assert secreto not in cifrado


class TestFormatoDeSalida:
    """El formato "iv:ciphertext" es un contrato: decrypt lo parte por ":"."""

    def test_tiene_dos_partes_separadas_por_dos_puntos(self):
        cifrado = encryption_service.encrypt('dato')
        partes = cifrado.split(':')
        assert len(partes) == 2

    def test_ambas_partes_son_base64_valido(self):
        iv, ct = encryption_service.encrypt('dato').split(':')
        # Si no fueran base64, b64decode lanzaria y la prueba fallaria.
        assert len(base64.b64decode(iv)) == 16     # el IV de CBC mide un bloque
        assert len(base64.b64decode(ct)) % 16 == 0  # multiplo del bloque


class TestIVAleatorio:
    """
    AES.new(key, MODE_CBC) sin IV explicito genera uno aleatorio por llamada.
    Esa es la razon por la que cifrar dos veces el mismo dato da resultados
    distintos, y es una propiedad de seguridad que conviene fijar con una
    prueba: si alguien "optimizara" el servicio reutilizando un IV fijo, dos
    usuarios con la misma contrasena tendrian el mismo texto cifrado y la
    tabla de usuarios filtraria esa coincidencia.
    """

    def test_dos_cifrados_del_mismo_dato_difieren(self):
        dato = 'mismo-dato'
        primero = encryption_service.encrypt(dato)
        segundo = encryption_service.encrypt(dato)
        assert primero != segundo

    def test_pero_ambos_descifran_al_mismo_valor(self):
        dato = 'mismo-dato'
        primero = encryption_service.encrypt(dato)
        segundo = encryption_service.encrypt(dato)
        assert encryption_service.decrypt(primero) == dato
        assert encryption_service.decrypt(segundo) == dato

    def test_los_iv_generados_son_distintos(self):
        ivs = {encryption_service.encrypt('dato').split(':')[0] for _ in range(20)}
        # 20 IV aleatorios de 128 bits: que se repitieran seria imposible en la
        # practica, de modo que un conjunto mas pequeno delata un IV fijo.
        assert len(ivs) == 20


class TestEntradasInvalidas:
    """
    decrypt se usa en auth_service dentro de un try/except que devuelve None o
    False cuando falla. Estas pruebas fijan que efectivamente lanza, porque de
    ese comportamiento depende que un usuario cifrado con otra llave no se
    confunda con una coincidencia valida.
    """

    def test_texto_sin_separador_lanza(self):
        with pytest.raises(ValueError):
            encryption_service.decrypt('sin-separador')

    def test_texto_cifrado_con_otra_llave_lanza(self):
        otro = EncryptionService()
        otro.key = b'llave-totalmente-distinta-de-32b'
        cifrado_ajeno = otro.encrypt('dato')
        # El relleno PKCS#7 no cuadra al descifrar con la llave equivocada.
        with pytest.raises(ValueError):
            encryption_service.decrypt(cifrado_ajeno)


class TestLlave:
    def test_la_llave_se_trunca_a_32_bytes(self):
        """
        AES-256 exige 32 bytes. El servicio corta con [:32], asi que una llave
        mas larga configurada por error no debe romper el arranque.
        """
        assert len(encryption_service.key) == 32
