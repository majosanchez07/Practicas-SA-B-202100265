# Universidad de San Carlos de Guatemala
## Facultad de Ingeniería
### Ingeniería en Ciencias y Sistemas
#### Software Avanzado — Sección B

**Nombre:** Maria Jose Tebalan Sanchez
**Carné:** 202100265

## Práctica # 1

---

# API REST - Gestión de Solicitudes Operativas

## Descripción del proyecto

API REST desarrollada con **FastAPI** y **PostgreSQL** para gestionar las solicitudes operativas de una academia ficticia. El sistema permite registrar, consultar, actualizar y eliminar solicitudes, aplicando los principios SOLID y buenas prácticas de código limpio, con el apoyo crítico de herramientas de Inteligencia Artificial generativa.

## Tecnologías utilizadas

- **Lenguaje:** Python 3.14
- **Framework:** FastAPI
- **ORM:** SQLAlchemy
- **Base de datos:** PostgreSQL
- **Driver de BD:** psycopg (v3)
- **Servidor:** Uvicorn

## Estructura de la práctica

P1/
├── src/
│ ├── models/
│ │ ├── solicitud.py # Modelo de datos (entidad)
│ │ └── database.py # Conexión a la base de datos
│ ├── schemas/
│ │ └── solicitud_schema.py # Validación de entrada/salida (Pydantic)
│ ├── services/
│ │ └── solicitud_service.py # Lógica de negocio
│ ├── routes/
│ │ └── solicitudes.py # Endpoints de la API
│ └── config.py # Configuración de la app
├── main.py # Punto de entrada
├── requirements.txt
├── .env
├── README.md
└── PROMPTS.md

## Endpoints disponibles

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| GET | `/solicitudes/` | Obtener todas las solicitudes |
| POST | `/solicitudes/` | Registrar una nueva solicitud |
| GET | `/solicitudes/{id}` | Obtener una solicitud por ID |
| PUT | `/solicitudes/{id}` | Actualizar completamente una solicitud |
| PATCH | `/solicitudes/{id}/estado` | Actualizar solo el estado |
| DELETE | `/solicitudes/{id}` | Eliminar una solicitud |

## Instalación y ejecución

```bash
# Crear entorno virtual
python -m venv venv
.\venv\Scripts\Activate.ps1

# Instalar dependencias
pip install -r requirements.txt

# Configurar variables de entorno en .env
# DATABASE_URL=postgresql://usuario:contraseña@localhost:5432/solicitudes_db

# Ejecutar el servidor
python main.py
```

La documentación interactiva estará disponible en: `http://localhost:8000/docs`

---

## Aplicación de Principios SOLID

A continuación se explica, con palabras propias, cómo se aplicó cada uno de los 5 principios SOLID en este proyecto, junto con la justificación de su importancia y fragmentos reales de código que evidencian su implementación.

### 1. S — Single Responsibility Principle (Principio de Responsabilidad Única)

**¿Qué significa?**

Este principio establece que una clase o módulo debe tener una única razón para cambiar. Es decir, cada componente del sistema debe encargarse de una sola responsabilidad bien definida. Si una clase mezcla varias responsabilidades (por ejemplo, validar datos, acceder a la base de datos y manejar peticiones HTTP al mismo tiempo), cualquier cambio en una de esas áreas obligaría a modificar la misma clase por razones distintas, lo cual aumenta el riesgo de introducir errores y dificulta el mantenimiento.

**¿Por qué es importante en este proyecto?**

Al gestionar solicitudes operativas, es común que en el futuro se necesiten cambios independientes: quizás cambie la forma en que se valida un campo, o se decida usar otra base de datos, o se agregue un nuevo endpoint. Separar responsabilidades permite que estos cambios se hagan de forma aislada sin afectar el resto del sistema.

**¿Cómo se aplicó?**

Dividí el proyecto en capas claramente diferenciadas, cada una con una sola responsabilidad:

- **Modelos** (`src/models/`): solo definen la estructura de datos que se persiste en la base de datos.
- **Schemas** (`src/schemas/`): solo validan los datos de entrada y salida de la API.
- **Servicios** (`src/services/`): solo contienen la lógica de negocio (crear, consultar, actualizar, eliminar).
- **Rutas** (`src/routes/`): solo exponen los endpoints HTTP y delegan el trabajo a los servicios.

Por ejemplo, `SolicitudService` se encarga exclusivamente de la lógica de negocio para interactuar con la base de datos, sin saber nada sobre HTTP, códigos de estado o formatos de petición:

```python
class SolicitudService:
    """Servicio para gestionar solicitudes operativas"""

    @staticmethod
    def crear_solicitud(db: Session, solicitud: SolicitudCreate) -> Solicitud:
        """Crear una nueva solicitud"""
        nueva_solicitud = Solicitud(
            titulo=solicitud.titulo,
            area_solicitante=solicitud.area_solicitante,
            prioridad=solicitud.prioridad,
            costo_estimado=solicitud.costo_estimado,
            estado=solicitud.estado
        )
        db.add(nueva_solicitud)
        db.commit()
        db.refresh(nueva_solicitud)
        return nueva_solicitud
```

