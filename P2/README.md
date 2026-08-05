
# Practica 2 - Autenticacion y Autorizacion

**Universidad de San Carlos de Guatemala**
**Facultad de Ingenieria**
**Ingenieria en Ciencias y Sistemas**
**Software Avanzado - Seccion B**

**Nombre:** Maria Jose Tebalan Sanchez
**Carne:** 202100265

---

## Descripcion del Proyecto

Sistema full-stack de autenticacion y autorizacion para una aplicacion web, implementando JWT almacenado en cookies HTTP-only, encriptacion AES para datos sensibles, autorizacion por roles (Admin/Cliente) y un microservicio independiente de autorizacion con retry loop.

---

## Stack Tecnologico

### Backend (auth-service)
- **Lenguaje:** Python 3.13
- **Framework:** FastAPI
- **ORM:** SQLAlchemy
- **Base de datos:** PostgreSQL
- **Autenticacion:** JWT (python-jose)
- **Encriptacion:** AES (pycryptodome)
- **Servidor:** Uvicorn

**Ventajas:**
- FastAPI genera documentacion interactiva automaticamente
- Python-jose facilita la creacion y validacion de JWT
- Pycryptodome ofrece implementacion robusta de AES
- SQLAlchemy permite cambiar de base de datos sin modificar logica

**Desventajas:**
- Python puede ser mas lento que lenguajes compilados en alta concurrencia
- La gestion manual de cookies requiere configuracion cuidadosa

### Backend (authorization-service)
- **Lenguaje:** Python 3.13
- **Framework:** FastAPI
- **Servidor:** Uvicorn (puerto 8001)

**Ventajas:**
- Microservicio independiente, desacoplado del servicio de autenticacion
- Facil de escalar horizontalmente
- Retry loop con backoff configurable ante fallas temporales

**Desventajas:**
- Agrega latencia de red al flujo de autorizacion
- Requiere manejo de errores de comunicacion entre servicios

### Frontend
- **HTML5, CSS3, JavaScript vanilla**

**Ventajas:**
- Sin dependencias externas, carga rapida
- Compatible con cualquier navegador moderno

**Desventajas:**
- Sin framework, el codigo puede volverse dificil de mantener en proyectos grandes

### Base de datos
- **PostgreSQL**

**Ventajas:**
- Robusto, confiable y con soporte para tipos de datos avanzados
- Excelente rendimiento en consultas complejas

**Desventajas:**
- Requiere mas configuracion inicial que SQLite

---

## Arquitectura del Sistema

```
Frontend (HTML/JS)
      |
      | HTTP REST (cookies HTTP-only)
      |
Auth Service (puerto 8000)
      |
      |--- PostgreSQL (datos encriptados con AES)
      |
      |--- Authorization Service (puerto 8001)
            retry loop con backoff
```

---

## Diagrama de Secuencia

```mermaid
sequenceDiagram
    participant F as Frontend
    participant A as Auth Service
    participant Z as Authorization Service
    participant DB as PostgreSQL

    Note over F,DB: Flujo de Registro
    F->>A: POST /auth/registro {nombre, correo, contrasena, rol}
    A->>A: Encriptar datos con AES
    A->>DB: INSERT usuario encriptado
    DB-->>A: Usuario creado
    A-->>F: 201 Created {id, nombre, correo, rol}

    Note over F,DB: Flujo de Login
    F->>A: POST /auth/login {correo, contrasena}
    A->>DB: SELECT usuarios
    A->>A: Desencriptar y comparar credenciales
    A->>A: Generar JWT con rol y sub
    A-->>F: 200 OK + Set-Cookie: access_token (HTTP-only)

    Note over F,DB: Flujo de Acceso a Ruta Protegida
    F->>A: GET /rutas/admin (cookie automatica)
    A->>A: Verificar JWT del cookie
    A->>Z: POST /autorizar {token, rol_requerido}
    Z->>Z: Decodificar JWT y validar rol
    Z-->>A: {autorizado: true/false}
    A-->>F: 200 OK o 403 Forbidden

    Note over F,DB: Flujo de Renovacion de Token
    F->>A: POST /auth/renovar-token (cookie expirada)
    A->>A: Verificar si expiro dentro del periodo de gracia
    A->>A: Generar nuevo JWT
    A-->>F: 200 OK + nuevo Set-Cookie HTTP-only
```

