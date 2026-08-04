from fastapi import FastAPI
from src.routes import authorization
from src.config import settings

app = FastAPI(
    title='Authorization Service - Practica 2',
    description='Microservicio independiente de autorizacion por roles',
    version='1.0.0'
)

app.include_router(authorization.router)

@app.get('/')
def root():
    return {'mensaje': 'Authorization Service corriendo', 'docs': '/docs'}

if __name__ == '__main__':
    import uvicorn
    uvicorn.run('main:app', host='0.0.0.0', port=settings.PORT, reload=settings.DEBUG)
