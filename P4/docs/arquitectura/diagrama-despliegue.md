# Diagrama de Despliegue - Sistema de Biblioteca

## Infraestructura Docker

Todos los servicios corren como contenedores Docker orquestados por Docker Compose en una red bridge compartida llamada `biblioteca-net`.

### Diagrama

```mermaid
graph TB
    subgraph HOST["Host Local (Linux)"]
        subgraph DOCKER["Docker Engine"]
            subgraph NETWORK["Red: biblioteca-net (bridge)"]

                subgraph GATEWAY_CONTAINER["Contenedor: api-gateway"]
                    GW_IMG["Imagen: node:18-alpine<br/>Puerto expuesto: 8080:8080"]
                end

                subgraph AUTH_CONTAINER["Contenedor: auth-service"]
                    AUTH_IMG["Imagen: python:3.11-slim<br/>Puerto expuesto: 8000:8000"]
                end

                subgraph BOOKS_CONTAINER["Contenedor: books-service"]
                    BOOKS_IMG["Imagen: python:3.11-slim<br/>Puerto expuesto: 8001:8001"]
                end

                subgraph LOANS_CONTAINER["Contenedor: loans-service"]
                    LOANS_IMG["Imagen: node:18-alpine<br/>Puerto expuesto: 8002:8002"]
                end

                subgraph NOTIF_CONTAINER["Contenedor: notifications-service"]
                    NOTIF_IMG["Imagen: node:18-alpine<br/>Puerto expuesto: 8003:8003"]
                end

                subgraph DB_AUTH_CONTAINER["Contenedor: postgres-auth"]
                    DB_AUTH_IMG["Imagen: postgres:15-alpine<br/>Puerto interno: 5432<br/>Volume: pgdata-auth"]
                end

                subgraph DB_BOOKS_CONTAINER["Contenedor: postgres-books"]
                    DB_BOOKS_IMG["Imagen: postgres:15-alpine<br/>Puerto interno: 5432<br/>Volume: pgdata-books"]
                end

                subgraph DB_LOANS_CONTAINER["Contenedor: postgres-loans"]
                    DB_LOANS_IMG["Imagen: postgres:15-alpine<br/>Puerto interno: 5432<br/>Volume: pgdata-loans"]
                end

                subgraph DB_NOTIF_CONTAINER["Contenedor: postgres-notifications"]
                    DB_NOTIF_IMG["Imagen: postgres:15-alpine<br/>Puerto interno: 5432<br/>Volume: pgdata-notifications"]
                end
            end
        end
    end

    GW_IMG --> AUTH_IMG
    GW_IMG --> BOOKS_IMG
    GW_IMG --> LOANS_IMG
    GW_IMG --> NOTIF_IMG

    AUTH_IMG --> DB_AUTH_IMG
    BOOKS_IMG --> DB_BOOKS_IMG
    LOANS_IMG --> DB_LOANS_IMG
    NOTIF_IMG --> DB_NOTIF_IMG
```

### Contenedores del sistema

| Contenedor | Imagen Base | Puerto Expuesto | Depende de |
|---|---|---|---|
| api-gateway | node:18-alpine | 8080 | auth, books, loans, notifications |
| auth-service | python:3.11-slim | 8000 | postgres-auth |
| books-service | python:3.11-slim | 8001 | postgres-books |
| loans-service | node:18-alpine | 8002 | postgres-loans |
| notifications-service | node:18-alpine | 8003 | postgres-notifications |
| postgres-auth | postgres:15-alpine | interno | - |
| postgres-books | postgres:15-alpine | interno | - |
| postgres-loans | postgres:15-alpine | interno | - |
| postgres-notifications | postgres:15-alpine | interno | - |

### Volúmenes persistentes

| Volumen | Contenedor | Ruta interna |
|---|---|---|
| pgdata-auth | postgres-auth | /var/lib/postgresql/data |
| pgdata-books | postgres-books | /var/lib/postgresql/data |
| pgdata-loans | postgres-loans | /var/lib/postgresql/data |
| pgdata-notifications | postgres-notifications | /var/lib/postgresql/data |

### Comando de despliegue

    docker compose up --build

### Comando para detener

    docker compose down

### Comando para limpiar todo (incluyendo volúmenes)

    docker compose down -v