---

## Seguridad Implementada

### JWT en Cookies HTTP-only
El token JWT nunca es visible para el usuario ni accesible via JavaScript. Se almacena en una cookie con la flag httponly=True, lo que previene ataques XSS. El tiempo de vida y el periodo de gracia para renovacion son configurables mediante variables de entorno.

### Encriptacion AES
Todos los datos sensibles (nombre, correo, contrasena) se almacenan encriptados en la base de datos usando el algoritmo AES en modo CBC. Cada encriptacion genera un IV aleatorio, haciendo que el mismo texto produzca resultados distintos en cada operacion.

### Autorizacion por Roles
El sistema contempla dos roles: Admin y Cliente. La autorizacion se resuelve a traves de un microservicio independiente (puerto 8001), consultado mediante un retry loop con backoff configurable ante fallas temporales.

### Renovacion Automatica de Token
Cuando un JWT ha expirado pero ha transcurrido menos tiempo del periodo de gracia configurado (JWT_GRACE_PERIOD_MINUTES), el sistema genera automaticamente un nuevo token sin requerir que el usuario inicie sesion nuevamente.

---

## Estructura del Proyecto

```
P2/
├── auth-service/
│   ├── src/
│   │   ├── models/
│   │   │   ├── database.py
│   │   │   └── usuario.py
│   │   ├── schemas/
│   │   │   └── usuario_schema.py
│   │   ├── services/
│   │   │   ├── auth_service.py
│   │   │   └── encryption_service.py
│   │   ├── routes/
│   │   │   ├── auth.py
│   │   │   └── protected.py
│   │   └── config.py
│   ├── main.py
│   ├── requirements.txt
│   └── .env
├── authorization-service/
│   ├── src/
│   │   ├── routes/
│   │   │   └── authorization.py
│   │   └── config.py
│   ├── main.py
│   ├── requirements.txt
│   └── .env
├── frontend/
│   ├── index.html
│   ├── login.html
│   ├── registro.html
│   ├── confirmacion.html
│   ├── admin.html
│   ├── style.css
│   └── app.js
└── README.md
```

---

## Instrucciones de Ejecucion

### Requisitos previos
- Python 3.10+
- PostgreSQL instalado y corriendo
- Crear la base de datos ejecutando en psql o pgAdmin:

```sql
CREATE DATABASE auth_db;
```

### 1. Auth Service (Terminal 1)

```powershell
cd P2/auth-service
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
python main.py
```

Corre en: http://localhost:8000
Docs: http://localhost:8000/docs

### 2. Authorization Service (Terminal 2)

```powershell
cd P2/authorization-service
python -m venv venv
.\venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python main.py
```

Corre en: http://localhost:8001
Docs: http://localhost:8001/docs

### 3. Frontend (Terminal 3)

```powershell
cd P2/frontend
python -m http.server 3000
```

Abrir en el navegador: http://localhost:3000

---

## Pruebas Realizadas

### Usuarios de prueba utilizados

| Rol | Nombre | Correo | Contrasena |
|-----|--------|--------|------------|
| Admin | Maria Jose Tebalan | admin@test.com | password123 |
| Cliente | Usuario Cliente | cliente@test.com | password123 |

---

### Prueba 1 - Registro de usuario Admin

Endpoint: `POST /auth/registro`
URL: http://localhost:8000/docs

Body enviado:
```json
{
  "nombre": "Maria Jose Tebalan",
  "correo": "admin@test.com",
  "contrasena": "password123",
  "rol": "admin"
}
```

Respuesta obtenida (201 Created):
```json
{
  "id": "uuid-generado",
  "nombre": "Maria Jose Tebalan",
  "correo": "admin@test.com",
  "rol": "admin",
  "created_at": "2026-07-30T00:00:00"
}
```

Resultado: Los datos se almacenaron encriptados con AES en la base de datos.

---

### Prueba 2 - Registro de usuario Cliente

Endpoint: `POST /auth/registro`

Body enviado:
```json
{
  "nombre": "Usuario Cliente",
  "correo": "cliente@test.com",
  "contrasena": "password123",
  "rol": "cliente"
}
```

