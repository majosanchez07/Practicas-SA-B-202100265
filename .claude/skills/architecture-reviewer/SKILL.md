---
name: architecture-reviewer
description: Revisa la arquitectura de Bank USAC y detecta acoplamiento, violaciones Saga, eventos inconsistentes y errores de diseño distribuido.
---

# Architecture Reviewer

Al revisar arquitectura:

1. Verificar que ningún microservicio consulte directamente la base de datos de otro.
2. Verificar comunicación asíncrona donde corresponda.
3. Verificar Saga.
4. Verificar idempotencia de consumidores.
5. Verificar correlationId de extremo a extremo.
6. Verificar contratos de eventos.
7. Verificar estados de negocio.
8. Verificar manejo explícito de errores.
9. Detectar dependencias circulares.
10. Detectar acoplamiento innecesario.

Antes de modificar código, explicar qué violación fue encontrada y proponer la corrección mínima.

