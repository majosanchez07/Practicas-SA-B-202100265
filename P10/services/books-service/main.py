import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from src.models.database import Base, engine, crear_schema_si_no_existe
from src.graphql.schema import schema
from src import routes_health
from src.config import settings
from strawberry.fastapi import GraphQLRouter

app = FastAPI(
    title="Books Service",
    description="Servicio de catalogo de libros con GraphQL",
    version="1.0.0",
    # Detras del Ingress el servicio vive bajo /books y el rewrite-target quita
    # ese prefijo, de modo que FastAPI se creeria montado en la raiz y generaria
    # enlaces absolutos (/openapi.json) que el Ingress ya no sabe enrutar.
    # root_path se lo indica para que /docs pida /books/openapi.json.
    root_path=os.getenv('ROOT_PATH', '')
)


@app.on_event('startup')
def crear_tablas():
    """Ver nota en auth-service: el esquema se crea al arrancar, no al importar."""
    crear_schema_si_no_existe()
    Base.metadata.create_all(bind=engine)


app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS.split(','),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"]
)

app.include_router(routes_health.router)
app.include_router(GraphQLRouter(schema), prefix="/graphql")


@app.get("/")
def root():
    return {"mensaje": "Books Service corriendo", "graphql": "/graphql"}
