# Guion del video demostrativo

Práctica 8 — María José Tebalán Sánchez — 202100265

Duración objetivo: **7 minutos** (el enunciado pide de 5 a 8).

---

## Antes de grabar

### Qué debe estar listo

| Requisito | Comprobación |
|---|---|
| Entorno encendido y accesible | `kubectl get nodes` devuelve dos nodos `Ready` |
| Aplicación sincronizada | `argocd app get sa-platform` muestra `Synced` y `Healthy` |
| Evidencias capturadas | Las cuatro demostraciones ya ejecutadas |
| Propuesta bloqueada | Abierta y visible, sin fusionar |

**Importante:** el video **no** es el momento de ejecutar las demostraciones por
primera vez. La reversión automática tarda entre uno y dos minutos y consume
casi un tercio del tiempo disponible; si algo falla en vivo, se pierde la toma.
Se graba mostrando evidencia ya capturada, y solo se ejecuta en vivo lo que es
instantáneo.

### Preparar las ventanas

Conviene tener abierto de antemano, en pestañas separadas:

1. La interfaz del operador de despliegue con la aplicación cargada.
2. Una terminal con el directorio del repositorio.
3. El navegador en la propuesta de cambio bloqueada.
4. El navegador en el historial de ejecuciones de la automatización.
5. El archivo del informe de incidente.

Cambiar de pestaña es más rápido y se ve mejor que abrir cosas en vivo.

### Consejos de grabación

- Ampliar el tamaño de letra de la terminal antes de empezar. Lo que se lee
  cómodo en tu pantalla no se lee en un video comprimido.
- Hablar sobre lo que se ve, no leer el guion palabra por palabra.
- Si algo sale mal, seguir: es preferible una toma continua con un tropiezo
  que cinco cortes evidentes.

---

## Minutaje

| Bloque | Desde | Hasta | Contenido |
|---|---|---|---|
| 1 | 0:00 | 0:40 | Presentación y el problema que se resuelve |
| 2 | 0:40 | 1:40 | Infraestructura declarada y sus dos capas |
| 3 | 1:40 | 2:40 | El pipeline que no puede desplegar |
| 4 | 2:40 | 3:40 | El operador: única fuente de verdad |
| 5 | 3:40 | 5:10 | Promoción por etapas y reversión automática |
| 6 | 5:10 | 6:10 | Políticas de admisión y cadena de suministro |
| 7 | 6:10 | 7:00 | Incidente, cierre y costos |

Esta tabla es la que se copia al README, ajustando los tiempos reales tras
grabar.

---

# BLOQUE 1 — Presentación (0:00 – 0:40)

**En pantalla:** el diagrama del flujo.

> Buenas. Soy María José Tebalán, carné 202100265, y esta es la Práctica 8 de
> Software Avanzado.
>
> El punto de partida es el flujo de la práctica anterior, que tenía tres
> debilidades. La primera: un cambio defectuoso alcanzaba al cien por cien de
> los usuarios sin ninguna validación intermedia. La segunda: la automatización
> guardaba credenciales de administración del clúster, así que comprometer el
> repositorio equivalía a comprometer la infraestructura. Y la tercera: si
> alguien modificaba algo a mano, nadie se enteraba.
>
> Lo que voy a mostrar es cómo se resuelven las tres invirtiendo quién inicia
> el despliegue.

---

# BLOQUE 2 — Infraestructura declarada (0:40 – 1:40)

**En pantalla:** terminal, directorio de Terraform.

> La infraestructura no se creó a mano. Está en dos capas.

Mostrar la estructura de directorios y comentar:

> La primera capa crea el clúster: la red, el plano de control, los nodos. La
> segunda crea los espacios de trabajo, las cuotas, los límites y los permisos.
>
> Están separadas por una razón técnica: Terraform resuelve sus proveedores
> antes de crear nada, y el proveedor de la segunda capa necesita un clúster
> que en el primer intento todavía no existe.

Ejecutar en vivo (es instantáneo):

```
kubectl get namespaces -l gestionado-por=terraform
```

> Esta etiqueta la pone Terraform. Si algún espacio de trabajo se hubiera
> creado a mano, no aparecería aquí.

```
kubectl describe resourcequota -n sa-p8
```

> Las cuotas también salen de Terraform. Y aquí hay una decisión que conviene
> explicar: el empaquetado de las prácticas anteriores también las declaraba, y
> tuve que desactivarlas ahí. Si dos componentes declararan el mismo objeto,
> cada uno lo reclamaría como propio y la aplicación oscilaría entre
> sincronizada y desviada sin estabilizarse nunca.

