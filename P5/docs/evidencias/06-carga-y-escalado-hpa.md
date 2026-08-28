# Evidencia — Prueba de carga y escalado automático (HPA)

## Script

`P5/loadtest/carga.js`, ejecutado con **k6 v2.2.0**. La carga entra por el
Ingress, que es la única puerta de entrada al clúster; no se golpea ningún
microservicio directamente.

Concurrencia creciente por escalones, para dar al HPA tiempo de observar el
consumo y decidir en lugar de un pico instantáneo:

```javascript
stages: [
  { duration: '30s', target: 10 },   // calentamiento
  { duration: '45s', target: 30 },   // primer escalón
  { duration: '60s', target: 60 },   // segundo escalón
  { duration: '60s', target: 100 },  // carga sostenida alta
  { duration: '30s', target: 0 },    // descenso, para observar el scale down
]
```

```bash
k6 run carga.js
```

## Resultados de la prueba de carga

```
=========================================================
  RESULTADOS DE LA PRUEBA DE CARGA — Carné 202100265
=========================================================
  Peticiones totales : 103065
  Peticiones/segundo : 457.73 RPS
  Latencia media     : 16.51 ms
  Latencia p95       : 67.88 ms
  Latencia máxima    : 1063.31 ms
  Tasa de error      : 0.00 %
  VUs máximos        : 100
=========================================================
```

| Métrica solicitada | Valor |
|---|---|
| **Peticiones por segundo** | **457.73 RPS** |
| **Latencia p95** | **67.88 ms** |
| **Porcentaje de error** | **0.00 %** |

## Escalado automático bajo carga

`kubectl get hpa -w` y `kubectl get pods -w`, muestreados cada 4 segundos:

```
11:32:33   10%/70%  replicas=2  pods=2 listos=2     <- reposo
11:33:27   68%/70%  replicas=2  pods=2 listos=2     <- carga subiendo, aún bajo el umbral
11:34:23  426%/70%  replicas=2  pods=4 listos=2     <- superado el 70 %: se crean pods
11:34:41  426%/70%  replicas=4  pods=4 listos=4     <- 4 réplicas listas
11:35:00  426%/70%  replicas=4  pods=5 listos=5
11:35:05  426%/70%  replicas=5  pods=5 listos=5     <- máximo alcanzado
11:35:18  510%/70%  replicas=5  pods=5 listos=5
11:36:20  572%/70%  replicas=5  pods=5 listos=5     <- carga sostenida en el tope
```

El HPA escaló de **2 a 5 réplicas** (el máximo configurado) al superarse el
umbral del 70 % de uso de CPU. El consumo llegó al 572 %, muy por encima del
objetivo, porque el HPA ya no podía crear más réplicas: `maxReplicas: 5` es el
techo fijado por el enunciado.

## Descenso de réplicas al cesar la carga

```
11:37:02  572%/70%  replicas=5  pods=5     <- fin de la carga
11:39:18    8%/70%  replicas=4  pods=4
11:40:23    8%/70%  replicas=3  pods=3
11:41:21    8%/70%  replicas=2  pods=2     <- vuelta al mínimo
```

El descenso es **gradual, de una réplica por minuto**, y se detiene en 2, que es
el `minReplicas` configurado. Ese comportamiento está definido explícitamente en
el chart:

```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 60
    policies:
      - type: Pods
        value: 1
        periodSeconds: 60
    selectPolicy: Min
```

La ventana de estabilización de 60 segundos evita que un valle momentáneo del
tráfico reduzca réplicas de golpe; el valor por defecto de Kubernetes son cinco
minutos, que habría hecho el descenso difícil de observar dentro de la sesión de
evidencia.

## Estado de la plataforma bajo carga

Ningún pod se reinició durante los 3 min 45 s de prueba a 457 RPS:

```
sa-platform-api-gateway-7fd854dc67-7562z    1/1 Running reinicios=0
sa-platform-api-gateway-7fd854dc67-8qcc4    1/1 Running reinicios=0
sa-platform-api-gateway-7fd854dc67-c2fnv    1/1 Running reinicios=0
sa-platform-api-gateway-7fd854dc67-f7wkd    1/1 Running reinicios=0
sa-platform-api-gateway-7fd854dc67-gszlf    1/1 Running reinicios=0
sa-platform-auth-service-5bddb65699-4k7pk   1/1 Running reinicios=0
sa-platform-books-service-644b6b5445-dfmm8  1/1 Running reinicios=0
sa-platform-loans-service-65bcd94858-cmp9l  1/1 Running reinicios=0
```

Los cronjobs continuaron ejecutándose con normalidad durante la prueba
(`cronjob-insert` completó en los minutos 29797532, 29797534 y 29797536).

La ResourceQuota mantuvo margen suficiente para el escalado:

```
pods: 11/30   requests.cpu: 425m/3   limits.cpu: 2800m/6   limits.memory: 3008Mi/8Gi
```

Esto confirma el dimensionamiento hecho al definir la cuota: si el techo hubiera
quedado por debajo del pico del HPA, el autoescalado se habría detenido contra
la cuota en lugar de contra el objetivo de CPU, y esta evidencia habría quedado
falseada sin ninguna señal aparente.
