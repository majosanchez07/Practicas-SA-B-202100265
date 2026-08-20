# Diagramas Entidad-Relación - Sistema de Biblioteca

Cada microservicio tiene su propia base de datos PostgreSQL independiente, siguiendo el patrón database-per-service.

---

## 1. Auth Service — auth_db

```mermaid
erDiagram
    USUARIOS {
        uuid id PK
        text nombre "Encriptado AES"
        text correo "Encriptado AES"
        text contrasena "Encriptada AES"
        varchar rol "cliente | admin"
        timestamp created_at
    }
```

**Descripción:** Almacena los usuarios del sistema. Los campos nombre, correo y contraseña están encriptados con AES para proteger datos sensibles. El campo rol determina los permisos del usuario.

---

## 2. Books Service — books_db

```mermaid
erDiagram
    BOOKS {
        integer id PK
        varchar_200 title "Título del libro"
        varchar_100 author "Autor del libro"
        varchar_20 isbn UK "ISBN único"
        varchar_50 genre "Género literario"
        boolean available "Disponible para préstamo"
        timestamp created_at
    }
```

**Descripción:** Catálogo de libros de la biblioteca. El campo isbn es único para evitar duplicados. El campo available indica si el libro está disponible para préstamo.

---

## 3. Loans Service — loans_db

```mermaid
erDiagram
    LOANS {
        integer id PK
        integer userId "ID del usuario que solicita"
        integer bookId "ID del libro prestado"
        timestamp loanDate "Fecha del préstamo"
        timestamp returnDate "Fecha de devolución (nullable)"
        enum status "active | returned | overdue"
        timestamp createdAt
        timestamp updatedAt
    }
```

**Descripción:** Registra los préstamos de libros. El campo status controla el ciclo de vida del préstamo: inicia como active, cambia a returned cuando se devuelve, o a overdue si se pasa la fecha límite. El userId y bookId son referencias lógicas a los otros microservicios.

---

## 4. Notifications Service — notifications_db

```mermaid
erDiagram
    NOTIFICATIONS {
        integer id PK
        integer userId "ID del usuario destinatario"
        enum type "loan_created | loan_returned | loan_overdue"
        text message "Contenido de la notificación"
        boolean read "Leída o no leída"
        timestamp createdAt
        timestamp updatedAt
    }
```

**Descripción:** Almacena las notificaciones del sistema. Cada notificación está asociada a un usuario y tiene un tipo que indica el evento que la generó. El campo read permite al usuario marcarla como leída.

---

## Relaciones lógicas entre servicios

Las relaciones entre microservicios son lógicas (no foreign keys directas), respetando el desacoplamiento:

```mermaid
graph LR
    USERS["usuarios (auth_db)"]
    BOOKS_T["books (books_db)"]
    LOANS_T["loans (loans_db)"]
    NOTIF_T["notifications (notifications_db)"]

    LOANS_T -->|"userId (lógica)"| USERS
    LOANS_T -->|"bookId (lógica)"| BOOKS_T
    NOTIF_T -->|"userId (lógica)"| USERS
```

> **Nota:** No existen foreign keys entre bases de datos distintas. Las referencias son lógicas y la consistencia se maneja a nivel de aplicación, siguiendo el principio de desacoplamiento de microservicios.
