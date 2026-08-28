# Preguntas teóricas

**Práctica 5 — Software Avanzado, Sección B**
**Maria Jose Tebalan Sanchez — Carné 202100265**

---

## 1. ¿Qué es Helm y qué problema resuelve frente a los manifiestos sueltos?

Helm es el gestor de paquetes de Kubernetes. Empaqueta un conjunto de
manifiestos en una unidad versionada llamada chart, les añade un motor de
plantillas y lleva registro del estado de cada instalación.

El problema que resuelve se ve comparando esta práctica con la anterior. En la
Práctica 4 cada objeto era un archivo YAML aplicado con `kubectl apply -f`, y
eso trae tres dificultades concretas:

**Repetición sin parametrización.** Los cinco microservicios de esta plataforma
tienen Deployments casi idénticos: cambian el nombre, el puerto, la imagen y los
recursos. Con manifiestos sueltos habría cinco archivos de unas 130 líneas
prácticamente iguales, y modificar la estrategia de actualización obligaría a
editar los cinco. En este chart hay **una sola plantilla** recorrida con `range`
sobre el mapa de servicios: agregar un microservicio a `values.yaml` genera su
Deployment, Service, HPA, PDB, ServiceAccount, Role, RoleBinding y sus
autorizaciones de red sin escribir una línea nueva de plantilla.

**Configuración por ambiente.** Desarrollo y producción difieren en réplicas,
límites, tag de imagen y nivel de log. Con manifiestos sueltos eso significa dos
copias completas del árbol de archivos, que divergen en cuanto alguien olvida
replicar un cambio. Aquí son dos archivos de values sobre un mismo chart.

**Estado y reversibilidad.** `kubectl apply` no sabe qué se aplicó antes: aplicar
un manifiesto que ya no contiene un objeto no lo elimina, queda huérfano. Helm
guarda cada revisión y puede volver atrás. En esta práctica pasé del chart 0.1.0
al 0.2.0 y regresé al 0.1.0 con un comando, y la aplicación efectivamente volvió
a responder `version: 1.0.0`.

Hay un cuarto punto que noté durante el desarrollo: Helm valida **antes** de
aplicar. La función `required` de las plantillas detiene la instalación con un
mensaje explícito cuando falta una credencial, en lugar de crear un Secret vacío
y dejar que los pods entren en CrashLoopBackOff sin explicación aparente.

---

## 2. ¿Cuál es la diferencia entre chart, release y repository?

Son tres niveles distintos y suelen confundirse porque en los comandos aparecen
juntos.

**Chart** — el paquete. Un directorio con `Chart.yaml`, `values.yaml` y las
plantillas. Es *la definición*: describe qué objetos hay que crear y qué se
puede parametrizar. Un chart no está desplegado en ninguna parte, igual que un
`.deb` no es un programa en ejecución. En esta práctica el chart es
`sa-platform`, con versiones 0.1.0 y 0.2.0.

**Release** — una instalación concreta de un chart en un clúster, con un nombre
y unos valores determinados. Es *la instancia*. El mismo chart puede instalarse
varias veces con nombres distintos y valores distintos, y cada release lleva su
propio historial de revisiones. Aquí el release se llama `sa-platform` y ha
pasado por tres revisiones (instalación, upgrade y rollback).

La distinción se hace tangible al ver dónde vive cada cosa: el chart está en el
disco, mientras que el release está registrado en un Secret dentro del clúster.
Durante esta práctica tuve un problema que lo ilustra: una plantilla mal
configurada recreaba el namespace y borraba ese Secret. Los objetos seguían
corriendo perfectamente en el clúster, pero el *release* había desaparecido:
`helm list` no lo mostraba y `helm upgrade` fallaba con "has no deployed
releases". Los objetos y el release son cosas separadas.

