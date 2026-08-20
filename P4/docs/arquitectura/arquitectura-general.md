# Diagrama de Arquitectura - Sistema de Biblioteca

## Arquitectura General

El sistema sigue una arquitectura de microservicios donde todas las peticiones externas pasan a través del API Gateway, que enruta hacia el microservicio correspondiente. Cada microservicio tiene su propia base de datos PostgreSQL (database-per-service pattern).

### Lenguajes utilizados

- **Python (FastAPI):** auth-service, books-service
- **Node.js (Express/Apollo):** loans-service, notifications-service, api-gateway

### Diagrama

```mermaid
graph TB
    Cliente["🖥️ Cliente / Thunder Client / Swagger"]

    subgraph API_GATEWAY["API Gateway (Node.js - Puerto 8080)"]
        GW["Express + http-proxy-middleware"]
    end

    Cliente -->|HTTP| GW

    subgraph PYTHON_SERVICES["Servicios Python"]
        AUTH["Auth Service<br/>(FastAPI - Puerto 8000)<br/>REST + JWT + AES"]
        BOOKS["Books Service<br/>(FastAPI + Strawberry - Puerto 8001)<br/>GraphQL"]
    end

    subgraph NODEJS_SERVICES["Servicios Node.js"]
        LOANS["Loans Service<br/>(Apollo Server - Puerto 8002)<br/>GraphQL"]
        NOTIF["Notifications Service<br/>(Express - Puerto 8003)<br/>REST"]
    end

    GW -->|"/auth/*"| AUTH
    GW -->|"/books/*"| BOOKS
    GW -->|"/loans/*"| LOANS
    GW -->|"/notifications/*"| NOTIF

    subgraph DATABASES["Bases de Datos PostgreSQL 15"]
        DB_AUTH[("auth_db")]
        DB_BOOKS[("books_db")]
        DB_LOANS[("loans_db")]
        DB_NOTIF[("notifications_db")]
    end

    AUTH --> DB_AUTH
    BOOKS --> DB_BOOKS
    LOANS --> DB_LOANS
    NOTIF --> DB_NOTIF
```

### Flujo de comunicación

1. El cliente envía una petición HTTP al API Gateway (puerto 8080)
2. El Gateway identifica la ruta y redirige al microservicio correspondiente
3. El microservicio procesa la petición y consulta su base de datos propia
4. La respuesta regresa al cliente a través del Gateway

### Puertos

| Servicio | Puerto | Protocolo |
|---|---|---|
| API Gateway | 8080 | HTTP/REST (proxy) |
| Auth Service | 8000 | HTTP/REST |
| Books Service | 8001 | HTTP/GraphQL |
| Loans Service | 8002 | HTTP/GraphQL |
| Notifications Service | 8003 | HTTP/REST |
