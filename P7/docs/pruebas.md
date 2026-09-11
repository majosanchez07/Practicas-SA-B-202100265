# Pruebas unitarias

**María José Tebalán Sánchez — 202100265**

La etapa 2 del pipeline ejecuta **105 pruebas unitarias** repartidas entre los
cinco microservicios. Este documento explica qué cubre cada suite y por qué se
eligieron esos casos.

| Servicio | Lenguaje | Herramienta | Pruebas | Archivo |
|---|---|---|---|---|
| `api-gateway` | Node | `node --test` | 19 | [`tests/proxy.test.js`](../services/api-gateway/tests/proxy.test.js) |
| `auth-service` | Python | pytest | 38 | [`tests/`](../services/auth-service/tests/) |
| `books-service` | Python | pytest | 17 | [`tests/test_graphql_schema.py`](../services/books-service/tests/test_graphql_schema.py) |
| `loans-service` | Node | `node --test` | 20 | [`tests/`](../services/loans-service/tests/) |
| `notifications-service` | Node | `node --test` | 15 | [`tests/consumer.test.js`](../services/notifications-service/tests/consumer.test.js) |
| **Total** | | | **105** | |

---

## Criterio general

Dos decisiones gobiernan todas las suites.

**Se prueba la lógica propia, no las bibliotecas.** No tiene valor verificar que
AES cifre o que Sequelize construya un `SELECT`: eso ya lo garantizan
pycryptodome y Sequelize, y una prueba así solo se rompe cuando se actualiza la
dependencia. Lo que sí se prueba son las decisiones del proyecto: el formato
`iv:ciphertext`, el período de gracia de los JWT, el sobre de los eventos, el
momento exacto del `ack`.

**Ninguna prueba necesita PostgreSQL ni RabbitMQ.** Las dependencias externas se
sustituyen por dobles, y `books-service` usa SQLite en memoria. La alternativa
—levantar contenedores de servicio en el runner— multiplicaría la duración de la
etapa y la volvería intermitente: un arranque lento de Postgres aparecería como
una prueba en rojo que en realidad no lo está, y ese ruido enseña a ignorar los
fallos del pipeline.

Los servicios de Node usan el runner integrado (`node --test`) en lugar de Jest
o Mocha. El proyecto no tenía dependencias de prueba y el runner nativo evita
arrastrar un árbol de paquetes completo solo para ejecutar estos casos.

---

## `api-gateway` — 19 pruebas

Se levanta un microservicio de mentira (un servidor HTTP real en un puerto
efímero) y se comprueba que el proxy le entrega exactamente lo que recibió. Se
ejercita el código real, incluido el encadenado de flujos.

| Grupo | Qué cubre |
|---|---|
| Reenvío | La petición llega al destino; el prefijo se quita; la raíz se traduce a `/`; se conserva la cadena de consulta; se propagan cuerpo y código de estado |
| Métodos y cuerpo | GET, POST, PUT, DELETE y PATCH; el cuerpo de un POST llega íntegro; un cuerpo de 50 KB no se trunca |
| Cabeceras | `Authorization` se propaga; `Host` se reescribe con el del destino; las cabeceras personalizadas sobreviven |
| Fallos | Un servicio caído produce 502, no una caída del gateway; el error identifica qué servicio falló |

**La prueba más importante es la del cuerpo del POST.** Es exactamente el fallo
que motivó escribir el proxy a mano: con `http-proxy-middleware` las peticiones
GET funcionaban pero cualquier POST quedaba colgado hasta el timeout, sin que el
microservicio destino recibiera nada. Una prueba que fije ese comportamiento
impide que alguien "simplifique" el módulo reintroduciendo el problema.

La prueba del 502 cubre otro riesgo real: sin ese manejador, un error de socket
derribaría el proceso del gateway, y la caída de un microservicio se llevaría
consigo a toda la plataforma.

---

## `auth-service` — 38 pruebas

