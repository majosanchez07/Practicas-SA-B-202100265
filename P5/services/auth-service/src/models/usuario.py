from sqlalchemy import Column, String, DateTime
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
import uuid
from src.models.database import Base

class Usuario(Base):
    __tablename__ = 'usuarios'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    nombre = Column(String(500), nullable=False)
    correo = Column(String(500), nullable=False, unique=True)
    contrasena = Column(String(500), nullable=False)
    rol = Column(String(50), nullable=False, default='cliente')
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