**Repository** — un servidor donde se publican charts empaquetados, con un
`index.yaml` que lista lo disponible. Es *el catálogo*. En esta práctica se usó
el repositorio de Bitnami para descargar PostgreSQL y RabbitMQ como
dependencias:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm dependency update .
```

Resumiendo la relación: un **repository** distribuye **charts**; instalar un
chart produce un **release**.

---

## 3. ¿Qué es un StatefulSet y cuándo NO usarlo?

Un StatefulSet es un controlador para cargas de trabajo cuyos pods **no son
intercambiables**. A diferencia de un Deployment, garantiza:

- **Identidad estable.** Los pods se llaman `<nombre>-0`, `<nombre>-1`, … y
  conservan ese nombre entre reinicios.
- **Almacenamiento ligado a esa identidad.** Cada pod recibe su propio PVC
  mediante `volumeClaimTemplates`, y al recrearse vuelve a montar exactamente el
  mismo volumen.
- **Orden en las operaciones.** Los pods se crean y eliminan secuencialmente, no
  todos a la vez.
- **Un headless service** que da DNS individual a cada pod.

La evidencia de esta práctica muestra el punto esencial. Al borrar el pod de
PostgreSQL:

```
antes:   pod uid 22ef9833-...  volumen pvc-fcc3c1d7-...
después: pod uid 98ded22e-...  volumen pvc-fcc3c1d7-...
```

El pod es una instancia nueva, pero el volumen es el mismo y los datos
sobrevivieron. Con un Deployment, cada pod nuevo habría tomado un volumen
distinto o ninguno.

**Cuándo NO usarlo.** Para servicios sin estado, que es la mayoría. Los cinco
microservicios de esta plataforma son Deployments, y debe ser así porque:

- El StatefulSet **estorba al escalado**. Crea y elimina pods en orden, uno tras
  otro. Cuando el HPA subió el gateway de 2 a 5 réplicas bajo carga, los pods se
  crearon en paralelo; con un StatefulSet habrían aparecido secuencialmente y la
  respuesta a la carga habría sido más lenta.
- **Complica la actualización sin caída.** El rolling update de un StatefulSet
  también es ordenado, y la garantía `maxUnavailable: 0` que sostuvo las 400
  peticiones sin error es propia del Deployment.
- **Reserva almacenamiento innecesario.** Un microservicio sin estado no necesita
  un PVC por réplica; con cinco réplicas serían cinco volúmenes ociosos.

Tampoco conviene para trabajos que terminan (ahí van Job y CronJob) ni para
procesos que deben correr uno por nodo (DaemonSet). Y hay un caso que parece
requerirlo y no lo requiere: una aplicación que guarda archivos temporales no
necesita identidad estable, le basta un volumen efímero, como el `emptyDir`
montado en `/tmp` de estos microservicios.

---

## 4. ¿Cuál es la diferencia entre liveness, readiness y startup probe?

Las tres verifican salud, pero responden preguntas distintas y Kubernetes actúa
distinto ante cada fallo. Por eso en este chart apuntan a endpoints diferentes:

| Probe | Pregunta | Consulta la BD | Al fallar |
|---|---|---|---|
| **startup** | ¿Terminó de arrancar? | No | Reinicia solo si nunca llega a arrancar |
| **liveness** | ¿Hay que reiniciar este pod? | **No** | **Reinicia el contenedor** |
| **readiness** | ¿Puede recibir tráfico? | **Sí** | **Lo saca del balanceo**, sin reiniciarlo |

**Liveness** detecta un proceso que está vivo pero irrecuperable: un interbloqueo,
un bucle infinito. La respuesta es reiniciarlo. Su costo es alto, así que debe
verificar solo el propio proceso.

**Readiness** decide si el Service envía tráfico al pod. Su fallo no es
destructivo: el pod sale del balanceo, sigue vivo y vuelve solo cuando la
dependencia se restablece.

**Startup** protege el arranque. Mientras no tenga éxito, las otras dos quedan
suspendidas. Sin ella habría que aflojar los umbrales de liveness para tolerar
el arranque, lo que retrasaría la detección de un cuelgue en régimen normal.

**La decisión de diseño más importante aquí**: la liveness **no consulta la base
de datos** y la readiness **sí**. Si liveness la consultara, una caída temporal
de PostgreSQL reiniciaría todos los pods de todos los microservicios. Reiniciar
no arregla una base de datos caída; solo añadiría un CrashLoopBackOff al
incidente y convertiría un fallo recuperable en una caída total. Con esta
separación, si PostgreSQL cae los pods salen del balanceo pero siguen vivos, y en
cuanto la base vuelve se reincorporan solos.

Esto se observó realmente durante el despliegue: al arrancar la plataforma,
PostgreSQL tarda más que los microservicios y el gateway respondía `503` en
readiness mientras sus dependencias no estaban listas. Era el comportamiento
correcto — se declaraba no disponible sin morir.

Los servicios en Python reciben más margen en la startup probe
(`failureThreshold: 24` frente a 18 de los Node) porque cargan más dependencias
al iniciar y crean su schema en el arranque.

---

## 5. ¿Qué es una NetworkPolicy y por qué el tráfico es permitido por defecto?

Una NetworkPolicy es un objeto que define qué tráfico de red se permite hacia y
desde un conjunto de pods, seleccionados por etiquetas.

**Por qué el tráfico es permitido por defecto.** Kubernetes se diseñó sobre un
modelo de red plano: todo pod puede alcanzar a todo pod sin NAT. Esa decisión
mantiene el modelo simple y hace que las aplicaciones funcionen sin configurar
nada, pero significa que un clúster recién creado **no tiene segmentación
alguna**: cualquier pod comprometido puede intentar conectarse a la base de datos.

El detalle que más confunde es que las NetworkPolicies son **reglas de permiso,
no de bloqueo**. Mientras ninguna política seleccione a un pod, ese pod acepta
todo. En cuanto una lo selecciona, pasa a rechazar todo lo que ninguna política
autorice expresamente. De ahí que el primer objeto de este chart sea una política
que selecciona a todos los pods y no autoriza nada:

```yaml
spec:
  podSelector: {}          # todos los pods del namespace
  policyTypes: [Ingress, Egress]
  # sin reglas: nada entra ni sale