### Cifrado (16 pruebas)

- **Reversibilidad** para siete entradas distintas, incluidos los casos borde del
  relleno PKCS#7: un solo carácter y exactamente 16 bytes.
- **Formato de salida**: dos partes separadas por `:`, ambas base64 válido, IV de
  16 bytes y texto cifrado múltiplo del bloque.
- **IV aleatorio**: cifrar dos veces el mismo dato produce resultados distintos,
  pero ambos descifran al mismo valor. Veinte cifrados generan veinte IV
  distintos.
- **Entradas inválidas**: texto sin separador y texto cifrado con otra llave
  lanzan excepción.

El grupo del IV aleatorio merece explicación. Es una propiedad de seguridad, no
una curiosidad: si alguien "optimizara" el servicio reutilizando un IV fijo, dos
usuarios con la misma contraseña tendrían idéntico texto cifrado y la tabla de
usuarios filtraría esa coincidencia a cualquiera que la leyera.

### Tokens y contraseñas (22 pruebas)

- **Creación**: estructura de tres partes, conservación de los datos, presencia
  de `exp` e `iat`, expiración acorde a la configuración, y que no se mute el
  diccionario recibido.
- **Verificación**: acepta un token válido; rechaza uno expirado, uno firmado con
  otra llave y cuatro formas de cadena que no son un JWT.
- **Período de gracia**: renueva un token vencido hace 2 minutos conservando la
  identidad; **no** renueva pasado el margen configurado; **no** renueva uno
  firmado con otra llave; **no** renueva uno sin `exp`.
- **Contraseñas**: acepta la correcta, rechaza la incorrecta, distingue
  mayúsculas, y devuelve `False` —sin propagar la excepción— ante un dato
  ilegible.

El período de gracia es la lógica más delicada del servicio. Decodifica con
`verify_exp=False`, lo que a primera vista parece una puerta trasera. Las
pruebas fijan las dos condiciones que impiden que lo sea: la firma se sigue
validando, y pasado el margen la renovación se niega. Sin la segunda, el período
de gracia equivaldría a un token eterno.

Los tokens vencidos se construyen firmando con la llave real pero con un `exp` en
el pasado, de modo que no hace falta esperar treinta minutos ni manipular el
reloj del sistema.

---

## `books-service` — 17 pruebas

Se ejecutan consultas y mutaciones reales contra el esquema de Strawberry,
respaldado por SQLite en memoria. Los resolvers abren su propia sesión con
`SessionLocal()` en lugar de recibirla por inyección, así que el fixture
sustituye ese objeto: el resultado es que se ejercita el mismo código que corre
en el pod, incluidas las consultas de SQLAlchemy.

| Grupo | Qué cubre |
|---|---|
| Definición del esquema | Existen las consultas y mutaciones esperadas; `BookType` tiene sus seis campos; `genre` es opcional y el resto obligatorio |
| Consulta `books` | Lista vacía sin datos; devuelve los tres libros; los campos traen los valores correctos |
| Consulta `book` | Encuentra por id; devuelve `null` —no un error— si no existe |
| Mutación `createBook` | Crea y devuelve el id; persiste de verdad; un libro nuevo nace disponible; `genre` puede omitirse |
| Mutación `updateBookAvailability` | Marca no disponible (préstamo); persiste; devuelve a disponible (devolución); `null` si no existe |

Las pruebas del esquema no tocan la base a propósito: el contrato GraphQL es lo
que consumen el gateway y el frontend, y un cambio accidental de nombre o de
tipo rompe a los consumidores sin que ninguna otra prueba lo note.

`StaticPool` con una única conexión compartida es necesario en el fixture: sin
él, cada sesión de `:memory:` abriría su propia base vacía y las filas escritas
por una mutación no serían visibles para la consulta siguiente.

---

## `loans-service` — 20 pruebas

### Broker (13 pruebas)

`amqplib` se sustituye en la caché de `require` por un doble que registra todo lo
que el broker le pide.

