"""
Conexion a PostgreSQL.

En la Practica 4 cada microservicio tenia su propia instancia de Postgres. En
la Practica 5 se despliega una sola instancia como StatefulSet y cada servicio
queda aislado en su propio schema: se conserva la separacion logica de datos
entre microservicios, pero con un unico PVC y un unico headless service, que es
lo que el enunciado pide para la persistencia.

El aislamiento se logra fijando el search_path de cada conexion al schema del
servicio, de modo que los modelos no necesitan declarar __table_args__.
"""
from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import declarative_base, sessionmaker

from src.config import settings

DB_SCHEMA = settings.DB_SCHEMA

engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,   # descarta conexiones muertas tras un reinicio del pod de BD
    pool_size=5,
    max_overflow=5,
)


@event.listens_for(engine, "connect", insert=True)
def _fijar_search_path(dbapi_connection, connection_record):
    """Cada conexion nueva del pool trabaja dentro del schema del servicio."""
    cursor = dbapi_connection.cursor()
    cursor.execute(f'SET search_path TO "{DB_SCHEMA}", public')
    cursor.close()


def crear_schema_si_no_existe():
    """Idempotente: varias replicas pueden ejecutarlo en paralelo sin romperse."""
    with engine.connect() as conn:
        conn.execute(text(f'CREATE SCHEMA IF NOT EXISTS "{DB_SCHEMA}"'))
        conn.commit()


SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
