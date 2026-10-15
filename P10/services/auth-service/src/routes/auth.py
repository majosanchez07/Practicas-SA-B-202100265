from fastapi import APIRouter, Depends, HTTPException, Response, Request, status
from sqlalchemy.orm import Session
from src.models.database import get_db
from src.schemas.usuario_schema import UsuarioCreate, UsuarioLogin, UsuarioResponse
from src.services.auth_service import AuthService
from src.services.encryption_service import encryption_service

router = APIRouter(prefix='/auth', tags=['Autenticacion'])

@router.post('/registro', response_model=UsuarioResponse, status_code=status.HTTP_201_CREATED)
def registro(usuario: UsuarioCreate, db: Session = Depends(get_db)):
    existente = AuthService.obtener_usuario_por_correo(db, usuario.correo)
    if existente:
        raise HTTPException(status_code=400, detail='El correo ya esta registrado')
    nuevo = AuthService.crear_usuario(db, usuario)
    return UsuarioResponse(
        id=nuevo.id,
        nombre=usuario.nombre,
        correo=usuario.correo,
        rol=nuevo.rol,
        created_at=nuevo.created_at
    )

@router.post('/login')
def login(credenciales: UsuarioLogin, response: Response, db: Session = Depends(get_db)):
    usuario = AuthService.obtener_usuario_por_correo(db, credenciales.correo)
    if not usuario:
        raise HTTPException(status_code=401, detail='Credenciales invalidas')
    if not AuthService.verificar_contrasena(credenciales.contrasena, usuario.contrasena):
        raise HTTPException(status_code=401, detail='Credenciales invalidas')
    token = AuthService.crear_token({
        'sub': str(usuario.id),
        'rol': usuario.rol,
        'correo': credenciales.correo
    })
    response.set_cookie(
        key='access_token',
        value=token,
        httponly=True,
        max_age=1800,
        samesite='lax'
    )
    return {
        'mensaje': 'Login exitoso',
        'rol': usuario.rol,
        'nombre': encryption_service.decrypt(usuario.nombre)
    }

@router.post('/logout')
def logout(response: Response):
    response.delete_cookie('access_token')
    return {'mensaje': 'Sesion cerrada correctamente'}

@router.post('/renovar-token')
def renovar_token(request: Request, response: Response):
    token = request.cookies.get('access_token')
    if not token:
        raise HTTPException(status_code=401, detail='No hay token')
    nuevo_token = AuthService.renovar_token_si_aplica(token)
    if not nuevo_token:
        raise HTTPException(status_code=401, detail='Token expirado fuera del periodo de gracia')
    response.set_cookie(
        key='access_token',
        value=nuevo_token,
        httponly=True,
        max_age=1800,
        samesite='lax'
    )
    return {'mensaje': 'Token renovado correctamente'}