```

A partir de ella se abren los trece caminos necesarios, incluido **el DNS**. Ese
detalle es fácil de pasar por alto: sin una política que permita el puerto 53
hacia kube-dns, el default-deny impide resolver nombres y los servicios fallan
con errores que parecen de conectividad y no de política.

**Una advertencia práctica que costó descubrir.** Las NetworkPolicies las
implementa el CNI, no Kubernetes. El API server acepta y almacena los objetos
aunque el CNI no sepa aplicarlos. En la primera prueba, las 13 políticas estaban
creadas y `kubectl get networkpolicy` las mostraba, pero un pod sin autorización
alcanzaba la base de datos sin problema: el CNI por defecto de minikube (bridge)
**no implementa NetworkPolicy y las ignora en silencio**. No hay advertencia ni
error. Hubo que recrear el clúster con Calico para que el aislamiento fuera real:

```
Pod sin etiquetas  -> PostgreSQL 5432 : BLOQUEADO
Pod con db-client  -> PostgreSQL 5432 : PERMITIDO
```

Mismo entorno, misma imagen, mismo destino; solo cambian las etiquetas. Es la
comparación que demuestra que quien bloquea es la política.

También conviene notar cómo se descarta el tráfico: las conexiones bloqueadas
**agotan el tiempo de espera** en lugar de devolver "connection refused". El
paquete se descarta sin respuesta, de modo que un atacante ni siquiera puede
distinguir entre un servicio inexistente y uno protegido.

---

## 6. ¿Qué es un PodDisruptionBudget?

Es un objeto que limita cuántos pods de un conjunto pueden estar simultáneamente
fuera de servicio por una **interrupción voluntaria**.

La distinción entre tipos de interrupción es lo que define su alcance:

- **Voluntarias** — iniciadas por un operador o por el sistema: `kubectl drain`,
  actualizar los nodos, el escalado del clúster. El PDB **sí** interviene: la
  operación se bloquea o espera si dejaría menos pods de los permitidos.
- **Involuntarias** — un nodo que se cae, un kernel panic, un OOM kill. El PDB
  **no** puede hacer nada. No es un mecanismo de alta disponibilidad; para eso
  están las réplicas distribuidas y las probes.

Se expresa con `minAvailable` o `maxUnavailable`. En este chart:

```yaml
spec:
  minAvailable: 1
  selector:
    matchLabels: {...}
