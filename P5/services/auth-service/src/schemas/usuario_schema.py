from pydantic import BaseModel, EmailStr
from typing import Optional
from uuid import UUID
from datetime import datetime

class UsuarioBase(BaseModel):
    nombre: str
    correo: str
    rol: Optional[str] = 'cliente'

class UsuarioCreate(UsuarioBase):
    contrasena: str

class UsuarioLogin(BaseModel):
    correo: str
    contrasena: str

class UsuarioResponse(BaseModel):
    id: UUID
    nombre: str
    correo: str
    rol: str
    created_at: datetime

    class Config:
        from_attributes = True