Mientras que la ruta (`solicitudes.py`) solo se encarga de recibir la petición HTTP, delegar el trabajo al servicio y devolver la respuesta adecuada:

```python
@router.post("/", response_model=SolicitudResponse, status_code=status.HTTP_201_CREATED)
def crear_solicitud(solicitud: SolicitudCreate, db: Session = Depends(get_db)):
    """Registrar una nueva solicitud operativa"""
    nueva_solicitud = SolicitudService.crear_solicitud(db, solicitud)
    return nueva_solicitud
```

Si en el futuro cambia la forma de crear una solicitud (por ejemplo, agregando una validación de negocio adicional), solo se modifica `SolicitudService`, sin tocar la ruta ni los schemas.

---

### 2. O — Open/Closed Principle (Principio de Abierto/Cerrado)

**¿Qué significa?**

Este principio indica que las entidades de software (clases, módulos, funciones) deben estar **abiertas para su extensión**, pero **cerradas para su modificación**. Esto significa que se debe poder agregar nueva funcionalidad al sistema sin alterar el código que ya funciona y que ya ha sido probado.

**¿Por qué es importante en este proyecto?**

Un sistema de gestión de solicitudes operativas probablemente crecerá con el tiempo: podrían agregarse nuevos tipos de solicitudes, nuevos campos, o nuevas validaciones. Si cada nuevo requerimiento obliga a modificar clases ya existentes, se corre el riesgo de romper funcionalidad que ya funcionaba correctamente.

**¿Cómo se aplicó?**

Los schemas de Pydantic están diseñados con **herencia**, de forma que `SolicitudCreate` y `SolicitudResponse` extienden de `SolicitudBase` sin necesidad de modificar la clase base:

```python
class SolicitudBase(BaseModel):
    """Schema base para solicitudes"""
    titulo: str = Field(..., min_length=1, max_length=255)
    area_solicitante: str = Field(..., min_length=1, max_length=255)
    prioridad: int = Field(..., ge=1, le=5)
    costo_estimado: float = Field(..., gt=0)
    estado: str = Field(default="registrada")

class SolicitudCreate(SolicitudBase):
    """Schema para crear una solicitud"""
    pass

class SolicitudResponse(SolicitudBase):
    """Schema para respuestas de solicitudes"""
    id: UUID
    created_at: datetime
    updated_at: datetime
```

Si en el futuro se necesita un nuevo tipo de schema (por ejemplo, un schema para generar reportes con campos adicionales), se puede crear una nueva clase que extienda `SolicitudBase`, sin modificar ni una sola línea de la clase original.

De la misma manera, `SolicitudService` está diseñado para poder **extenderse** agregando nuevos métodos estáticos (por ejemplo, un método para filtrar solicitudes por prioridad o por área solicitante) sin necesidad de modificar los métodos ya existentes como `crear_solicitud`, `actualizar_solicitud` o `eliminar_solicitud`. Esto reduce el riesgo de introducir errores en funcionalidad ya validada.

---

### 3. L — Liskov Substitution Principle (Principio de Sustitución de Liskov)

**¿Qué significa?**

Este principio establece que los objetos de una clase derivada deben poder sustituir a los objetos de su clase base sin alterar el comportamiento correcto del programa. En otras palabras, si el sistema espera un objeto de un tipo determinado, debe poder recibir cualquier subtipo de ese tipo sin que el programa falle o se comporte de forma inesperada.

**¿Por qué es importante en este proyecto?**

En este sistema existen distintos tipos de "entrada" para actualizar una solicitud: una actualización completa y una actualización parcial (solo el estado). Es importante que el servicio que procesa estas actualizaciones pueda trabajar con cualquiera de estos schemas sin romper su lógica interna.

**¿Cómo se aplicó?**

`SolicitudUpdate` y `SolicitudEstadoUpdate` son schemas diseñados para actuar como una "entrada válida" en el proceso de actualización, cada uno adaptado a un contexto distinto (actualización completa vs. actualización parcial del estado), pero ambos respetan el mismo contrato: ser un objeto validado por Pydantic del cual se pueden extraer atributos de forma segura.

```python
class SolicitudUpdate(BaseModel):
    """Schema para actualizar una solicitud completa"""
    titulo: Optional[str] = Field(None, min_length=1, max_length=255)
    area_solicitante: Optional[str] = Field(None, min_length=1, max_length=255)
    prioridad: Optional[int] = Field(None, ge=1, le=5)
    costo_estimado: Optional[float] = Field(None, gt=0)
    estado: Optional[str] = None

class SolicitudEstadoUpdate(BaseModel):
    """Schema para actualizar solo el estado"""
    estado: str = Field(..., description="Nuevo estado de la solicitud")
```

Ambos esquemas pueden ser usados por métodos del servicio a través de `.model_dump(exclude_unset=True)`, garantizando que cualquier subtipo de entrada de actualización se comporte de manera consistente sin que el servicio necesite conocer detalles internos de cada schema en particular:

