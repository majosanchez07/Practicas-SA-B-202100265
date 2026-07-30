from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from uuid import UUID

class SolicitudBase(BaseModel):
    """Schema base para solicitudes"""
    titulo: str = Field(..., min_length=1, max_length=255, description="Título de la solicitud")
    area_solicitante: str = Field(..., min_length=1, max_length=255, description="Área que solicita")
    prioridad: int = Field(..., ge=1, le=5, description="Prioridad del 1 al 5")
    costo_estimado: float = Field(..., gt=0, description="Costo estimado positivo")
    estado: str = Field(default="registrada", description="Estado actual de la solicitud")

class SolicitudCreate(SolicitudBase):
    """Schema para crear una solicitud"""
    pass

class SolicitudUpdate(BaseModel):
    """Schema para actualizar una solicitud"""
    titulo: Optional[str] = Field(None, min_length=1, max_length=255)
    area_solicitante: Optional[str] = Field(None, min_length=1, max_length=255)
    prioridad: Optional[int] = Field(None, ge=1, le=5)
    costo_estimado: Optional[float] = Field(None, gt=0)
    estado: Optional[str] = None

class SolicitudEstadoUpdate(BaseModel):
    """Schema para actualizar solo el estado"""
    estado: str = Field(..., description="Nuevo estado de la solicitud")

class SolicitudResponse(SolicitudBase):
    """Schema para respuestas de solicitudes"""
    id: UUID
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True