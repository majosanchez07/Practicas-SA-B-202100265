# Preguntas teóricas

Práctica 8 — María José Tebalán Sánchez — 202100265

Las respuestas analizan la implementación entregada en esta práctica y sus
implicaciones operativas. Los datos citados proceden de la propia
implementación, no de fuentes generales.

---

## 1. El repositorio como única fuente de verdad: ¿qué cambia realmente respecto del modelo anterior?

Lo que cambia no es dónde se guardan los archivos, sino **quién inicia la
acción de desplegar**.

En el modelo de la práctica anterior, la automatización tomaba la iniciativa:
se autenticaba contra el entorno y ejecutaba comandos de actualización. El
estado del entorno era el resultado acumulado del último comando que alguien
ejecutó con éxito, y ese resultado no estaba escrito en ninguna parte. Si
alguien modificaba algo a mano, el entorno quedaba en un estado que ningún
archivo describía.

En el modelo actual, la automatización no puede desplegar. Escribe una línea en
un repositorio y se detiene ahí. Un componente que vive dentro del entorno lee
ese repositorio y ajusta lo que existe hasta que coincida con lo declarado.

Tres consecuencias concretas de mi implementación:

**La reversión deja de ser un procedimiento.** Antes, revertir exigía recordar
qué versión estaba antes y ejecutar un comando contra el entorno. Ahora se
revierte un registro del historial. La operación es idéntica a corregir
cualquier otro error de archivo, y no requiere acceso al entorno.

**La desviación se corrige sola.** Configuré la comparación continua con
corrección automática activada. Si alguien modificara a mano un recurso del
entorno, la diferencia se detecta y se deshace. En el modelo anterior esa
modificación habría persistido hasta que alguien la notara por casualidad.

**Comprometer el repositorio ya no compromete la infraestructura.** Este es el
cambio de mayor alcance, y lo desarrollo en la pregunta 3.

Una consecuencia menos evidente que encontré al implementarlo: **la separación
obliga a decidir quién declara cada objeto.** En mi primera versión, tanto la
declaración de infraestructura como el empaquetado de la aplicación creaban las
cuotas del espacio de trabajo. Al aplicarlo, ambos habrían reclamado el mismo
objeto y el estado habría oscilado indefinidamente entre "sincronizado" y
"desviado". Tuve que desactivar esa parte del empaquetado. La lección es que la
fuente única de verdad no admite solapamientos: si dos declaraciones describen
el mismo objeto, no hay una fuente de verdad sino dos en conflicto.

---

## 2. ¿Por qué la entrega progresiva reduce el impacto de un fallo, y cuál es su límite?

La entrega progresiva reduce el impacto porque **acota cuántos usuarios pueden
ver una versión antes de que exista evidencia de que funciona**.

En mi implementación, la primera etapa expone el veinte por ciento del tráfico.
Si el análisis detecta un problema allí, ochenta de cada cien usuarios nunca
llegaron a ver la versión defectuosa. En el modelo anterior, la versión nueva
sustituía a la anterior en una sola operación: el cien por cien de los usuarios
recibía el cambio antes de que nadie pudiera comprobar nada.

La reducción no es solo de alcance sino de **duración**. El análisis se ejecuta
cada veinte segundos, de modo que el intervalo entre publicar una versión rota
y contenerla se mide en decenas de segundos, no en el tiempo que tarde una
persona en enterarse.

### El límite

La entrega progresiva solo detecta lo que sus pruebas saben medir. Es un
mecanismo de contención, no de verificación exhaustiva.

En mi implementación el análisis comprueba tres cosas: disponibilidad,
funcionamiento de los servicios esenciales y tiempo de respuesta bajo
concurrencia. Un defecto que no se manifieste en ninguna de esas tres pasaría
las cuatro etapas y sería promovido. Ejemplos concretos que mi análisis **no**
detectaría:

- Un cálculo que devuelve un resultado incorrecto pero con el formato correcto
  y en el tiempo esperado.
- Un fallo que solo se produce con datos que mis pruebas no generan.
- Una degradación que aparece después de horas de funcionamiento, como una fuga
  de memoria: cada etapa dura sesenta segundos.
- Un error que solo afecta a un subconjunto de usuarios que el reparto de
  tráfico no alcanza durante la ventana de medición.

Hay un segundo límite, de naturaleza distinta: **un cambio con efectos
irreversibles no se contiene revirtiendo la versión.** Si la versión defectuosa
modifica datos almacenados de forma incompatible con la anterior, devolver el
tráfico a la versión estable no deshace esa modificación. La reversión restaura
el código, no los datos. Por eso el mecanismo protege bien frente a defectos de
comportamiento y mal frente a defectos de migración de datos.

---

## 3. ¿Qué implica que la automatización no posea credenciales del entorno?

Implica que **el peor escenario cambia de categoría**.

