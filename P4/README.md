# Práctica 4 - Diseño y Toma de Decisiones

**Estudiante:** Maria Jose Tebalan Sanchez  
**Carnet:** 202100265  
**Curso:** Software Avanzado - Segundo Semestre 2026

---

## Descripción del Sistema

Sistema de gestión de biblioteca basado en arquitectura de microservicios, contenedorizado con Docker e integrado mediante un API Gateway. El sistema permite gestionar libros, préstamos, notificaciones y autenticación de usuarios.

---

## Arquitectura

El sistema está compuesto por 5 microservicios independientes, cada uno con su propia base de datos PostgreSQL:

| Servicio | Lenguaje | Puerto | Descripción |
|---|---|---|---|
| api-gateway | Node.js | 8080 | Enruta peticiones a todos los microservicios |
| auth-service | Python (FastAPI) | 8000 | Autenticación y autorización con JWT (de P2) |
| books-service | Python (FastAPI + Strawberry) | 8001 | Catálogo de libros con GraphQL |
| loans-service | Node.js (Apollo Server) | 8002 | Préstamos de libros con GraphQL |
| notifications-service | Node.js (Express) | 8003 | Notificaciones REST |

---

## Tecnologías utilizadas

- **Python** — FastAPI, Strawberry GraphQL, SQLAlchemy, Uvicorn
- **Node.js** — Express, Apollo Server, Sequelize
- **GraphQL** — Implementado en books-service y loans-service
- **Docker** — Dockerfile individual por cada microservicio
- **Docker Compose** — Orquestación de todos los servicios
- **PostgreSQL** — Base de datos separada por microservicio (4 instancias)

---

## Cómo levantar el sistema

Desde la carpeta P4 ejecutar:

    cd P4
    docker compose up --build

El sistema completo estará disponible en http://localhost:8080

Para detener el sistema:

    docker compose down

---

## Cómo probar los servicios

### Swagger (Auth y Books - servicios Python)

- Auth Service: http://localhost:8000/docs
- Books Service: http://localhost:8001/docs

### GraphQL Playground

- Books GraphQL: http://localhost:8001/graphql
- Loans GraphQL: http://localhost:8002/graphql

### API Gateway (punto de entrada unificado)

Todas las peticiones se pueden hacer a través del gateway en http://localhost:8080:

- http://localhost:8080/auth/auth/registro — Registro de usuario
- http://localhost:8080/auth/auth/login — Login
- http://localhost:8080/books/graphql — GraphQL de libros
- http://localhost:8080/loans/graphql — GraphQL de préstamos
- http://localhost:8080/notifications/notifications — Notificaciones REST

---

## Endpoints disponibles

### Auth Service (/auth) - REST

| Método | Ruta | Descripción |
|---|---|---|
| POST | /auth/auth/registro | Registro de usuario |
| POST | /auth/auth/login | Login y obtención de JWT |
| POST | /auth/auth/logout | Cierre de sesión |
| POST | /auth/auth/renovar-token | Renovar JWT |

**Ejemplo registro:**

    POST http://localhost:8080/auth/auth/registro
    Content-Type: application/json

    {
      "nombre": "Maria Jose",
      "correo": "majo@test.com",
      "contrasena": "Test1234!",
      "rol": "cliente"
    }

**Ejemplo login:**

    POST http://localhost:8080/auth/auth/login
    Content-Type: application/json

    {
      "correo": "majo@test.com",
      "contrasena": "Test1234!"
    }

### Books Service (/books) - GraphQL

Endpoint: POST /books/graphql

**Crear libro:**

    {
      "query": "mutation { createBook(title: \"Cien años de soledad\", author: \"Gabriel García Márquez\", isbn: \"978-0307474728\", genre: \"Novela\") { id title author isbn genre available } }"
    }

**Listar libros:**

    {
      "query": "{ books { id title author isbn genre available } }"
    }

**Obtener libro por ID:**

    {
      "query": "{ book(id: 1) { id title author isbn genre available } }"
    }

**Actualizar disponibilidad:**

    {
      "query": "mutation { updateBookAvailability(id: 1, available: false) { id title available } }"
    }

### Loans Service (/loans) - GraphQL

Endpoint: POST /loans/graphql

**Crear préstamo:**

    {
      "query": "mutation { createLoan(userId: 1, bookId: 1) { id userId bookId status loanDate } }"
    }

**Listar préstamos:**

    {
      "query": "{ loans { id userId bookId status loanDate returnDate } }"
    }

**Préstamos por usuario:**

    {
      "query": "{ loansByUser(userId: 1) { id bookId status loanDate } }"
    }

**Devolver libro:**

    {
      "query": "mutation { returnLoan(id: 1) { id status returnDate } }"
    }

### Notifications Service (/notifications) - REST

| Método | Ruta | Descripción |
|---|---|---|
| GET | /notifications/notifications | Lista todas las notificaciones |
| GET | /notifications/notifications/user/:id | Notificaciones por usuario |
| POST | /notifications/notifications | Crear notificación |
| PATCH | /notifications/notifications/:id/read | Marcar como leída |

**Crear notificación:**

    POST http://localhost:8080/notifications/notifications
    Content-Type: application/json

    {
      "userId": 1,
      "type": "loan_created",
      "message": "Se creó un préstamo del libro Cien años de soledad"
    }

