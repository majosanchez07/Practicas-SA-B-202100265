"""
Configuracion comun a las pruebas de books-service.

Dos cosas ocurren aqui, y en este orden:

1. Se inyecta DATABASE_URL antes de importar nada de src, porque config.py la
   declara sin default: el servicio debe negarse a arrancar si el Secret no la
   provee, y esa misma exigencia aplica al importar el modulo en pruebas.

2. Se sustituye la sesion de SQLAlchemy por uh SQLite en memoria. Los resolvers
   de GraphQL abren su propia sesion con SessionLocal() en lugar de recibirla
   por inyeccion, de modo que la unica forma de probarlos sin un Postgres real
   es reemplazar ese objeto. El resultado es que las pruebas ejercitan los
   resolvers de verdad —consultas, filtros, commits— contra una base efimera
   que se crea y se destruye en cada prueba.
"""
import os

os.environ.setdefault(
    'DATABASE_URL', 'postgresql://prueba:prueba@localhost:5432/prueba'
)

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool


@pytest.fixture
def db_en_memoria(monkeypatch):
    """
    Crea una base SQLite nueva por prueba y apunta a ella el SessionLocal que
    usan los resolvers.

    StaticPool con una unica conexion compartida es necesario: sin el, cada
    sesion de ":memory:" abriria su propia base vacia y las filas escritas por
    una mutacion no serian visibles para la consulta siguiente.
    """
    from src.models import database as modulo_db
    from src.models.book import Book

    engine = create_engine(
        'sqlite://',
        connect_args={'check_same_thread': False},
        poolclass=StaticPool,
    )
    # Solo la tabla de este servicio: Base.metadata la registra al importarse.
    Book.__table__.create(bind=engine)

    Sesion = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    # Los resolvers hacen "from src.models.database import SessionLocal", por lo
    # que el parche debe aplicarse tanto en el modulo de origen como en el de
    # destino, donde el nombre ya quedo enlazado al importarse.
    monkeypatch.setattr(modulo_db, 'SessionLocal', Sesion)
    from src.graphql import schema as modulo_schema
    monkeypatch.setattr(modulo_schema, 'SessionLocal', Sesion)

    yield Sesion

    engine.dispose()


@pytest.fixture
def libros_de_ejemplo(db_en_memoria):
    """Tres libros ya cargados, para las pruebas de consulta."""
    from src.models.book import Book

    sesion = db_en_memoria()
    try:
        sesion.add_all([
            Book(title='Cien anos de soledad', author='Gabriel Garcia Marquez',
                 isbn='978-0307474728', genre='Realismo magico', available=True),
            Book(title='El Senor de los Anillos', author='J.R.R. Tolkien',
                 isbn='978-0544003415', genre='Fantasia', available=True),
            Book(title='Rayuela', author='Julio Cortazar',
                 isbn='978-8437604572', genre='Novela', available=False),
        ])
        sesion.commit()
    finally:
        sesion.close()
    return db_en_memoria
