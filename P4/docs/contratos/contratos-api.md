# Contratos de API - Sistema de Biblioteca

## API Gateway: http://localhost:8080

---

## 1. Auth Service (Python - FastAPI)

### 1.1 Registro de usuario

    POST http://localhost:8080/auth/auth/registro
    Content-Type: application/json

    {
      "nombre": "Maria Jose",
      "correo": "majo@test.com",
      "contrasena": "Test1234!",
      "rol": "cliente"
    }

### 1.2 Login

    POST http://localhost:8080/auth/auth/login
    Content-Type: application/json

    {
      "correo": "majo@test.com",
      "contrasena": "Test1234!"
    }

### 1.3 Logout

    POST http://localhost:8080/auth/auth/logout

### 1.4 Renovar token

    POST http://localhost:8080/auth/auth/renovar-token

---

## 2. Books Service (Python - GraphQL)

### 2.1 Crear libro

    POST http://localhost:8080/books/graphql
    Content-Type: application/json

    {
      "query": "mutation { createBook(title: \"Cien años de soledad\", author: \"Gabriel García Márquez\", isbn: \"978-0307474728\", genre: \"Novela\") { id title author isbn genre available } }"
    }

### 2.2 Listar todos los libros

    POST http://localhost:8080/books/graphql
    Content-Type: application/json

    {
      "query": "{ books { id title author isbn genre available } }"
    }

### 2.3 Obtener libro por ID

    POST http://localhost:8080/books/graphql
    Content-Type: application/json

    {
      "query": "{ book(id: 1) { id title author isbn genre available } }"
    }

### 2.4 Actualizar disponibilidad

    POST http://localhost:8080/books/graphql
    Content-Type: application/json

    {
      "query": "mutation { updateBookAvailability(id: 1, available: false) { id title available } }"
    }

---

## 3. Loans Service (Node.js - GraphQL)

### 3.1 Crear préstamo

    POST http://localhost:8080/loans/graphql
    Content-Type: application/json

    {
      "query": "mutation { createLoan(userId: 1, bookId: 1) { id userId bookId status loanDate } }"
    }

### 3.2 Listar todos los préstamos

    POST http://localhost:8080/loans/graphql
    Content-Type: application/json

    {
      "query": "{ loans { id userId bookId status loanDate returnDate } }"
    }

### 3.3 Préstamos por usuario

    POST http://localhost:8080/loans/graphql
    Content-Type: application/json

    {
      "query": "{ loansByUser(userId: 1) { id bookId status loanDate } }"
    }

### 3.4 Devolver libro

    POST http://localhost:8080/loans/graphql
    Content-Type: application/json

    {
      "query": "mutation { returnLoan(id: 1) { id status returnDate } }"
    }

---

## 4. Notifications Service (Node.js - REST)

### 4.1 Crear notificación

    POST http://localhost:8080/notifications/notifications
    Content-Type: application/json

    {
      "userId": 1,
      "type": "loan_created",
      "message": "Se creó un préstamo del libro Cien años de soledad"
    }

### 4.2 Listar todas las notificaciones

    GET http://localhost:8080/notifications/notifications

### 4.3 Notificaciones por usuario

    GET http://localhost:8080/notifications/notifications/user/1

### 4.4 Marcar como leída

    PATCH http://localhost:8080/notifications/notifications/1/read

---

## 5. Health Checks

    GET http://localhost:8080/health
    GET http://localhost:8080/auth
    GET http://localhost:8080/books
    GET http://localhost:8080/loans
    GET http://localhost:8080/notifications