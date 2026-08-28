from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from src.models.database import Base, engine, crear_schema_si_no_existe
from src.routes import auth, protected
from src import routes_health
from src.config import settings

app = FastAPI(
    title='Auth Service',
    description='Modulo de autenticacion y autorizacion con JWT, cookies HTTP-only y encriptacion AES',
    version='1.0.0'
)


@app.on_event('startup')
def crear_tablas():
    """
    Se crea el esquema al arrancar y no al importar el modulo: con varias
    replicas levantadas por el HPA, hacerlo en import-time provoca que todos
    los workers golpeen la base a la vez antes de que el proceso este listo.
    """
    crear_schema_si_no_existe()
    Base.metadata.create_all(bind=engine)


app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS.split(','),
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*']
)

app.include_router(routes_health.router)
app.include_router(auth.router)
app.include_router(protected.router)


@app.get('/')
def root():
    return {'mensaje': 'Auth Service corriendo', 'docs': '/docs'}


if __name__ == '__main__':
    import uvicorn
    uvicorn.run('main:app', host='0.0.0.0', port=8000, reload=settings.DEBUG)
