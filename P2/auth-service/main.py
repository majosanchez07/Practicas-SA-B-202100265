from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from src.models.database import Base, engine
from src.routes import auth, protected
from src.config import settings

Base.metadata.create_all(bind=engine)

app = FastAPI(
    title='Auth Service - Practica 2',
    description='Modulo de autenticacion y autorizacion con JWT, cookies HTTP-only y encriptacion AES',
    version='1.0.0'
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=['http://localhost:3000', 'http://127.0.0.1:5500'],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*']
)

app.include_router(auth.router)
app.include_router(protected.router)

@app.get('/')
def root():
    return {'mensaje': 'Auth Service corriendo', 'docs': '/docs'}

if __name__ == '__main__':
    import uvicorn
    uvicorn.run('main:app', host='0.0.0.0', port=8000, reload=settings.DEBUG)