```

**El error que hay que evitar**, y que este chart previene explícitamente: si
`minAvailable` iguala o supera el número de réplicas, el presupuesto se vuelve
**imposible de satisfacer** y cualquier drenaje del nodo queda bloqueado
indefinidamente. Un servicio con una réplica y `minAvailable: 1` impide vaciar el
nodo para siempre, y el síntoma es un `kubectl drain` colgado sin explicación
obvia.

Por eso la plantilla acota el valor en lugar de tomarlo tal cual de los values:

```gotemplate
{{- $maximo := sub $replicas 1 }}
{{- $minAvailable := min $deseado $maximo }}
{{- if gt (int $minAvailable) 0 }}
```

Y cuando un servicio corre con una sola réplica —como ocurre en el ambiente de
desarrollo— el chart **no emite el PDB**, porque cualquier valor válido sería 0
(que no protege) o 1 (que bloquearía el nodo).

---

## 7. ¿Qué ventajas y qué nuevos problemas introduce la comunicación asíncrona?

### Ventajas comprobadas en esta práctica

**Desacople temporal.** El productor no necesita que el consumidor exista. Al
detener `notifications-service` y crear seis préstamos, todos respondieron
HTTP 200 en unos 13 ms; los mensajes quedaron en la cola y se procesaron al
restaurarlo, con seis préstamos convertidos en seis notificaciones. En un flujo
síncrono, esas seis peticiones habrían fallado.

**Latencia percibida menor.** `createLoan` responde en 169 ms sin esperar a que
la notificación se escriba. El trabajo secundario ocurre después.

**Absorción de picos.** La cola actúa de amortiguador: si llegan más eventos de
los que el consumidor procesa, se acumulan en lugar de saturarlo.

**Escalado independiente.** Productor y consumidor escalan por separado según su
propia carga.

### Problemas nuevos

**La consistencia deja de ser inmediata.** Cuando `createLoan` responde, la
notificación **todavía no existe**. Si el cliente consultara sus notificaciones
en ese instante, no vería nada, y no sería un error: es consistencia eventual. La
interfaz debe estar diseñada para eso.

**Los mensajes pueden entregarse más de una vez.** Con ack manual, si el
consumidor persiste el dato y muere antes de confirmar, RabbitMQ vuelve a
entregar el mensaje y el registro se duplica. Es la contrapartida inevitable de
no perder mensajes: se elige entre *al menos una vez* y *como mucho una vez*.
Este consumidor prioriza no perder información, así que en un sistema real
habría que hacer el procesamiento idempotente.

**Mensajes veneno.** Un mensaje que siempre falla volvería a la cola
indefinidamente y bloquearía el procesamiento del resto. Por eso el consumidor
lo descarta hacia una cola de mensajes muertos:

```javascript
canal.nack(msg, false, false);   // no reencolar: va a la DLQ
```

**Depurar es más difícil.** Un fallo síncrono deja una traza continua. Aquí el
flujo se parte: hay que mirar los logs del productor, el estado de la cola en el
broker y los logs del consumidor. Los tres pueden verse sanos y el mensaje
haberse quedado en medio.

**Una pieza de infraestructura más.** El broker debe desplegarse, configurarse y
mantenerse, y su caída afecta a todo el flujo. Además introduce un problema de
arranque que apareció literalmente en esta práctica: `loans-service` agotaba diez
reintentos de conexión mientras RabbitMQ terminaba de levantar, y el pod entraba
en CrashLoopBackOff. La corrección fue que el productor reintente en segundo
plano sin bloquear el arranque, en lugar de morir por algo que solo requería
esperar.

**El orden no está garantizado** con varios consumidores en paralelo, y la
transaccionalidad se pierde: escribir en la base de datos y publicar el evento no
son una operación atómica.

### Cuándo conviene

Cuando el trabajo secundario **puede esperar** y su fallo no debe afectar a la
operación principal. Enviar una notificación encaja perfectamente. Validar un
pago antes de confirmar un pedido, no: ahí la respuesta inmediata es parte del
resultado.

---

## 8. ¿Qué hace `helm rollback` internamente?

`helm rollback` **no deshace cambios**: aplica una revisión anterior como si
fuera nueva.

Helm guarda cada revisión de un release en un Secret dentro del namespace, del
tipo `helm.sh/release.v1`:

```
$ kubectl get secrets -n sa-p5 --field-selector type=helm.sh/release.v1
sh.helm.release.v1.sa-platform.v1
sh.helm.release.v1.sa-platform.v2
sh.helm.release.v1.sa-platform.v3
```

Cada uno contiene los manifiestos ya renderizados, los valores usados y los
metadatos, comprimidos y codificados en base64.

Los pasos que ejecuta:

1. **Lee** el Secret de la revisión destino y extrae los manifiestos que se
   aplicaron entonces. No vuelve a renderizar el chart: usa el resultado
   guardado, por eso el rollback funciona aunque los archivos del chart hayan
   cambiado en el disco.
2. **Compara** con los manifiestos de la revisión actual y calcula un parche de
   tres vías: entre el estado anterior, el deseado y el que hay en el clúster.
3. **Aplica** el parche: actualiza lo que difiere, crea lo que faltaba y elimina
   los objetos que la revisión destino no incluía.
4. **Crea una revisión nueva**. Aquí está lo esencial: volver de la 2 a la 1 no
   restaura la revisión 1, genera la **revisión 3** con el contenido de la 1. El
   historial nunca se reescribe:

```
REVISION  STATUS      CHART              APP VERSION  DESCRIPTION
1         superseded  sa-platform-0.1.0  1.0.0        Install complete
2         superseded  sa-platform-0.2.0  1.1.0        Upgrade complete
3         deployed    sa-platform-0.1.0  1.0.0        Rollback to 1
```

Eso permite hacer rollback de un rollback: siempre se avanza hacia adelante.

### Sus límites

**No revierte lo que está fuera del release.** Los datos de la base no vuelven
atrás: si la versión nueva ejecutó una migración destructiva, el rollback
restaura el código pero no los datos.

**Tampoco revierte las imágenes si el tag es móvil.** Este punto es decisivo y
por eso este proyecto usa tags inmutables (`v1`, `v2`, …). Si ambas revisiones
apuntaran a `:latest`, el rollback restauraría el manifiesto, pero el nodo
seguiría ejecutando la última imagen descargada bajo ese nombre: un rollback solo
aparente. Con tags distintos, volver a la revisión 1 devuelve exactamente el
binario que corría entonces, como confirmó la respuesta del servicio tras el
rollback de esta práctica:

```
antes del rollback:   version 1.1.0  ·  imagen sa-p5/api-gateway:v2
después del rollback: version 1.0.0  ·  imagen sa-p5/api-gateway:v1
```

**Depende del historial.** Si el Secret de la revisión destino no existe, el
rollback es imposible. Durante esta práctica ocurrió exactamente eso: una
plantilla que recreaba el namespace borraba esos Secrets, y aunque los objetos
seguían corriendo, el release había desaparecido y `helm upgrade` fallaba con
"has no deployed releases". Sin historial no hay rollback.
