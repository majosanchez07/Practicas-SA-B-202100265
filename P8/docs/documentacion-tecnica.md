# Documentación técnica

Práctica 8 — María José Tebalán Sánchez — 202100265

---

## 1. El problema

El flujo de entrega de la práctica anterior presentaba tres debilidades. Las
tres tienen la misma raíz: **la automatización empujaba los cambios hacia el
entorno productivo y poseía las credenciales para hacerlo.**

| Debilidad | Consecuencia |
|---|---|
| El despliegue avanzaba sin validación intermedia | Un cambio defectuoso alcanzaba a la totalidad de los usuarios |
| La automatización tenía credenciales de administración | Comprometer el repositorio equivalía a comprometer la infraestructura |
| No se comparaba el estado real con el declarado | Una modificación manual podía persistir indefinidamente sin ser detectada |

## 2. La solución: invertir el sentido del flujo

El cambio central no es añadir herramientas, sino **invertir quién inicia el
despliegue**.

| | Modelo anterior | Modelo actual |
|---|---|---|
| Quién aplica | La automatización externa | Un componente interno del entorno |
| Sentido | La automatización empuja | El entorno consulta y toma |
| Credenciales | La automatización las posee | La automatización no tiene ninguna |
| Origen de la verdad | El último comando ejecutado | El repositorio de declaración |
| Reversión | Comando manual | Revertir un registro del historial |

De esa inversión se derivan tres propiedades sin necesidad de añadir nada más:

**Trazabilidad.** El estado del entorno es el historial del repositorio de
declaración. Cada cambio de versión es una propuesta revisable con autor, fecha
y motivo.

**Reversibilidad.** Revertir un registro del historial devuelve el entorno al
estado anterior. No hace falta recordar qué versión estaba antes ni ejecutar
ningún comando contra el entorno.

**Detección de desviaciones.** El componente interno compara continuamente lo
declarado con lo real. Una modificación manual se deshace sola y queda
registrada.

## 3. Las cinco puertas de calidad

Un cambio atraviesa cinco validaciones antes de alcanzar a la totalidad de los
usuarios. El orden no es arbitrario: va de lo más barato a lo más costoso, de
modo que un defecto evidente se detecta en segundos y no tras exponer tráfico
real.

| Orden | Validación | Momento | Coste |
|---|---|---|---|
| 1 | Lógica del código | Antes de construir | Segundos |
| 2 | Coherencia del empaquetado | Antes de construir | Segundos |
| 3 | Vulnerabilidades conocidas | Antes de publicar | Un minuto |
| 4 | Conformidad con las normas | Al admitir en el entorno | Instantáneo |
| 5 | Comportamiento con tráfico real | Durante la promoción | Minutos, con exposición parcial |

Las cuatro primeras examinan el artefacto **en reposo**. Ninguna puede
responder si funciona cuando lo usan personas, porque para saberlo hay que
ejecutarlo. La quinta es la única que lo observa **en funcionamiento**, y por
eso es la única capaz de detectar una regresión de rendimiento o un fallo que
solo aparece con datos reales.

## 4. Decisiones de diseño

### 4.1 Por qué dos repositorios separados

El código y la declaración del estado tienen ciclos de vida distintos: el
primero cambia al programar, la segunda al desplegar. Separarlos aporta tres
cosas concretas:

- La automatización recibe permiso de escritura **solo** sobre el repositorio
  de declaración. No ve el código fuente ni puede alterar sus propias reglas.
- No se producen ciclos: si la automatización escribiera en el mismo
  repositorio que la dispara, cada promoción provocaría una nueva ejecución.
- El historial de despliegues queda limpio, sin mezclarse con el de desarrollo.

### 4.2 Por qué solo un componente se promueve por etapas

La promoción progresiva tiene un coste: durante el avance conviven dos
versiones, con el consumo de recursos que implica, y cada etapa espera el
resultado de un análisis.

Se aplica únicamente al componente expuesto al exterior porque es la puerta de
entrada del sistema: una versión defectuosa allí afecta a la totalidad de los
usuarios. Aplicarla a los siete componentes multiplicaría el tiempo de
despliegue sin reducir el riesgo de forma proporcional, ya que los componentes
internos solo son alcanzables a través de esa puerta.

### 4.3 Por qué el análisis genera tráfico en lugar de observarlo

Lo habitual en un sistema en producción es que el análisis consulte las
métricas del tráfico real. Aquí el análisis **genera** las peticiones, y la
razón es determinante:

En la primera etapa la versión candidata recibe el veinte por ciento del
tráfico. En un sistema sin usuarios reales, ese veinte por ciento de nada sigue
siendo nada. Un análisis basado en observación no tendría muestras que evaluar
y concluiría "sin errores" por ausencia de datos.

**Aprobar por falta de información es la peor forma posible de aprobar un
despliegue**, porque produce exactamente la misma señal que un éxito legítimo.

### 4.4 Por qué se rechaza en lugar de corregir

El motor de admisión podría corregir automáticamente los despliegues no
conformes: asignar los límites que faltan, sustituir una referencia imprecisa
por una exacta. Se eligió rechazar.

Una corrección silenciosa hace que el despliegue funcione, pero oculta que
alguien propuso algo incorrecto. El rechazo deja constancia y obliga a
corregirlo en el origen. La corrección automática resuelve el síntoma una vez;
el rechazo corrige la causa de forma permanente.

### 4.5 Por qué cada objeto tiene un único responsable

La declaración de la infraestructura y la de las cargas de trabajo las
gestionan componentes distintos. Ningún objeto puede estar declarado en ambos.

Si dos componentes declararan el mismo objeto, cada uno lo reclamaría como
propio y el estado oscilaría permanentemente entre "sincronizado" y
"desviado", sin estabilizarse nunca. Como la evaluación exige que el sistema
esté sincronizado y sano, la separación de responsabilidades no es una
preferencia de estilo sino una condición de funcionamiento.

| Responsable | Objetos que declara |
|---|---|
| Declaración de infraestructura | Espacios de trabajo, cuotas, límites, permisos |
| Declaración de aplicación | Cargas de trabajo, configuración, exposición |

### 4.6 Fundamento de los umbrales

| Medida | Umbral | Fundamento |
|---|---|---|
| Proporción de errores | Menor al 1% | En condiciones normales es nula. Con unas seiscientas peticiones por ventana de medición, el margen cubre unas seis anomalías: un reinicio puntual, una conexión interrumpida. Un fallo sistemático lo supera de inmediato |
| Tiempo de respuesta (percentil 95) | Menor a 500 ms | El valor observado en condiciones normales es inferior a 200 ms. Se fija en más del doble deliberadamente |

La holgura del segundo umbral merece explicación. Un umbral ajustado al valor
observado saltaría por la variabilidad normal del entorno —carga de un vecino,
ausencia de datos en memoria intermedia— y revertiría versiones correctas.

**Un equipo que ve revertirse despliegues sanos aprende a desconfiar del
mecanismo y termina desactivándolo.** Un control que se desactiva protege
menos que uno más permisivo que permanece activo. A la vez, 500 ms es lo
bastante estricto para detectar una regresión real: una consulta mal optimizada
o una llamada añadida en el camino crítico multiplican el tiempo de respuesta,
no lo aumentan en un veinte por ciento.

## 5. Verificación de la cadena de suministro

Tres controles garantizan que solo llegue al entorno lo que se construyó desde
el repositorio autorizado:

**Análisis previo a la publicación.** El artefacto se examina antes de
publicarse, no después. Uno con vulnerabilidades críticas conocidas no llega
siquiera al almacén de artefactos.

**Inventario de componentes.** Se registra todo lo que el artefacto contiene.
Cuando se publique una vulnerabilidad de una biblioteca cualquiera, la
pregunta "¿nos afecta?" se responde consultando el inventario, no inspeccionando
cada artefacto.

**Firma verificable.** El artefacto se firma con una identidad efímera vinculada
al proceso de construcción, sin claves privadas almacenadas en ningún sitio. La
firma se aplica sobre el identificador del contenido y no sobre su etiqueta,
porque una etiqueta puede reasignarse a otro contenido mientras que el
identificador del contenido no. Verificar la firma comprueba que el artefacto
procede del repositorio autorizado y no ha sido sustituido.

## 6. Anexo: equivalencia de componentes

Este documento describe funciones en lugar de nombres de producto. La
correspondencia con la implementación entregada:

| Función descrita | Implementación |
|---|---|
| Declaración de infraestructura | Terraform |
| Empaquetado de la aplicación | Helm |
| Motor de declaración | ArgoCD |
| Controlador de promoción | Argo Rollouts |
| Motor de admisión | Kyverno |
| Análisis de vulnerabilidades e inventario | Trivy |
| Firma de artefactos | Cosign |
| Prueba de rendimiento | k6 |
| Automatización de construcción | GitHub Actions |
| Gestión de credenciales cifradas | Sealed Secrets |
