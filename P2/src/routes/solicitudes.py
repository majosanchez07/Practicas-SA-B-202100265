from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from src.models.database import get_db
from src.schemas.solicitud_schema import (
    SolicitudCreate, 
    SolicitudUpdate, 
    SolicitudEstadoUpdate,
    SolicitudResponse
)
from src.services.solicitud_service import SolicitudService
from uuid import UUID

router = APIRouter(prefix="/solicitudes", tags=["solicitudes"])

@router.get("/", response_model=list[SolicitudResponse])
def obtener_todas_solicitudes(db: Session = Depends(get_db)):
    """Obtener todas las solicitudes operativas"""
    solicitudes = SolicitudService.obtener_todas_solicitudes(db)
    return solicitudes

@router.post("/", response_model=SolicitudResponse, status_code=status.HTTP_201_CREATED)
def crear_solicitud(solicitud: SolicitudCreate, db: Session = Depends(get_db)):
    """Registrar una nueva solicitud operativa"""
    nueva_solicitud = SolicitudService.crear_solicitud(db, solicitud)
    return nueva_solicitud

@router.get("/{solicitud_id}", response_model=SolicitudResponse)
def obtener_solicitud(solicitud_id: UUID, db: Session = Depends(get_db)):
    """Obtener una solicitud por ID"""
    solicitud = SolicitudService.obtener_solicitud(db, solicitud_id)
    if not solicitud:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Solicitud con ID {solicitud_id} no encontrada"
        )
    return solicitud

@router.put("/{solicitud_id}", response_model=SolicitudResponse)
def actualizar_solicitud(solicitud_id: UUID, solicitud_update: SolicitudUpdate, db: Session = Depends(get_db)):
    """Actualizar completamente una solicitud"""
    solicitud_actualizada = SolicitudService.actualizar_solicitud(db, solicitud_id, solicitud_update)
    if not solicitud_actualizada:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Solicitud con ID {solicitud_id} no encontrada"
        )
    return solicitud_actualizada

@router.patch("/{solicitud_id}/estado", response_model=SolicitudResponse)
def actualizar_estado(solicitud_id: UUID, estado_update: SolicitudEstadoUpdate, db: Session = Depends(get_db)):
    """Actualizar solo el estado de una solicitud"""
    solicitud_actualizada = SolicitudService.actualizar_estado(db, solicitud_id, estado_update)
    if not solicitud_actualizada:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Solicitud con ID {solicitud_id} no encontrada"
        )
    return solicitud_actualizada

@router.delete("/{solicitud_id}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar_solicitud(solicitud_id: UUID, db: Session = Depends(get_db)):
    """Eliminar una solicitud operativa"""
    solicitud_eliminada = SolicitudService.eliminar_solicitud(db, solicitud_id)
    if not solicitud_eliminada:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Solicitud con ID {solicitud_id} no encontrada"
        )
    return None