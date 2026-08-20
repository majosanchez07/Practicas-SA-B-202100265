from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import strawberry
from strawberry.fastapi import GraphQLRouter
from src.models.database import Base, engine
from src.graphql.schema import schema
from src.config import settings

Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Books Service",
    description="Servicio de catalogo de libros con GraphQL",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"]
)

graphql_app = GraphQLRouter(schema)
app.include_router(graphql_app, prefix="/graphql")

@app.get("/")
def root():
    return {"mensaje": "Books Service corriendo", "graphql": "/graphql"}

@app.get("/health")
def health():
    return {"status": "ok", "service": "books-service"}