---

# BLOQUE 3 — El pipeline que no puede desplegar (1:40 – 2:40)

**En pantalla:** el archivo del flujo de trabajo.

> Esta es la diferencia central con la práctica anterior. Aquel pipeline
> terminaba aplicando los cambios al clúster. Este no puede.

Recorrer las etapas y comentar:

> Construye, prueba, valida el empaquetado, analiza vulnerabilidades, genera el
> inventario de componentes y firma el artefacto. Y al final, lo único que hace
> es abrir una propuesta de cambio en el otro repositorio.
>
> No tiene credenciales del clúster. Lo máximo que puede hacer contra
> producción es cambiar una línea en una propuesta que después alguien revisa.

Ejecutar en vivo:

```
./P8/scripts/verificar-sin-despliegue-directo.sh
```

> Y esto no es solo una afirmación mía: es una comprobación automática que se
> ejecuta como primera etapa del pipeline, antes de construir nada. Revisa
> catorce patrones distintos de despliegue directo.
>
> Un detalle que vale la pena contar: la primera versión de esta comprobación
> estaba escrita dentro del propio archivo del pipeline, y fallaba siempre,
> porque los patrones que buscaba aparecían en las líneas que los buscaban. Se
> encontraba a sí misma. La moví a un archivo aparte, y la comprobé en los dos
> sentidos: pasa contra este pipeline, y falla contra el de la práctica
> anterior, que sí desplegaba.

---

# BLOQUE 4 — Única fuente de verdad (2:40 – 3:40)

**En pantalla:** la interfaz del operador de despliegue.

> Quien aplica los cambios es este componente, que vive dentro del clúster y
> lee el repositorio de declaración.

Señalar el estado:

> Sincronizada y sana. Eso significa que lo que existe en el clúster coincide
> exactamente con lo que está declarado en el repositorio.

Mostrar el árbol de recursos:

> Aquí está todo lo que gestiona: las cargas de trabajo, los servicios, la
> configuración.

Mostrar el repositorio de declaración en el navegador, el archivo de valores:

> Y esta es la línea que el pipeline modifica. Una sola: la versión de la
> imagen. Ese es todo el poder que la automatización tiene sobre producción.
>
> Además está configurada la corrección automática de desviaciones. Si alguien
> modificara un recurso a mano, el cambio se deshace solo y queda registrado.
> Ésa era la tercera debilidad del enunciado: aquí no solo se detecta, se
> corrige.

---

# BLOQUE 5 — Promoción y reversión (3:40 – 5:10)

Este es el bloque más importante: vale veintiocho de los sesenta puntos de
conocimiento. Conviene no apurarlo.

**En pantalla:** el registro de la promoción exitosa.

> La entrega progresiva se aplica al componente expuesto al exterior, que es la
> única puerta de entrada del sistema. Una versión defectuosa ahí afecta a todo
> el mundo.

Mostrar los pasos:

> La promoción avanza por etapas: veinte por ciento, cincuenta, ochenta, cien.
> Entre cada una hay una pausa, y durante esa pausa se ejecuta un análisis
> contra la versión candidata.

Explicar el análisis:

> El análisis hace tres cosas: comprueba que el componente responda, que sus
> servicios esenciales devuelvan resultados válidos, y que aguante bajo
> concurrencia. Los umbrales son menos del uno por ciento de errores y un
> percentil noventa y cinco por debajo de quinientos milisegundos.
>
> Ese medio segundo no es un número redondo elegido al azar: lo medí sobre el
> despliegue de la práctica cinco, donde estaba por debajo de doscientos
> milisegundos. Le dejé más del doble de holgura a propósito, porque un umbral
> ajustado saltaría por la variabilidad normal del entorno y revertiría
> versiones correctas. Y un equipo que ve revertirse despliegues sanos termina
> desactivando el mecanismo.

**Cambiar a:** el registro de la reversión automática.

> Ahora la parte interesante. Publiqué una versión con un defecto deliberado:
> la ruta del catálogo devuelve un error del servidor.
>
> El defecto está elegido con un criterio preciso. Es invisible para las
> comprobaciones de disponibilidad: el componente arranca, responde a sus
> comprobaciones de estado, y su instancia figura como disponible. Solo falla
> al ejecutar la función real.

Mostrar el análisis fallido:

> Aquí se ve. La prueba de disponibilidad pasa. La de funcionalidad falla. Y en
> cuanto falla, la promoción se detiene y el tráfico vuelve íntegro a la
> versión estable, sin que nadie intervenga.
>
> El tráfico afectado fue como máximo el veinte por ciento, el de la primera
> etapa. Ochenta de cada cien usuarios nunca vieron la versión defectuosa.
>
> Y esto es lo que justifica que el análisis no se conforme con la comprobación
> más barata: un análisis que solo mirara disponibilidad habría promovido esta
> versión al cien por cien de los usuarios.

---

# BLOQUE 6 — Políticas y cadena de suministro (5:10 – 6:10)

**En pantalla:** terminal.

> Hay tres políticas de admisión, todas en modo de rechazo, no de aviso.

Ejecutar en vivo (es instantáneo y se ve bien):

```
kubectl apply -f P8/policies/pruebas/pod-que-viola-las-politicas.yaml
```

> Este manifiesto incumple las tres a propósito: usa una referencia móvil a la
> imagen, no declara cuánto consume, y se ejecuta con privilegios de
> administrador. El resultado es un rechazo, con el detalle de qué regla
> incumple cada cosa.
>
> Elegí rechazar en lugar de corregir automáticamente. El motor podría asignar
> los límites que faltan y dejar pasar el despliegue, pero eso oculta que
> alguien propuso algo incorrecto. El rechazo obliga a corregirlo en el origen.

**Cambiar a:** la propuesta de cambio bloqueada, en el navegador.

> En la cadena de suministro, el análisis de vulnerabilidades se ejecuta antes
> de publicar el artefacto. Aquí abrí una propuesta con una imagen base antigua
> que tiene una vulnerabilidad crítica conocida, y quedó bloqueada.
>
> La elección de esa imagen tampoco fue al azar: comprobé que la vulnerabilidad
> tuviera corrección disponible. Una sin parche no se puede arreglar
> actualizando, así que bloquear por ella detendría la entrega sin ofrecer
> ninguna acción posible.

Mostrar la verificación de firma:

> Los artefactos se firman sin ninguna clave privada almacenada: la identidad
> es efímera y queda vinculada al proceso de construcción. Y se firma el
> identificador del contenido, no la etiqueta, porque una etiqueta se puede
> reasignar a otra imagen y el identificador no.

Mostrar el archivo de credenciales cifradas:

> Y las credenciales viajan cifradas. Este archivo está en un repositorio
> público y no hay riesgo: solo el controlador que lo cifró puede descifrarlo,
> con una clave que nunca sale del clúster.

---

# BLOQUE 7 — Cierre (6:10 – 7:00)

**En pantalla:** el informe de incidente.

> El informe del fallo inducido responde los cinco campos: qué falló, cómo se
> detectó, cómo se contuvo, cuánto tardó la recuperación y cómo prevenirlo.
>
> Sobre lo último: el defecto llegó a la etapa de promoción porque ninguna
> validación previa ejecutaba la función real del componente. Las pruebas
> unitarias comprueban piezas aisladas, el análisis de vulnerabilidades examina
> el artefacto en reposo, y las políticas verifican la forma del despliegue, no
> su comportamiento.
>
> El control que propongo es levantar el componente en un entorno desechable
> dentro de la propia automatización y ejecutar contra él las mismas pruebas de
> funcionalidad, antes de proponer la promoción. Mismo conjunto de pruebas, más
> temprano en la cadena, sin exponer tráfico a nadie.

**Cerrar con:** el resumen.

> Resumiendo: la infraestructura se declara y no se toca a mano; la
> automatización no puede desplegar; el operador que sí puede vive dentro del
> clúster y corrige cualquier desviación; ningún artefacto llega sin analizarse
> y firmarse; y una versión defectuosa se contiene sola en la primera etapa.
>
> El entorno completo costó alrededor de medio dólar, porque se crea, se
> captura la evidencia y se destruye.
>
> Gracias.

---

## Tras grabar

1. Anotar los tiempos reales de cada bloque.
2. Completar la fila del video en la tabla de enlaces con la URL y el minutaje.
3. Comprobar el enlace **sin sesión iniciada**, en una ventana privada: un
   enlace que pida autenticación se califica igual que uno ausente.

Formato sugerido para el README:

```
| Video demostrativo | https://... — 0:00 presentación · 0:40 infraestructura ·
1:40 pipeline sin despliegue · 2:40 fuente de verdad · 3:40 promoción y
reversión · 5:10 políticas y suministro · 6:10 incidente y cierre |
```
