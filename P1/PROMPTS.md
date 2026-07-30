# Documentación de Prompts de IA

**Herramienta utilizada:** Claude (Anthropic)

Este documento registra los prompts utilizados durante el desarrollo de la API REST de Solicitudes Operativas, la respuesta obtenida en cada caso, y el análisis crítico o ajustes realizados sobre el código generado.

---

## Prompt 1: Diseño del modelo de base de datos y schemas de validación

### Prompt utilizado:

> "Necesito crear un modelo de SQLAlchemy para una tabla de 'solicitudes operativas' con los campos: id (UUID), titulo (string), area_solicitante (string), prioridad (entero 1-5), costo_estimado (decimal) y estado (string: registrada, en_proceso, finalizada). También necesito los schemas de Pydantic para crear, actualizar completamente y actualizar solo el estado. El código debe validar que prioridad esté entre 1 y 5, y que costo_estimado sea positivo, para evitar datos inválidos en la base de datos."

### Respuesta obtenida (resumen):

La IA generó el modelo `Solicitud` usando SQLAlchemy con `UUID` como llave primaria autogenerada, y tres schemas de Pydantic (`SolicitudCreate`, `SolicitudUpdate`, `SolicitudEstadoUpdate`) utilizando `Field()` con restricciones (`ge=1, le=5` para prioridad, `gt=0` para costo_estimado).

### Análisis y ajustes realizados:

- Se revisó que las validaciones (`ge`, `le`, `gt`) realmente se aplicaran a nivel de Pydantic y no solo como comentarios, confirmando que FastAPI las hace cumplir automáticamente devolviendo error 422 si se violan.
- Se agregó el campo `SolicitudEstadoUpdate` como un schema **separado** en lugar de reutilizar `SolicitudUpdate`, ya que el enunciado pedía un endpoint que actualizara *exclusivamente* el estado sin exponer el resto de los campos (esto refuerza el principio de Segregación de Interfaces).
- Se verificó que los campos `created_at` y `updated_at` se generaran automáticamente en el modelo usando `server_default=func.now()`, para no depender de que el cliente los enviara.

---

## Prompt 2: Generación de la lógica de negocio (Service Layer) y separación de responsabilidades

### Prompt utilizado:

> "Genera una clase de servicio en Python que contenga la lógica de negocio para crear, obtener, actualizar completamente, actualizar solo el estado, y eliminar solicitudes, usando SQLAlchemy Session. La clase no debe manejar nada relacionado con HTTP, ni debe crear su propia conexión a la base de datos, para poder inyectarla como dependencia. Aplica el principio de responsabilidad única."

### Respuesta obtenida (resumen):

La IA propuso una clase `SolicitudService` con métodos estáticos (`crear_solicitud`, `obtener_solicitud`, `obtener_todas_solicitudes`, `actualizar_solicitud`, `actualizar_estado`, `eliminar_solicitud`), todos recibiendo la sesión de base de datos (`db: Session`) como parámetro en lugar de crearla internamente.

### Análisis y ajustes realizados:

- Se corroboró que ningún método de `SolicitudService` importara o dependiera directamente de FastAPI, `HTTPException` ni de la creación del engine de SQLAlchemy, para mantener la capa de negocio desacoplada de la capa HTTP (Principio de Inversión de Dependencias).
- Se ajustó el método `actualizar_solicitud` para usar `model_dump(exclude_unset=True)` en lugar de iterar todos los campos del schema, evitando sobrescribir campos con `None` cuando el cliente no los envía explícitamente en una actualización parcial.
- Se agregó manejo explícito de los casos donde la solicitud no existe (retornando `None`), dejando que sea la capa de rutas la responsable de traducir eso a un error HTTP 404, manteniendo la separación de capas.

---

## Prompt 3: Generación de las rutas REST y manejo de errores HTTP

### Prompt utilizado:

> "Crea las rutas de FastAPI para los endpoints GET (todas), POST, GET por id, PUT, PATCH (solo estado) y DELETE de solicitudes. El código debe manejar errores devolviendo un 404 con un mensaje claro si la solicitud no existe, usar los schemas de Pydantic correspondientes para validar entrada y salida, e inyectar la sesión de base de datos usando Depends. Evita duplicación de código y usa nombres descriptivos para cada función."

### Respuesta obtenida (resumen):

La IA generó el archivo `solicitudes.py` con un `APIRouter`, definiendo cada endpoint con su método HTTP correspondiente, usando `Depends(get_db)` para inyectar la sesión, `response_model` para validar la salida, y bloques `if not solicitud: raise HTTPException(...)` para manejar los casos no encontrados.

### Análisis y ajustes realizados:

- Se verificó que el endpoint `DELETE` devolviera el código de estado `204 No Content` en lugar de `200`, siguiendo las convenciones REST correctas para operaciones de eliminación exitosas sin contenido de respuesta.
- Se confirmó que el prefijo del router (`prefix="/solicitudes"`) evitara repetir la ruta base en cada función, reduciendo duplicación.
- Se revisó que los mensajes de error del `HTTPException` incluyeran el ID de la solicitud buscada, para facilitar la depuración desde el cliente, sin exponer información sensible de la base de datos (por ejemplo, no se expone ningún detalle interno de SQLAlchemy en el mensaje de error, para evitar fugas de información y mitigar riesgos de seguridad como los descritos en OWASP Top 10).

---

## Prompt 4: Depuración de errores de compatibilidad de librerías

### Prompt utilizado:

> "Estoy obteniendo el error 'AssertionError: Class SQLCoreOperations directly inherits TypingOnly but has additional attributes' al importar SQLAlchemy en Python 3.14 en Windows. ¿Cuál es la causa y cómo lo soluciono sin cambiar de versión de Python?"

### Respuesta obtenida (resumen):

La IA identificó que el error se debía a una incompatibilidad entre la versión de SQLAlchemy instalada (2.0.x) y las nuevas características internas de `typing` en Python 3.14, recomendando actualizar a una versión de SQLAlchemy (2.1.0 beta) compatible con esa versión de Python, y advirtió que el driver `psycopg2` debía reemplazarse por `psycopg` (v3), ya que las versiones más nuevas de SQLAlchemy cambiaron el nombre del dialecto esperado.

### Análisis y ajustes realizados:

- Se validó el cambio actualizando `requirements.txt` con `sqlalchemy==2.1.0b3` y `psycopg==3.2.1`, y se comprobó que el servidor iniciara correctamente y creara la tabla `solicitudes` sin errores.
- Se documentó esta incidencia como parte del proceso de desarrollo, ya que refleja el uso **crítico** de la IA: no se aceptó la primera solución propuesta sin verificar (se probaron varias versiones de dependencias hasta confirmar cuál realmente resolvía el problema sin generar nuevos conflictos).
- Se dejó constancia de que el uso de una versión *beta* de SQLAlchemy es una decisión pragmática forzada por el entorno (Python 3.14 recién lanzado), y se recomienda en un entorno de producción real usar una versión de Python con soporte estable (3.11 o 3.12).

---

## Conclusión sobre el uso de IA

El uso de IA generativa en este proyecto se limitó a la generación de estructuras de código base y la resolución de errores técnicos de compatibilidad. En todos los casos se realizó una **revisión crítica** del código generado, verificando que cumpliera con los principios SOLID, las buenas prácticas de diseño REST, y que no introdujera vulnerabilidades de seguridad (como exponer detalles internos de la base de datos en mensajes de error, o no validar correctamente los datos de entrada).