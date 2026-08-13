# Practica 3 - Diseno de Arquitectura

**Universidad de San Carlos de Guatemala**
**Facultad de Ingenieria**
**Ingenieria en Ciencias y Sistemas**
**Software Avanzado - Seccion B**

**Nombre:** Maria Jose Tebalan Sanchez
**Carne:** 202100265

---

## Descripcion del Proyecto

Diseno de arquitectura basada en microservicios para el sistema de procesamiento de transacciones bancarias de una institucion financiera. El sistema actual opera bajo un esquema monolitico que presenta problemas de rendimiento en epocas de alta demanda (fin de mes, pago de planillas masivas, temporadas de impuestos). Esta practica propone una solucion escalable y mantenible que resuelve ese problema mediante la separacion de responsabilidades en microservicios independientes, comunicacion asincrona y un flujo de aprobacion de 3 pasos.

---

## Arquitectura General

El sistema esta compuesto por 5 microservicios propios, un API Gateway, el modulo de autenticacion de la Practica 2 y multiples sistemas externos.

Diagrama completo: [docs/arquitectura/arquitectura-general.md](docs/arquitectura/arquitectura-general.md)

### Microservicios

| Servicio | Responsabilidad | Base de datos |
|----------|----------------|---------------|
| transaction-service | Carga de CSV, validacion de reglas de negocio, historial de lotes | PostgreSQL |
| approval-service | Flujo de aprobacion maker-checker-authorizer de 3 pasos | PostgreSQL |
| notification-service | Envio de correos electronicos a clientes y beneficiarios | PostgreSQL |
| core-banking-connector | Envio de transacciones al core bancario externo con reintentos | PostgreSQL |
| logging-service | Recepcion, almacenamiento y consulta de logs centralizados | MongoDB |

### Tecnologias utilizadas

| Componente | Tecnologia | Justificacion |
|------------|-----------|---------------|
| Microservicios | FastAPI / Python | Desarrollo rapido, documentacion automatica con OpenAPI, ideal para APIs REST |
| API Gateway | Kong / Nginx | Enrutamiento, validacion JWT y rate limiting en un solo punto de entrada |
| Mensajeria | RabbitMQ | Desacoplamiento entre servicios, garantia de entrega de mensajes, soporte AMQP |
| BD transaccional | PostgreSQL | Robustez, soporte ACID, ideal para datos financieros criticos |
| BD de logs | MongoDB | Esquema flexible para logs con estructura variable y metadata dinamica |
| Almacenamiento | AWS S3 | Alta disponibilidad, durabilidad, politicas de ciclo de vida automaticas |
| Autenticacion | OAuth 2.0 + JWT | Estandar de la industria, token de 12h para sesiones corporativas |
| Contenedores | Docker / Kubernetes | Portabilidad, escalado horizontal, despliegue reproducible |

---

## Integracion con Auth Service de la Practica 2

El sistema reutiliza el modulo de autenticacion desarrollado en la Practica 2 de la siguiente manera:

- **Auth Service P2** (puerto 8000): valida el JWT en cada request que llega al API Gateway. Si el token es invalido o ha expirado, el Gateway retorna 401 sin llegar al microservicio destino.
- **Authorization Service P2** (puerto 8001): verifica que el usuario tenga el rol requerido para ejecutar la accion solicitada (Maker, Checker, Authorizer). Usa el retry loop con backoff implementado en P2.
- El OAuth corporativo emite tokens con vida de 12 horas. El Auth Service P2 los valida y extrae el rol del usuario del payload JWT.

```
Cliente -> OAuth corporativo (token 12h)
        -> API Gateway
        -> Auth Service P2 (valida JWT)
        -> Authorization Service P2 (valida rol)
        -> Microservicio destino
```

---

## Flujo de Aprobacion de 3 Pasos

El sistema implementa el esquema maker-checker-authorizer para garantizar que ningun lote sea procesado sin la revision de tres usuarios con roles distintos.

| Paso | Rol | Accion |
|------|-----|--------|
| 1 | Maker | Carga el CSV y crea el lote |
| 2 | Checker | Revisa y aprueba el contenido del lote |
| 3 | Authorizer | Aprueba definitivamente y dispara el envio |

Al completarse el paso 3, el approval-service publica un evento en RabbitMQ que es consumido simultaneamente por el notification-service (correos a clientes) y el core-banking-connector (envio al core bancario).

Documentacion detallada: [docs/flujos/flujo-aprobacion.md](docs/flujos/flujo-aprobacion.md)

---

## Reglas de Validacion del Negocio