- **Conexión**: se declara el exchange, es de tipo `topic` y es `durable`.
- **Publicación**: va al exchange configurado, con la clave indicada, marcada
  como `persistent` y con `content-type` JSON; el sobre lleva `evento`, `origen`
  y una fecha ISO 8601 válida.
- **Evento de préstamo**: se publica como `loan.created` e incluye `loanId`,
  `userId`, `bookId` y `status`, **sin** exponer campos internos del modelo.
- **Sin canal**: publicar no lanza y devuelve `false`.

Tres de estas pruebas fijan requisitos de durabilidad del enunciado. El exchange
durable y el mensaje `persistent` son ambos necesarios: una cola durable con
mensajes no persistentes sigue perdiendo su contenido al reiniciarse RabbitMQ.

La prueba de "sin canal" cubre el comportamiento que evita el
`CrashLoopBackOff`: si RabbitMQ todavía no está listo, publicar no debe derribar
el proceso. Y la de campos internos protege una decisión deliberada —el evento
se arma campo por campo en lugar de serializar la instancia completa— para que
una columna nueva en la tabla no se filtre sola al broker.

### Salud (7 pruebas)

- **Liveness**: responde 200 con la base disponible **y también cuando está
  caída**.
- **Readiness**: 200 con la base arriba; **503** cuando falla, informando el
  detalle.
- El alias `/health` de la Práctica 4 sigue respondiendo.

La segunda prueba de liveness es el centro del asunto. Si la liveness dependiera
de Postgres, una caída temporal de la base haría que Kubernetes reiniciara todos
los pods, y reiniciar no arregla una base caída: solo agrega un
`CrashLoopBackOff` al problema. El 503 de readiness, en cambio, retira el pod del
balanceo sin reiniciarlo, y se recupera solo cuando la base vuelve.

---

## `notifications-service` — 15 pruebas

### Procesamiento de eventos (11 pruebas)

- **`loan.created`**: crea una notificación, la asocia al usuario correcto, la
  clasifica con el tipo del ENUM, el mensaje menciona préstamo y libro, y no
  escribe ningún resumen.
- **`resumen.generado`**: almacena el resumen con su carné y total, guarda el
  desglose por hora en `detalle`, toma la fecha **del sobre del mensaje** y no
  crea notificaciones.
- **Evento desconocido**: se ignora sin lanzar.

El mapeo `datos.porHora` → columna `detalle` es un renombrado fácil de romper que
ninguna otra prueba detectaría. Y tomar la fecha del sobre importa porque el
consumidor puede procesar un mensaje mucho después de que el cronjob lo emitiera,
por ejemplo tras un reinicio del pod.

Que un evento desconocido se ignore en lugar de lanzar también es intencional: si
lanzara, iría a la DLQ, y en un exchange de tipo `topic` un evento nuevo es algo
normal cuando se agrega otro productor.

### Confirmación de mensajes (4 pruebas)

Estas son las que más valor tienen de toda la suite, porque verifican una
garantía que **no se puede comprobar leyendo el código**:

- El mensaje se confirma con `ack` **después** de persistir.
- Si la escritura en la base falla, **no hay `ack`**: RabbitMQ conserva el
  mensaje y lo volverá a entregar.
- Un fallo manda el mensaje a la DLQ **sin reencolarlo** (`requeue: false`), lo
  que evita el bucle infinito del "mensaje veneno": uno que siempre falla
  volvería a entregarse para siempre, bloqueando la cola.
- Un mensaje con JSON inválido va a la DLQ.

---

## Ejecutarlas localmente

```bash
# Todas, igual que el pipeline
./P7/scripts/pruebas-locales.sh

# Un servicio de Node
cd P7/services/api-gateway && npm ci && npm test

# Un servicio de Python
cd P7/services/auth-service
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt -r requirements-dev.txt
./.venv/bin/python -m pytest
```