### Health Checks

    GET http://localhost:8080/health
    GET http://localhost:8080/auth
    GET http://localhost:8080/books
    GET http://localhost:8080/loans
    GET http://localhost:8080/notifications

---

## Principios SOLID aplicados

### 1. Single Responsibility Principle (SRP) — Principio de Responsabilidad Única

Cada clase y cada microservicio tiene una sola razón para cambiar. En lugar de crear un monolito que maneje todo, el sistema se divide en servicios especializados donde cada uno se enfoca en una sola área del negocio.

**Evidencia en el código:**

- `books-service/src/models/book.py` — El modelo Book solo define la estructura de datos de un libro (columnas, tipos, constraints). No contiene lógica de negocio ni de presentación.
- `books-service/src/graphql/schema.py` — El schema GraphQL solo maneja la lógica de consultas y mutaciones. La definición del modelo está separada.
- `notifications-service/src/routes/notifications.js` — Las rutas solo manejan peticiones HTTP. El modelo de datos está en un archivo aparte.

### 2. Open/Closed Principle (OCP) — Principio Abierto/Cerrado

Las entidades de software deben estar abiertas para extensión pero cerradas para modificación. Se pueden agregar nuevas funcionalidades sin tocar el código existente.

**Evidencia en el código:**

- `notifications-service/src/models/notification.js` — El campo `type` usa un ENUM (`loan_created`, `loan_returned`, `loan_overdue`). Para agregar un nuevo tipo de notificación, solo se agrega un nuevo valor al ENUM sin modificar la lógica de las rutas existentes.
- `api-gateway/src/index.js` — Para agregar un nuevo microservicio, solo se agrega una nueva regla de proxy. Las reglas existentes no se modifican.

### 3. Liskov Substitution Principle (LSP) — Principio de Sustitución de Liskov

Los objetos de un subtipo deben poder sustituir a los de su tipo base sin alterar el comportamiento del programa. En el contexto de microservicios, cada servicio expone interfaces estándar que se pueden consumir de forma uniforme.

**Evidencia en el código:**

- Todos los microservicios exponen endpoints `/` y `/health` con el mismo formato de respuesta JSON. El API Gateway puede tratar cualquier servicio de la misma forma sin conocer su implementación interna.
- `api-gateway/src/index.js` — Cada servicio se registra como proxy con la misma estructura: target, pathRewrite y manejo de errores idéntico.

### 4. Interface Segregation Principle (ISP) — Principio de Segregación de Interfaces

Los clientes no deben verse forzados a depender de interfaces que no utilizan. Cada servicio expone solo los endpoints que son relevantes para su dominio.

**Evidencia en el código:**

- `notifications-service/src/routes/notifications.js` — Expone solo 4 operaciones (GET todas, GET por usuario, POST crear, PATCH marcar leída). Un cliente que solo necesita leer notificaciones no tiene que conocer la interfaz de creación.
- `books-service/src/graphql/schema.py` — GraphQL permite que el cliente solicite solo los campos que necesita. Si solo necesita `title` y `available`, no recibe `isbn`, `genre`, etc.

### 5. Dependency Inversion Principle (DIP) — Principio de Inversión de Dependencias

Los módulos de alto nivel no deben depender de módulos de bajo nivel. Ambos deben depender de abstracciones. Las dependencias se inyectan a través de configuración externa.

**Evidencia en el código:**

- `api-gateway/src/index.js` — Las URLs de los microservicios se inyectan mediante variables de entorno (`process.env.AUTH_SERVICE_URL`), no están hardcodeadas. Si cambia la ubicación de un servicio, solo se modifica el `.env`.
- `books-service/src/config.py` — La conexión a base de datos se configura mediante la variable `DATABASE_URL`. El servicio no sabe si se conecta a PostgreSQL local, remoto o en Docker.
- `auth-service/src/models/database.py` — La función `get_db()` actúa como inyección de dependencias para las rutas de FastAPI usando `Depends(get_db)`.

---

## Estructura del repositorio

    P4/
    ├── docker-compose.yml
    ├── README.md
    ├── api-gateway/
    │   ├── Dockerfile
    │   ├── package.json
    │   ├── .env
    │   └── src/
    │       └── index.js
    ├── auth-service/
    │   ├── Dockerfile
    │   ├── requirements.txt
    │   ├── main.py
    │   ├── .env
    │   └── src/
    │       ├── config.py
    │       ├── models/
    │       ├── routes/
    │       ├── schemas/
    │       └── services/
    ├── books-service/
    │   ├── Dockerfile
    │   ├── requirements.txt
    │   ├── main.py
    │   ├── .env
    │   └── src/
    │       ├── config.py
    │       ├── models/
    │       └── graphql/
    ├── loans-service/
    │   ├── Dockerfile
    │   ├── package.json
    │   ├── .env
    │   └── src/
    │       ├── index.js
    │       ├── models/
    │       └── graphql/
    ├── notifications-service/
    │   ├── Dockerfile
    │   ├── package.json
    │   ├── .env
    │   └── src/
    │       ├── index.js
    │       ├── models/
    │       └── routes/
    └── docs/
        ├── arquitectura/
        ├── er/
        └── contratos/