from fastapi import APIRouter, Request, HTTPException, status
from src.services.auth_service import AuthService
import httpx
import asyncio
from src.config import settings

router = APIRouter(prefix='/rutas', tags=['Rutas Protegidas'])

async def verificar_autorizacion(token: str, rol_requerido: str) -> bool:
    intentos = 0
    backoff = settings.AUTHORIZATION_RETRY_BACKOFF
    while intentos < settings.AUTHORIZATION_MAX_RETRIES:
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f'{settings.AUTHORIZATION_SERVICE_URL}/autorizar',
                    json={'token': token, 'rol_requerido': rol_requerido},
                    timeout=5.0
                )
                if response.status_code == 200:
                    data = response.json()
                    return data.get('autorizado', False)
                return False
        except (httpx.RequestError, httpx.TimeoutException):
            intentos += 1
            if intentos < settings.AUTHORIZATION_MAX_RETRIES:
                await asyncio.sleep(backoff * intentos)
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail='Servicio de autorizacion no disponible'
    )

@router.get('/admin')
async def ruta_solo_admin(request: Request):
    token = request.cookies.get('access_token')
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='No autenticado')
    payload = AuthService.verificar_token(token)
    if not payload:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Token invalido o expirado')
    autorizado = await verificar_autorizacion(token, 'admin')
    if not autorizado:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Acceso denegado')
    return {'mensaje': 'Bienvenido Admin', 'rol': payload.get('rol')}

@router.get('/admin-cliente')
async def ruta_admin_y_cliente(request: Request):
    token = request.cookies.get('access_token')
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='No autenticado')
    payload = AuthService.verificar_token(token)
    if not payload:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Token invalido o expirado')
    autorizado = await verificar_autorizacion(token, 'cliente')
    if not autorizado:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Acceso denegado')
    return {'mensaje': 'Bienvenido', 'rol': payload.get('rol')}
