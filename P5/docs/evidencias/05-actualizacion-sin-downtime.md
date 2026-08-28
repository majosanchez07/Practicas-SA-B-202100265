# Evidencia — Actualización sin caída de servicio

## Método

Se lanzaron **400 peticiones consecutivas** contra el API Gateway a través del
Ingress, a intervalos de 0.25 s, mientras se ejecutaba un `helm upgrade` que
cambiaba la imagen del gateway de la versión 1.0.0 a la 1.1.0. Cada petición
registra el código HTTP, la latencia y la versión que responde.

```bash
# En paralelo al sondeo:
helm upgrade sa-platform ./charts/sa-platform --namespace sa-p5   -f values-dev.yaml -f values.secret.yaml   --set services.api-gateway.image.tag=v2 --timeout 8m --wait
```

```
inicio: 11:27:02
STATUS: deployed
REVISION: 2
fin:    11:27:28
```

## Resultado

```
=== 400 peticiones durante el rolling update ===
  codigos HTTP : {'200': 400}
  errores      : 0  (0.00%)
  versiones    : {'1.0.0': 76, '1.1.0': 324}
  latencia     : min 5ms  p95 9ms  max 87ms
```

**Ninguna petición falló durante la actualización.**

## La transición se observa en las respuestas

Durante la ventana del rolling update, las respuestas alternan entre ambas
versiones porque el Service reparte entre los pods antiguos y los nuevos, que
conviven mientras dura la transición:

```
  peticion # 69: 1.0.0 -> 1.1.0
  peticion # 71: 1.1.0 -> 1.0.0
  peticion # 73: 1.0.0 -> 1.1.0
  peticion # 78: 1.1.0 -> 1.0.0
  peticion # 81: 1.0.0 -> 1.1.0
  peticion # 83: 1.1.0 -> 1.0.0
  peticion # 85: 1.0.0 -> 1.1.0
  peticion # 87: 1.1.0 -> 1.0.0
  peticion # 88: 1.0.0 -> 1.1.0
```

Esa alternancia es la prueba de que la actualización fue progresiva: en ningún
momento dejó de haber pods atendiendo. Si la estrategia retirara los pods viejos
antes de tener los nuevos listos, aparecerían códigos 502 o 503 en la ventana.

## Qué lo hace posible

**`maxUnavailable: 0`** en la estrategia de actualización. Kubernetes no retira
un pod antiguo hasta que el nuevo pasa su readiness probe, de modo que la
capacidad disponible nunca baja de la deseada:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

Durante la transición llegan a coexistir tres pods para un Deployment de dos
réplicas, como se observó al capturar el estado a mitad de una actualización:

```
NAME                                       READY   STATUS
sa-platform-api-gateway-58cc9d4745-72vgc   1/1     Running
sa-platform-api-gateway-58cc9d4745-7fkmj   0/1     Running       <- nuevo, aun no listo
sa-platform-api-gateway-6fd65498d9-69bxh   1/1     Running
sa-platform-api-gateway-6fd65498d9-tjz56   1/1     Terminating   <- viejo, saliendo
```

Dos elementos más contribuyen a que no se pierda ninguna petición:

- **`preStop` con una pausa de 5 segundos.** Retrasa el SIGTERM lo suficiente
  para que el endpoint salga de las tablas de los kube-proxy antes de que el
  proceso empiece a cerrarse. Sin esa pausa, las peticiones ya enrutadas hacia
  el pod que se retira se perderían.

- **`dumb-init` como punto de entrada de las imágenes Node.** Sin él, `node`
  corre como PID 1 y no recibe SIGTERM, por lo que Kubernetes tendría que
  terminar el pod por la fuerza al agotarse el `terminationGracePeriod`,
  cortando las conexiones en curso.