Respuesta obtenida (201 Created):
```json
{
  "id": "uuid-generado",
  "nombre": "Usuario Cliente",
  "correo": "cliente@test.com",
  "rol": "cliente",
  "created_at": "2026-07-30T00:00:00"
}
```

---

### Prueba 3 - Login usuario Admin

Endpoint: `POST /auth/login`

Body enviado:
```json
{
  "correo": "admin@test.com",
  "contrasena": "password123"
}
```

Respuesta obtenida (200 OK):
```json
{
  "mensaje": "Login exitoso",
  "rol": "admin",
  "nombre": "Maria Jose Tebalan"
}
```

Resultado: Se genero un JWT y se almaceno en una cookie HTTP-only llamada access_token, no visible para el usuario ni accesible via JavaScript.

---

### Prueba 4 - Login usuario Cliente

Endpoint: `POST /auth/login`

Body enviado:
```json
{
  "correo": "cliente@test.com",
  "contrasena": "password123"
}
```

Respuesta obtenida (200 OK):
```json
{
  "mensaje": "Login exitoso",
  "rol": "cliente",
  "nombre": "Usuario Cliente"
}
```

---

### Prueba 5 - Acceso a ruta Admin+Cliente con rol Admin

Endpoint: `GET /rutas/admin-cliente`

Resultado (200 OK):
```json
{
  "mensaje": "Bienvenido",
  "rol": "admin"
}
```

---

### Prueba 6 - Acceso a ruta solo Admin con rol Admin

Endpoint: `GET /rutas/admin`

Resultado (200 OK):
```json
{
  "mensaje": "Bienvenido Admin",
  "rol": "admin"
}
```

---

### Prueba 7 - Acceso a ruta Admin+Cliente con rol Cliente

Endpoint: `GET /rutas/admin-cliente`
(Con sesion iniciada como cliente@test.com)

Resultado (200 OK):
```json
{
  "mensaje": "Bienvenido",
  "rol": "cliente"
}
```

---

### Prueba 8 - Acceso denegado a ruta solo Admin con rol Cliente

Endpoint: `GET /rutas/admin`
(Con sesion iniciada como cliente@test.com)

Resultado (403 Forbidden):
```json
{
  "detail": "Acceso denegado"
}
```

Resultado: El microservicio de autorizacion valido correctamente el rol y denego el acceso.

---

### Prueba 9 - Renovacion de token

Endpoint: `POST /auth/renovar-token`

Con un token expirado dentro del periodo de gracia (5 minutos), el sistema genera automaticamente un nuevo JWT y lo almacena en la cookie HTTP-only.

Resultado (200 OK):
```json
{
  "mensaje": "Token renovado correctamente"
}
```

---

### Prueba 10 - Frontend completo

1. Abrir http://localhost:3000
2. Hacer clic en "Registrarse", completar el formulario y enviar
3. Redireccion automatica a login.html
4. Ingresar credenciales y hacer clic en "Iniciar Sesion"
5. Redireccion automatica a confirmacion.html con nombre y rol del usuario
6. Probar boton "Ruta Admin+Cliente": acceso permitido para ambos roles
7. Probar boton "Ruta Solo Admin": acceso permitido para Admin, 403 para Cliente
8. Hacer clic en "Cerrar Sesion": elimina la cookie y redirige a login.html

---

## Variables de entorno (.env auth-service)

| Variable | Descripcion | Valor por defecto |
|----------|-------------|-------------------|
| DATABASE_URL | Conexion a PostgreSQL | postgresql://postgres:admin@localhost:5432/auth_db |
| JWT_SECRET_KEY | Clave secreta para firmar JWT | - |
| JWT_EXPIRATION_MINUTES | Tiempo de vida del JWT en minutos | 30 |
| JWT_GRACE_PERIOD_MINUTES | Periodo de gracia para renovacion | 5 |
| AES_SECRET_KEY | Clave de 32 bytes para encriptacion AES | - |
| AUTHORIZATION_SERVICE_URL | URL del microservicio de autorizacion | http://localhost:8001 |
| AUTHORIZATION_MAX_RETRIES | Numero maximo de reintentos | 3 |
| AUTHORIZATION_RETRY_BACKOFF | Factor de backoff entre reintentos | 1.5 |

---

## Endpoints disponibles

### Auth Service (puerto 8000)

