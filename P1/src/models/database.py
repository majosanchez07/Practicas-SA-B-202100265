from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from src.config import settings
from src.models.solicitud import Base

# Crear motor de la base de datos
engine = create_engine(settings.database_url, echo=settings.debug)

# Crear sesión
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    """Dependencia para obtener la sesión de base de datos"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def create_tables():
    """Crear todas las tablas"""
    Base.metadata.create_all(bind=engine)