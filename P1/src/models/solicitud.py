from sqlalchemy import Column, Integer, String, Float, DateTime, func
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.dialects.postgresql import UUID
import uuid
from datetime import datetime

Base = declarative_base()

class Solicitud(Base):
    __tablename__ = "solicitudes"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    titulo = Column(String(255), nullable=False)
    area_solicitante = Column(String(255), nullable=False)
    prioridad = Column(Integer, nullable=False)  # 1-5
    costo_estimado = Column(Float, nullable=False)
    estado = Column(String(50), nullable=False, default="registrada")  # registrada, en_proceso, finalizada
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    def __repr__(self):
        return f"<Solicitud(id={self.id}, titulo={self.titulo}, estado={self.estado})>"