| Metodo | Endpoint | Descripcion | Autenticacion |
|--------|----------|-------------|---------------|
| POST | /auth/registro | Registrar nuevo usuario | No |
| POST | /auth/login | Iniciar sesion | No |
| POST | /auth/logout | Cerrar sesion | Si |
| POST | /auth/renovar-token | Renovar JWT expirado | Si |
| GET | /rutas/admin | Ruta exclusiva Admin | Si (Admin) |
| GET | /rutas/admin-cliente | Ruta Admin y Cliente | Si (Admin/Cliente) |

### Authorization Service (puerto 8001)

| Metodo | Endpoint | Descripcion |
|--------|----------|-------------|
| POST | /autorizar | Validar token y rol |

---

## Aplicación de Principios SOLID

A continuación se detalla cómo se ha diseñado la arquitectura del sistema respetando los 5 principios SOLID para garantizar un código limpio, mantenible y escalable.

### S - Single Responsibility Principle (Principio de Responsabilidad Única)

**Explicación:** Una clase, módulo o función debe tener una y solo una razón para cambiar. Esto significa que debe encargarse de una única tarea o responsabilidad específica dentro del sistema. Si un módulo hace demasiadas cosas, los cambios en una funcionalidad pueden afectar a otras de manera imprevista.

* **Archivo/Clase:** `src/services/encryption_service.py` y `src/services/auth_service.py`
* **Justificación:** Se ha delegado toda la lógica criptográfica (AES) a un servicio independiente. El servicio de autenticación no necesita saber *cómo* se encriptan los datos (tamaño de bloque, IV, modo CBC), solo necesita utilizarlos. Si el día de mañana se cambia el algoritmo de AES a ChaCha20, solo se modifica `encryption_service.py` y la lógica de autenticación (`auth_service.py`) permanece intacta.
* **Fragmento de código real:**

```python
# src/services/encryption_service.py
from Crypto.Cipher import AES
import os

class EncryptionService:
    def __init__(self, secret_key: bytes):
        self.secret_key = secret_key

    def encrypt_data(self, data: str) -> bytes:
        # Única responsabilidad: Encriptar datos
        iv = os.urandom(16)
        cipher = AES.new(self.secret_key, AES.MODE_CBC, iv)
        # ... lógica de padding y encriptación ...
        return iv + ciphertext

# src/services/auth_service.py
class AuthService:
    def __init__(self, db_session, enc_service: EncryptionService):
        self.db = db_session
        self.enc_service = enc_service

    def registrar_usuario(self, usuario_data):
        # Única responsabilidad: Orquestar el registro
        encrypted_pass = self.enc_service.encrypt_data(usuario_data.contrasena)
        # ... guardar en base de datos ...

```

### O - Open/Closed Principle (Principio de Abierto/Cerrado)

**Explicación:** Las entidades de software (clases, módulos, funciones) deben estar abiertas para su extensión, pero cerradas para su modificación. Esto significa que deberíamos poder agregar nueva funcionalidad o comportamiento sin alterar el código fuente ya existente, previniendo la introducción de nuevos bugs.

* **Archivo/Clase:** `src/schemas/usuario_schema.py`
* **Justificación:** Los esquemas de validación de Pydantic utilizan herencia de clases. Se define una clase abstracta `UsuarioBase` con los datos en común. Para crear respuestas, registros u otras variantes, se crean nuevas clases que heredan de la base. Si se necesita un nuevo tipo de usuario o una nueva vista de datos (por ejemplo, `UsuarioAdminResponse`), el código se *extiende* añadiendo una nueva clase, sin *modificar* el `UsuarioBase`.
* **Fragmento de código real:**

```python
# src/schemas/usuario_schema.py
from pydantic import BaseModel, EmailStr

class UsuarioBase(BaseModel):
    nombre: str
    correo: EmailStr
    rol: str

# Extendemos (Open for extension) sin modificar UsuarioBase (Closed for modification)
class UsuarioCreate(UsuarioBase):
    contrasena: str

class UsuarioResponse(UsuarioBase):
    id: str
    created_at: str

    class Config:
        orm_mode = True

```

### L - Liskov Substitution Principle (Principio de Sustitución de Liskov)

