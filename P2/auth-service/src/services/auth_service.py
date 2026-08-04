from sqlalchemy.orm import Session
from src.models.usuario import Usuario
from src.schemas.usuario_schema import UsuarioCreate
from src.services.encryption_service import encryption_service
from src.config import settings
from jose import jwt, JWTError, ExpiredSignatureError
from datetime import datetime, timedelta
from typing import Optional
import uuid

class AuthService:

    @staticmethod
    def crear_usuario(db: Session, usuario: UsuarioCreate) -> Usuario:
        nuevo_usuario = Usuario(
            nombre=encryption_service.encrypt(usuario.nombre),
            correo=encryption_service.encrypt(usuario.correo),
            contrasena=encryption_service.encrypt(usuario.contrasena),
            rol=usuario.rol
        )
        db.add(nuevo_usuario)
        db.commit()
        db.refresh(nuevo_usuario)
        return nuevo_usuario

    @staticmethod
    def obtener_usuario_por_correo(db: Session, correo: str) -> Optional[Usuario]:
        usuarios = db.query(Usuario).all()
        for usuario in usuarios:
            try:
                correo_desencriptado = encryption_service.decrypt(usuario.correo)
                if correo_desencriptado == correo:
                    return usuario
            except Exception:
                continue
        return None

    @staticmethod
    def verificar_contrasena(contrasena_plana: str, contrasena_encriptada: str) -> bool:
        try:
            contrasena_desencriptada = encryption_service.decrypt(contrasena_encriptada)
            return contrasena_plana == contrasena_desencriptada
        except Exception:
            return False

    @staticmethod
    def crear_token(data: dict) -> str:
        to_encode = data.copy()
        expire = datetime.utcnow() + timedelta(minutes=settings.JWT_EXPIRATION_MINUTES)
        to_encode.update({'exp': expire, 'iat': datetime.utcnow()})
        return jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)

    @staticmethod
    def verificar_token(token: str) -> Optional[dict]:
        try:
            payload = jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
            return payload
        except ExpiredSignatureError:
            return None
        except JWTError:
            return None

    @staticmethod
    def renovar_token_si_aplica(token: str) -> Optional[str]:
        try:
            payload = jwt.decode(
                token,
                settings.JWT_SECRET_KEY,
                algorithms=[settings.JWT_ALGORITHM],
                options={'verify_exp': False}
            )
            exp = payload.get('exp')
            if not exp:
                return None
            exp_datetime = datetime.utcfromtimestamp(exp)
            ahora = datetime.utcnow()
            diferencia = (ahora - exp_datetime).total_seconds() / 60
            if diferencia <= settings.JWT_GRACE_PERIOD_MINUTES:
                payload.pop('exp', None)
                payload.pop('iat', None)
                return AuthService.crear_token(payload)
            return None
        except JWTError:
            return None