En el modelo anterior, la automatización almacenaba credenciales de
administración del entorno. Quien obtuviera acceso al repositorio o a esas
credenciales podía ejecutar cualquier acción sobre la infraestructura: desplegar
código arbitrario, leer todas las credenciales almacenadas, eliminar los datos.
El repositorio era, en la práctica, una llave maestra.

En mi implementación, la automatización posee un único permiso: escribir en el
repositorio de declaración y proponer un cambio. No tiene credenciales del
entorno, y verifico esa ausencia de forma automática —la explico en la pregunta
7.

Quien comprometa esa automatización puede, como máximo, proponer que se
despliegue una versión distinta. Esa propuesta atraviesa después:

1. La revisión de la propuesta, que un humano aprueba o rechaza.
2. El motor de admisión, que rechaza lo que incumple las normas del entorno.
3. El análisis progresivo, que revierte si el comportamiento se degrada.

Es decir: de "control total inmediato" se pasa a "una propuesta que debe
superar tres controles adicionales".

### Lo que este modelo no resuelve

Conviene ser preciso sobre el alcance, porque es fácil sobrestimarlo.

El componente que aplica los cambios **sí** tiene permisos amplios dentro del
espacio de trabajo de la aplicación: puede crear y eliminar cargas de trabajo.
Eso es inevitable, porque es exactamente su función. Lo que se consigue no es
eliminar el privilegio, sino **moverlo a un lugar más defendible**: ese
componente no es alcanzable desde el exterior, no ejecuta código proveniente de
propuestas externas y sus permisos terminan en la frontera del espacio de
trabajo. No puede tocar la administración del entorno ni concederse permisos
adicionales.

Tampoco resuelve el caso de quien tenga acceso directo al entorno con
credenciales de administración. Frente a eso, el modelo aporta detección —la
modificación se deshace y queda registrada— pero no prevención.

---

## 4. Los umbrales del análisis: ¿cómo se eligen y qué pasa si se eligen mal?

Los umbrales que fijé son una proporción de errores inferior al uno por ciento
y un tiempo de respuesta en el percentil 95 inferior a 500 milisegundos.

### Cómo los elegí

Ninguno es un valor convencional copiado de una referencia. Ambos parten de
mediciones del sistema en condiciones normales.

**Proporción de errores.** El sistema no tiene ninguna fuente conocida de error
intermitente: en condiciones normales la proporción observada es nula. El uno
por ciento no significa "se tolera algo de error". Con unas seiscientas
peticiones por ventana de medición, ese margen cubre unas seis anomalías, que
es lo que puede producir un reinicio de instancia o una conexión interrumpida
durante la ventana. Una versión que falle de forma sistemática lo supera de
inmediato.

**Tiempo de respuesta.** El valor observado en condiciones normales está por
debajo de 200 milisegundos. Fijé el umbral en 500, más del doble.

### Qué pasa si se eligen mal

Los dos errores posibles tienen consecuencias asimétricas, y esa asimetría
determinó mi elección.

**Umbral demasiado estricto.** Si hubiera fijado 250 milisegundos, el umbral
saltaría por la variabilidad normal del entorno: otra carga de trabajo
consumiendo recursos del mismo nodo, ausencia de datos en memoria intermedia
tras un reinicio. El resultado serían reversiones de versiones correctas.

Esto parece el error "seguro", pero no lo es. **Un equipo que ve revertirse
despliegues sanos aprende a desconfiar del mecanismo**, empieza a repetir
despliegues hasta que "pasa", y termina relajando los umbrales o desactivando el
análisis. Un control desactivado protege menos que uno permisivo que permanece
activo.

**Umbral demasiado laxo.** Una versión degradada se promueve. El fallo es
directo pero, en mi opinión, menos grave a largo plazo: el problema se detecta
después por otros medios y el umbral se corrige. No destruye la confianza en el
mecanismo.

Por eso elegí holgura en la latencia —donde la variabilidad ambiental es alta—
y rigor en la proporción de errores, donde el valor normal es nulo y cualquier
desviación sostenida indica un defecto real.

### Una decisión relacionada

Uso el percentil 95 y no el promedio. El promedio oculta los casos extremos: si
de cada cien peticiones noventa y cinco tardan 50 milisegundos y cinco tardan
cinco segundos, el promedio resulta aceptable mientras uno de cada veinte
usuarios espera cinco segundos. El percentil 95 expone justamente esa cola.

Configuré además un límite de cero fallos tolerados antes de abortar: sin
reintentos. Si la versión candidata falla la comprobación, no dejará de fallarla
por intentarlo de nuevo, y cada reintento es tiempo con tráfico real llegando a
una versión defectuosa.

---

## 5. ¿Por qué el análisis genera tráfico en lugar de observar el real?

Porque en este sistema **no hay tráfico real que observar**, y un análisis sin
muestras produce un falso positivo silencioso.

Lo habitual en producción es que el análisis consulte las métricas del tráfico
que los usuarios generan. Ese enfoque es correcto cuando hay usuarios. En la
primera etapa de mi implementación, la versión candidata recibe el veinte por
ciento del tráfico; si nadie está usando el sistema, el veinte por ciento de
cero sigue siendo cero.

