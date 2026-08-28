# Decisiones técnicas y problemas resueltos

Registro de los obstáculos encontrados durante el despliegue y el criterio con
que se resolvieron. Se documentan porque varios no son evidentes y condicionan
la forma del chart.

## 1. Bitnami trasladó sus imágenes a un catálogo de pago

Los charts de `postgresql` y `rabbitmq` apuntan por defecto a imágenes que ya no
se pueden descargar desde el repositorio público: el chart de RabbitMQ referencia
`bitnami/rabbitmq:4.1.3-debian-12-r1`, cuyo manifiesto ya no existe, y el de
PostgreSQL pasó a `tag: latest`. Instalarlos sin más deja los pods en
`ImagePullBackOff`.

**Solución.** Se redirige el registro al repositorio `bitnamilegacy`, que
conserva las imágenes publicadas antes del cambio, y se declara
`global.security.allowInsecureImages: true`, que los charts exigen al detectar
una imagen distinta de la oficial.

## 2. Las NetworkPolicies de Bitnami anulaban el aislamiento

Ambos charts incluyen su propia NetworkPolicy, pero su regla de entrada declara
solo el puerto y ninguna cláusula `from`:

```yaml
ingress:
  - ports:
      - port: 5432
```

En la semántica de NetworkPolicy eso equivale a **permitir la conexión desde
cualquier pod del clúster**. Las políticas propias habrían quedado escritas y la
base de datos igualmente accesible, sin ninguna señal de que algo fallaba.

**Solución.** Se desactivan (`primary.networkPolicy.enabled: false` en
PostgreSQL, `networkPolicy.enabled: false` en RabbitMQ) y el acceso queda
gobernado por las 13 políticas definidas en `templates/networkpolicies.yaml`.

## 3. Helm no puede crear el namespace donde registra su propio release

Helm guarda el estado de cada revisión en un Secret alojado dentro del namespace
del release, y lo escribe **antes** de aplicar las plantillas. Se probaron las
tres vías posibles:

| Intento | Resultado |
|---|---|
| Hook `pre-install` con `hook-delete-policy: before-hook-creation` | El hook recrea el namespace y arrastra el Secret del release. `helm install` reporta `STATUS: deployed`, los objetos quedan corriendo, pero el release desaparece de `helm list` y todo `helm upgrade` falla con `has no deployed releases` |
| Hook `pre-install` sin política de borrado | Igual: el hook sigue recreando el namespace después de que Helm escribió el Secret |
| Recurso ordinario sin `--create-namespace` | `create: failed to create: namespaces "sa-p5" not found` |
| Release en un namespace de gestión aparte | El chart de PostgreSQL ignora `namespaceOverride` en sus plantillas: la base de datos queda fuera de `sa-p5`, separada de los microservicios y del alcance de las NetworkPolicies |

Este fue el problema más costoso de diagnosticar, porque la instalación
**reportaba éxito**: los pods corrían con normalidad y nada indicaba que el
historial de revisiones se hubiera perdido.

**Solución.** La definición del namespace se conserva en
`templates/namespace.yaml`, versionada dentro del chart, y la instalación pasa
`--create-namespace` con `namespace.create: false`. La bandera solo resuelve el
arranque; el namespace sigue declarado en el chart y se puede renderizar con
`--set namespace.create=true`.

## 4. El API Gateway colgaba todas las peticiones POST

Las peticiones GET se enrutaban con normalidad, pero cualquier POST quedaba
esperando hasta agotar el tiempo del cliente. El diagnóstico se hizo por
descarte, acotando el problema capa por capa:

| Prueba | Resultado |
|---|---|
| POST al servicio destino, saltando el gateway | 200, préstamo creado |
| POST al gateway desde otro pod | timeout |
| POST al gateway desde `127.0.0.1` **dentro de su propio pod** | timeout |
| POST del gateway al servicio destino con el módulo `http` nativo | 200 en 99 ms |

La última prueba descartó la red y las NetworkPolicies: el fallo estaba en
`http-proxy-middleware`, que no reenviaba el cuerpo. Se probaron la versión 2 y
la 3 con el mismo resultado.

**Solución.** El gateway solo elige un destino y encadena dos flujos, de modo
que la dependencia no aportaba nada que justificara arrastrar el fallo. Se
sustituyó por `src/proxy.js`, unas cuarenta líneas sobre el módulo `http`.
Tiempo de respuesta tras el cambio: **169 ms**.

## 5. Las imágenes reconstruidas no llegaban al clúster

Durante el diagnóstico anterior, varias correcciones parecían no surtir efecto.
La causa era que `minikube image load` no reemplaza una imagen que ya existe en
el nodo con el mismo tag, y `imagePullPolicy: IfNotPresent` hacía que los pods
siguieran usando la versión antigua. Se confirmó comparando el código dentro del
pod con el local:

```
$ kubectl exec ... -- ls src/
index.js            <- faltaba proxy.js
$ kubectl exec ... -- head -3 src/index.js
const { createProxyMiddleware } = require('http-proxy-middleware');   <- código viejo
```

**Solución.** Cada cambio de imagen usa un tag nuevo (`v1`, `v2`, …), que además
es lo que permite que `helm rollback` devuelva exactamente el binario anterior.

## 6. Un arranque lento del broker mataba a loans-service

`loans-service` agotaba diez reintentos de conexión a RabbitMQ y propagaba la
excepción, con lo que el proceso moría y el pod entraba en `CrashLoopBackOff`.
El broker tarda más en estar listo que el microservicio, así que solo faltaba
esperar.

**Solución.** El productor reintenta de forma indefinida y en segundo plano, sin
bloquear el arranque: el servicio atiende de inmediato las operaciones que no
dependen del broker y se engancha en cuanto aparece. El consumidor aplica el
mismo criterio.

## 7. La cuota de producción no cubría el pico del HPA

Con los cinco servicios en su máximo de 5 réplicas, la suma de `limits.cpu`
asciende a unos 15.9 núcleos, mientras que la `ResourceQuota` fijaba un techo de
12. El autoescalado se habría detenido contra la cuota en lugar de contra el
objetivo de CPU, y la evidencia de escalado habría quedado falseada sin ninguna
señal aparente.

**Solución.** Se recalculó el peor caso y se subió el techo a 20 núcleos y 18 Gi,
dejando margen por encima del pico.

## 8. Zona horaria invertida en el resumen

El Cronjob 2 agrupaba las ejecuciones en la hora `21:00` para registros de las
`09:22` GMT-6. La causa es que en la sintaxis POSIX que acepta PostgreSQL,
`AT TIME ZONE 'UTC-6'` significa UTC**+**6:

```
 ejecutado_en (UTC)  : 2026-08-27 15:22:43+00
 AT TIME ZONE UTC-6  : 2026-08-27 21:22:43     <- incorrecto
 America/Guatemala   : 2026-08-27 09:22:43     <- correcto
```

**Solución.** Se usa `America/Guatemala`, que es GMT-6 permanente y además
expresa la intención de forma legible.
