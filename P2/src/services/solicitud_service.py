from sqlalchemy.orm import Session
from src.models.solicitud import Solicitud
from src.schemas.solicitud_schema import SolicitudCreate, SolicitudUpdate, SolicitudEstadoUpdate
from uuid import UUID
from typing import List, Optional

class SolicitudService:
    """Servicio para gestionar solicitudes operativas"""

    @staticmethod
    def crear_solicitud(db: Session, solicitud: SolicitudCreate) -> Solicitud:
        """Crear una nueva solicitud"""
        nueva_solicitud = Solicitud(
            titulo=solicitud.titulo,
            area_solicitante=solicitud.area_solicitante,
            prioridad=solicitud.prioridad,
            costo_estimado=solicitud.costo_estimado,
            estado=solicitud.estado
        )
        db.add(nueva_solicitud)
        db.commit()
        db.refresh(nueva_solicitud)
        return nueva_solicitud

    @staticmethod
    def obtener_solicitud(db: Session, solicitud_id: UUID) -> Optional[Solicitud]:
        """Obtener una solicitud por ID"""
        return db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()

    @staticmethod
    def obtener_todas_solicitudes(db: Session, skip: int = 0, limit: int = 100) -> List[Solicitud]:
        """Obtener todas las solicitudes con paginación"""
        return db.query(Solicitud).offset(skip).limit(limit).all()

    @staticmethod
    def actualizar_solicitud(db: Session, solicitud_id: UUID, solicitud_update: SolicitudUpdate) -> Optional[Solicitud]:
        """Actualizar completamente una solicitud"""
        solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
        if not solicitud:
            return None
        
        # Actualizar solo los campos que no son None
        datos_actualizacion = solicitud_update.model_dump(exclude_unset=True)
        for campo, valor in datos_actualizacion.items():
            if valor is not None:
                setattr(solicitud, campo, valor)
        
        db.commit()
        db.refresh(solicitud)
        return solicitud

    @staticmethod
    def actualizar_estado(db: Session, solicitud_id: UUID, estado_update: SolicitudEstadoUpdate) -> Optional[Solicitud]:
        """Actualizar solo el estado de una solicitud"""
        solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
        if not solicitud:
            return None
        
        solicitud.estado = estado_update.estado
        db.commit()
        db.refresh(solicitud)
        return solicitud

    @staticmethod
    def eliminar_solicitud(db: Session, solicitud_id: UUID) -> Optional[Solicitud]:
        """Eliminar una solicitud"""
        solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
        if not solicitud:
            return None
        
        db.delete(solicitud)
        db.commit()
        return solicitud