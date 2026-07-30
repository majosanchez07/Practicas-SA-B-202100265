import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    database_url: str = os.getenv("DATABASE_URL", "postgresql://user:password@localhost:5432/solicitudes_db")
    environment: str = os.getenv("ENVIRONMENT", "development")
    debug: bool = os.getenv("DEBUG", "True") == "True"

settings = Settings()