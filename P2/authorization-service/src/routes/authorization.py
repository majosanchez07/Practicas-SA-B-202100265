from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel
from jose import jwt, JWTError
from src.config import settings

router = APIRouter(tags=['Autorizacion'])

class AutorizacionRequest(BaseModel):
    token: str
    rol_requerido: str

@router.post('/autorizar')
def autorizar(request: AutorizacionRequest):
    try:
        payload = jwt.decode(
            request.token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM]
        )
        rol_usuario = payload.get('rol')
        if not rol_usuario:
            return {'autorizado': False, 'motivo': 'Token sin rol definido'}
        if request.rol_requerido == 'admin':
            if rol_usuario == 'admin':
                return {'autorizado': True, 'rol': rol_usuario}
            return {'autorizado': False, 'motivo': 'Se requiere rol admin'}
        if request.rol_requerido == 'cliente':
            if rol_usuario in ['admin', 'cliente']:
                return {'autorizado': True, 'rol': rol_usuario}
            return {'autorizado': False, 'motivo': 'Rol no reconocido'}
        return {'autorizado': False, 'motivo': 'Rol requerido no reconocido'}
    except JWTError:
        return {'autorizado': False, 'motivo': 'Token invalido o expirado'}