```python
@staticmethod
def actualizar_solicitud(db: Session, solicitud_id: UUID, solicitud_update: SolicitudUpdate) -> Optional[Solicitud]:
    """Actualizar completamente una solicitud"""
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
    if not solicitud:
        return None
    
    datos_actualizacion = solicitud_update.model_dump(exclude_unset=True)
    for campo, valor in datos_actualizacion.items():
        if valor is not None:
            setattr(solicitud, campo, valor)
    
    db.commit()
    db.refresh(solicitud)
    return solicitud
```

Esto demuestra que el servicio no necesita ser modificado si se introduce un nuevo tipo de esquema de actualización, siempre que este respete el mismo contrato de comportamiento.

---

### 4. I — Interface Segregation Principle (Principio de Segregación de Interfaces)

**¿Qué significa?**

Este principio indica que ningún cliente (en este caso, un endpoint o una función) debe verse obligado a depender de métodos o campos que no utiliza. Es preferible tener varias interfaces pequeñas y específicas, en lugar de una sola interfaz general que obligue a todos a lidiar con información que no necesitan.

**¿Por qué es importante en este proyecto?**

El enunciado de la práctica pide explícitamente un endpoint que actualice **exclusivamente el estado** de una solicitud, sin modificar el resto de sus atributos. Si se usara un único schema para todas las actualizaciones, ese endpoint estaría obligado a recibir y procesar campos que no le corresponden (como `titulo` o `costo_estimado`), lo cual viola este principio y aumenta el riesgo de actualizaciones no deseadas.

**¿Cómo se aplicó?**

En lugar de tener un único schema gigante que sirva para crear, actualizar completamente y actualizar el estado, separé los schemas según su propósito específico:

- `SolicitudCreate` → solo para creación (todos los campos obligatorios).
- `SolicitudUpdate` → solo para actualización completa (todos los campos opcionales, ya que puede que no todos cambien).
- `SolicitudEstadoUpdate` → solo para actualizar el estado (un único campo obligatorio).

```python
class SolicitudEstadoUpdate(BaseModel):
    """Schema para actualizar solo el estado"""
    estado: str = Field(..., description="Nuevo estado de la solicitud")
```

De esta forma, el endpoint `PATCH /solicitudes/{id}/estado` solo depende de la interfaz mínima necesaria (`estado`), sin verse forzado a recibir o exponer campos como `titulo` o `costo_estimado` que no le corresponden:

```python
@router.patch("/{solicitud_id}/estado", response_model=SolicitudResponse)
def actualizar_estado(solicitud_id: UUID, estado_update: SolicitudEstadoUpdate, db: Session = Depends(get_db)):
    """Actualizar solo el estado de una solicitud"""
    solicitud_actualizada = SolicitudService.actualizar_estado(db, solicitud_id, estado_update)
    if not solicitud_actualizada:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Solicitud con ID {solicitud_id} no encontrada"
        )
    return solicitud_actualizada
```

Esta segregación evita que un cliente de la API tenga que enviar información innecesaria y reduce el riesgo de que, por error, se modifiquen campos que no debían tocarse.

---

### 5. D — Dependency Inversion Principle (Principio de Inversión de Dependencias)

**¿Qué significa?**

Este principio establece que los módulos de alto nivel (la lógica de negocio) no deben depender directamente de módulos de bajo nivel (detalles de implementación, como la conexión a una base de datos específica). Ambos deben depender de abstracciones. En la práctica, esto se traduce en usar **inyección de dependencias** en lugar de crear instancias concretas directamente dentro del código.

**¿Por qué es importante en este proyecto?**

Si las rutas o los servicios crearan directamente sus propias conexiones a PostgreSQL, cambiar de base de datos, hacer pruebas unitarias con una base de datos de prueba, o cambiar la configuración de conexión sería muy complicado, ya que habría que modificar código en múltiples lugares del sistema.

**¿Cómo se aplicó?**

Las rutas no crean directamente la conexión a la base de datos ni gestionan manualmente las sesiones de SQLAlchemy. En su lugar, dependen de la función `get_db`, la cual es inyectada por FastAPI a través del mecanismo `Depends()`:

```python
def get_db():
    """Dependencia para obtener la sesión de base de datos"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

Las rutas simplemente declaran que necesitan una sesión de base de datos, sin saber cómo se crea ni cómo se cierra:

```python
@router.get("/", response_model=list[SolicitudResponse])
def obtener_todas_solicitudes(db: Session = Depends(get_db)):
    """Obtener todas las solicitudes operativas"""
    solicitudes = SolicitudService.obtener_todas_solicitudes(db)
    return solicitudes
```

Gracias a este mecanismo, la ruta depende de una **abstracción** (una sesión de base de datos inyectada) y no de una implementación concreta y fija. Esto permitiría, por ejemplo, reemplazar `get_db` por una versión que use una base de datos en memoria durante las pruebas automatizadas, sin modificar ni una sola línea de las rutas ni de los servicios.

---