El transaction-service aplica las siguientes reglas sobre cada transaccion del CSV antes de permitir que el lote avance en el flujo de aprobacion:

| Regla | Descripcion |
|-------|-------------|
| Saldo disponible | La cuenta origen debe tener saldo suficiente para cubrir el monto |
| Limite de transaccion | El monto no puede superar el limite configurado segun el tipo de transaccion |
| Cuentas validas | Las cuentas origen y destino deben existir y estar activas |
| Prevencion de fraude | Se detectan patrones anomalos como multiples transacciones al mismo destino |
| Formato CSV | Cabeceras obligatorias, encoding UTF-8, delimitador coma |

---

## Estrategia de Almacenamiento de Archivos CSV

Los archivos CSV son almacenados en AWS S3 antes de ser procesados. La ruta queda registrada en la base de datos del transaction-service y el historial es consultable y descargable en todo momento mediante presigned URLs.

Documentacion detallada: [docs/flujos/estrategia-almacenamiento-csv.md](docs/flujos/estrategia-almacenamiento-csv.md)

---

## Estrategia de Logging Centralizado

Todos los microservicios publican sus logs a RabbitMQ. El logging-service los consume y persiste en MongoDB. Cada log incluye un trace_id que permite rastrear una operacion a traves de multiples servicios. Las acciones de usuarios quedan en una tabla de auditoria independiente.

Documentacion detallada: [docs/flujos/estrategia-logging.md](docs/flujos/estrategia-logging.md)

---

## Comunicacion entre Servicios

- **REST sincrono**: para operaciones que requieren respuesta inmediata (validaciones, consultas, CRUD).
- **RabbitMQ asincrono**: para eventos de negocio que pueden ser consumidos por multiples servicios (lote aprobado, logs).

Documentacion detallada: [docs/flujos/comunicacion-entre-servicios.md](docs/flujos/comunicacion-entre-servicios.md)

---

## Propuesta de API Gateway

El API Gateway es el unico punto de entrada al sistema desde el frontend. Sus responsabilidades son:

- Enrutar cada peticion al microservicio correspondiente segun el path.
- Validar el JWT contra el Auth Service de la Practica 2 antes de reenviar la peticion.
- Aplicar rate limiting para prevenir abuso y ataques de fuerza bruta.
- Centralizar el logging de entrada (quien llamo, a que endpoint, cuando).
- Ocultar la topologia interna de microservicios al cliente externo.

**Tecnologia propuesta:** Kong o Nginx con modulo de autenticacion JWT. Ambas opciones son gratuitas, ampliamente documentadas y compatibles con despliegues en Docker/Kubernetes.

---

## Diagramas UML

| Tipo | Ubicacion |
|------|-----------|
| Diagramas ER (5) | [docs/er/](docs/er/) |
| Diagramas de clases (5) | [docs/uml/clases/](docs/uml/clases/) |
| Diagramas de secuencia (3) | [docs/uml/secuencia/](docs/uml/secuencia/) |
| Diagrama de componentes | [docs/uml/componentes/componentes-sistema.md](docs/uml/componentes/componentes-sistema.md) |

---

## Estructura del Repositorio

```
P3/
├── docs/
│   ├── arquitectura/
│   │   └── arquitectura-general.md
│   ├── er/
│   │   ├── er-transaction-service.md
│   │   ├── er-approval-service.md
│   │   ├── er-notification-service.md
│   │   ├── er-core-banking-connector.md
│   │   └── er-logging-service.md
│   ├── uml/
│   │   ├── clases/
│   │   │   ├── clases-transaction-service.md
│   │   │   ├── clases-approval-service.md
│   │   │   ├── clases-notification-service.md
│   │   │   ├── clases-core-banking-connector.md
│   │   │   └── clases-logging-service.md
│   │   ├── secuencia/
│   │   │   ├── secuencia-flujo-aprobacion.md
│   │   │   ├── secuencia-envio-core-bancario.md
│   │   │   └── secuencia-notificacion-clientes.md
│   │   └── componentes/
│   │       └── componentes-sistema.md
│   └── flujos/
│       ├── flujo-aprobacion.md
│       ├── estrategia-almacenamiento-csv.md
│       ├── estrategia-logging.md
│       └── comunicacion-entre-servicios.md
└── README.md
```

---

## Referencias

- Sam Newman - Building Microservices (O'Reilly)
- Documentacion oficial de OAuth 2.0
- Documentacion de Apache Kafka y RabbitMQ
- AWS Architecture Best Practices
- GCP Architecture Framework
- API Gateway Pattern - Microsoft