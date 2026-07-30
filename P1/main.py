from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from src.models.database import create_tables
from src.routes.solicitudes import router as solicitudes_router
from src.config import settings

# Crear la aplicación FastAPI
app = FastAPI(
    title="API de Solicitudes Operativas",
    description="API REST para gestionar solicitudes operativas de una academia ficticia",
    version="1.0.0"
)

# Configurar CORS (para permitir peticiones desde el frontend)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Crear las tablas al iniciar
@app.on_event("startup")
def startup_event():
    create_tables()
    print("✓ Tablas de base de datos creadas")

# Health check
@app.get("/health")
def health_check():
    """Verificar que la API está funcionando"""
    return {"status": "ok", "message": "API funcionando correctamente"}

# Incluir rutas
app.include_router(solicitudes_router)

# Raíz de la API
@app.get("/")
def read_root():
    """Bienvenida a la API"""
    return {
        "mensaje": "Bienvenido a la API de Solicitudes Operativas",
        "versión": "1.0.0",
        "docs": "/docs",
        "ambiente": settings.environment
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.debug
    )