**Explicación:** Los objetos de una superclase deben poder ser reemplazados por objetos de sus subclases sin que el programa se rompa o altere su comportamiento esperado. Las clases derivadas deben cumplir el "contrato" definido por su clase padre.

* **Archivo/Clase:** `src/schemas/usuario_schema.py` (Polimorfismo en validaciones) y la manipulación en `auth_service.py`.
* **Justificación:** Como `UsuarioCreate` y `UsuarioResponse` extienden rigurosamente de `UsuarioBase`, en cualquier función de servicio o validación interna que espere un objeto del tipo `UsuarioBase` (para leer nombre, correo o rol), podemos pasar de forma segura un `UsuarioCreate` o un `UsuarioResponse`, sabiendo que ambas subclases respetan los tipos y propiedades de la clase base sin generar excepciones (como un `AttributeError`).
* **Fragmento de código real:**

```python
# Un validador genérico que espera la superclase
def validar_dominio_correo(usuario: UsuarioBase) -> bool:
    return usuario.correo.endswith("@test.com")

# Puede recibir una subclase (UsuarioCreate) sin alterar el funcionamiento
nuevo_usuario = UsuarioCreate(
    nombre="Maria Jose", 
    correo="admin@test.com", 
    rol="admin", 
    contrasena="pwd123"
)
es_valido = validar_dominio_correo(nuevo_usuario) # Retorna True de forma segura

```

### I - Interface Segregation Principle (Principio de Segregación de Interfaces)

**Explicación:** Los clientes no deben verse obligados a depender de interfaces (o esquemas de datos) que no utilizan. Es mejor crear varias interfaces específicas orientadas a un objetivo concreto, que una interfaz gigante de propósito general.

* **Archivo/Clase:** `src/schemas/usuario_schema.py`
* **Justificación:** Se han segregado las interfaces de entrada de la API. El endpoint de inicio de sesión (`/auth/login`) no requiere saber el `nombre` o el `rol` del usuario al momento de hacer el request, solo necesita `correo` y `contrasena`. En lugar de forzar al cliente frontend a enviar un solo objeto gigante `Usuario` con campos opcionales o nulos, se diseñó un esquema específico y segregado `UsuarioLogin`.
* **Fragmento de código real:**

```python
# src/schemas/usuario_schema.py
from pydantic import BaseModel, EmailStr

# Interfaz segregada exclusivamente para el proceso de Login
class UsuarioLogin(BaseModel):
    correo: EmailStr
    contrasena: str

# src/routes/auth.py
@router.post("/login")
def login(credenciales: UsuarioLogin, db: Session = Depends(get_db)):
    # El cliente no es forzado a enviar campos que no aplican a esta acción
    user = auth_service.authenticate(db, credenciales.correo, credenciales.contrasena)
    # ...

```

### D - Dependency Inversion Principle (Principio de Inversión de Dependencias)

**Explicación:** Los módulos de alto nivel (como los enrutadores/controladores) no deben depender de los módulos de bajo nivel (como la conexión a la base de datos). Ambos deben depender de abstracciones. Los detalles concretos (implementaciones) deben depender de estas abstracciones.

* **Archivo/Clase:** `src/routes/auth.py` y `src/models/database.py`
* **Justificación:** Los endpoints (módulo de alto nivel) no abren la conexión a PostgreSQL directamente ni instancian el motor de SQLAlchemy. En su lugar, el framework FastAPI inyecta la dependencia a través de `Depends(get_db)`. La ruta solo sabe que recibe un objeto que cumple con la interfaz de una sesión de base de datos. Esto desacopla el sistema y permite que, si queremos realizar pruebas unitarias, podamos inyectar un `mock_db` fácilmente sin tocar el código de la ruta.
* **Fragmento de código real:**

```python
# src/models/database.py
def get_db():
    db = SessionLocal()
    try:
        # Abstracción entregada por un yield (Generador)
        yield db
    finally:
        db.close()

# src/routes/auth.py
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from src.models.database import get_db

router = APIRouter()

@router.post("/registro", response_model=UsuarioResponse)
def registrar(usuario: UsuarioCreate, db: Session = Depends(get_db)):
    # La ruta no sabe de credenciales, puertos o motores (PostgreSQL vs SQLite)
    # Solo depende de la abstracción inyectada "Session"
    return auth_service.crear_usuario(db=db, usuario=usuario)

```