Un análisis por observación concluiría entonces "ningún error detectado" y
promovería la versión. **Aprobar por ausencia de datos produce exactamente la
misma señal que aprobar por evidencia favorable**, y esa indistinguibilidad es
lo que lo hace peligroso: no hay forma de notar que el control no comprobó
nada.

Por eso mi análisis ejecuta pruebas activas: genera las peticiones contra la
versión candidata y evalúa las respuestas. Si no hay respuesta, hay fallo, no
silencio.

Hay una segunda razón, independiente de la anterior. Dirijo las pruebas al
punto de acceso específico de la versión candidata y no al general. Si midiera
sobre el general, las respuestas de ambas versiones se mezclarían: en la primera
etapa, con un reparto de veinte a ochenta, una versión candidata que fallara la
totalidad de sus peticiones produciría una proporción de errores combinada del
veinte por ciento. Habría que fijar el umbral por debajo de ese valor para
detectarla, lo que a su vez lo haría inútil en las etapas posteriores, donde el
mismo fallo se diluye o se concentra de forma distinta. Medir solo la candidata
mantiene el umbral con el mismo significado en todas las etapas.

---

## 6. ¿Qué aporta rechazar un despliegue no conforme frente a corregirlo automáticamente?

El motor de admisión que configuré puede hacer dos cosas ante un despliegue que
incumple las normas: rechazarlo o corregirlo. Elegí rechazar, en las tres
normas.

La corrección automática hace que el despliegue funcione. Si falta la
declaración de límites de consumo, se asignan valores predeterminados; si la
referencia al artefacto es imprecisa, se sustituye por una exacta. El despliegue
prosigue y nadie se entera.

Ahí está el problema: **nadie se entera**. Quien propuso un despliegue
incorrecto no recibe ninguna señal, de modo que volverá a proponerlo igual. La
corrección resuelve el síntoma una vez y deja intacta la causa.

El rechazo detiene el despliegue y devuelve un mensaje explicando qué norma se
incumplió. Obliga a corregirlo en el origen, donde la corrección es permanente.

Hay un segundo argumento, específico de esta práctica: **los valores que la
corrección automática asignaría probablemente serían inadecuados.** Si el motor
asigna límites de consumo predeterminados, esos valores no están pensados para
esa carga de trabajo concreta: pueden quedarse cortos y provocar terminaciones
por falta de memoria, o sobrar y desperdiciar capacidad. Quien escribe el
despliegue es quien sabe cuánto consume su componente.

### Una complementariedad que conviene notar

En mi implementación conviven dos mecanismos que garantizan lo mismo por vías
distintas. La declaración de infraestructura define valores predeterminados que
se aplican a los contenedores que no declaren los suyos —una corrección
silenciosa— mientras que la norma de admisión rechaza el despliegue que los
omita.

No es una contradicción. Los valores predeterminados son una red de seguridad
que evita que una carga auxiliar sea rechazada por una cuota; la norma es lo
que educa a quien escribe despliegues. Si solo existiera la red de seguridad,
nadie declararía límites nunca.

---

## 7. ¿Cómo se comprueba que la automatización realmente no puede desplegar?

Esta pregunta me parece la más importante de todas, porque una prohibición que
no se verifica no es una garantía sino una intención.

Podría afirmar que mi automatización no despliega y que quien lo dude revise el
archivo. Pero un archivo se modifica, y nadie revisa cada cambio con esa
pregunta en mente. Implementé una comprobación automática: la propia
automatización se analiza a sí misma buscando comandos de despliegue,
referencias a credenciales del entorno y acciones de aplicación. Si encuentra
alguno, se detiene con error.

La comprobación se ejecuta antes de construir ningún artefacto, de modo que una
automatización que pudiera desplegar no llegaría siquiera a producir una
versión.

### Un error que cometí al implementarlo, y lo que enseña

La primera versión de esta comprobación estaba escrita dentro del propio archivo
de la automatización, y **fallaba siempre**. El motivo: los patrones que buscaba
aparecían literalmente en las líneas que los buscaban. La comprobación se
encontraba a sí misma.

Lo resolví moviendo la comprobación a un archivo separado, de modo que los
patrones no conviven con el archivo analizado.

El episodio enseña algo que va más allá del detalle técnico: **un control que
falla siempre es tan inútil como uno que nunca falla.** Si lo hubiera dejado
así, el resultado previsible sería desactivarlo por ruidoso, y la prohibición
habría quedado sin verificación.

Por eso comprobé el control en los dos sentidos:

- Contra la automatización actual: las catorce comprobaciones pasan.
- Contra la automatización de la práctica anterior, que sí desplegaba: detecta
  los tres mecanismos de despliegue que contenía y falla.

La segunda prueba es la que da valor a la primera. Sin ella, no habría forma de
distinguir un control que funciona de uno que aprueba todo lo que se le pone
delante.
