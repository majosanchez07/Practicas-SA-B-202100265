# Evidencia — Ciclo de vida con Helm: install, upgrade y rollback

## 1. Instalación con un solo comando

```bash
helm install sa-platform ./charts/sa-platform \
  --namespace sa-p5 --create-namespace \
  -f ./charts/sa-platform/values-dev.yaml \
  -f ./charts/sa-platform/values.secret.yaml \
  --timeout 10m
```

```
NAME: sa-platform
LAST DEPLOYED: Thu Aug 27 10:48:57 2026
NAMESPACE: sa-p5
STATUS: deployed
REVISION: 1
```

Toda la plataforma queda desplegada: 5 microservicios, PostgreSQL, RabbitMQ y
los dos cronjobs.

```
NAME                                                 READY   STATUS
sa-platform-api-gateway-697cd8d99f-4wbq2             1/1     Running
sa-platform-api-gateway-697cd8d99f-m7blc             1/1     Running
sa-platform-auth-service-998469bc8-wxd8j             1/1     Running
sa-platform-books-service-6f4d6f496-lggnv            1/1     Running
sa-platform-loans-service-5cfccdddc7-fdsm6           1/1     Running
sa-platform-notifications-service-7bcb6f8696-nbmzl   1/1     Running
sa-platform-postgresql-0                             1/1     Running
sa-platform-rabbitmq-0                               1/1     Running
sa-platform-cronjob-insert-29797490-8h75m            Completed
sa-platform-cronjob-summary-29797490-k5lj7           Completed
```

## 2. Estado antes del upgrade

```
$ curl -H "Host: sa-p5.local" http://127.0.0.1/
  version: 1.0.0

$ helm history sa-platform -n sa-p5
REVISION  UPDATED                   STATUS    CHART              APP VERSION  DESCRIPTION
1         Thu Aug 27 10:48:57 2026  deployed  sa-platform-0.1.0  1.0.0        Install complete
```

## 3. Segunda versión del chart y upgrade

Se publicó la versión **0.2.0** del chart (`appVersion` 1.1.0), con una nueva
imagen del API Gateway etiquetada `v2`.

```bash
helm upgrade sa-platform ./charts/sa-platform \
  --namespace sa-p5 \
  -f ./charts/sa-platform/values-dev.yaml \
  -f ./charts/sa-platform/values.secret.yaml \
  --set services.api-gateway.image.tag=v2 \
  --timeout 8m --wait
```

```
NAME: sa-platform
LAST DEPLOYED: Thu Aug 27 11:13:23 2026
STATUS: deployed
REVISION: 2
```

El cambio se verifica en la respuesta real del servicio, no solo en el manifiesto:

```
  version que responde: 1.1.0
  imagen desplegada:    sa-p5/api-gateway:v2
```

```
$ helm history sa-platform -n sa-p5
REVISION  UPDATED                   STATUS      CHART              APP VERSION  DESCRIPTION
1         Thu Aug 27 10:48:57 2026  superseded  sa-platform-0.1.0  1.0.0        Install complete
2         Thu Aug 27 11:13:23 2026  deployed    sa-platform-0.2.0  1.1.0        Upgrade complete
```

## 4. Rollback a la revisión anterior

```bash
helm rollback sa-platform 1 --namespace sa-p5 --timeout 8m --wait
```

```
Rollback was a success! Happy Helming!
```

La aplicación vuelve efectivamente a la versión previa:

```
  version que responde: 1.0.0
  imagen desplegada:    sa-p5/api-gateway:v1
```

## 5. Historial final

```
$ helm history sa-platform -n sa-p5
REVISION  UPDATED                   STATUS      CHART              APP VERSION  DESCRIPTION
1         Thu Aug 27 10:48:57 2026  superseded  sa-platform-0.1.0  1.0.0        Install complete
2         Thu Aug 27 11:13:23 2026  superseded  sa-platform-0.2.0  1.1.0        Upgrade complete
3         Thu Aug 27 11:14:08 2026  deployed    sa-platform-0.1.0  1.0.0        Rollback to 1

$ helm list -n sa-p5
NAME         NAMESPACE  REVISION  STATUS    CHART              APP VERSION
sa-platform  sa-p5      3         deployed  sa-platform-0.1.0  1.0.0
```

## Nota sobre por qué el rollback devuelve el binario correcto

Cada despliegue usa un tag de imagen distinto (`v1`, `v2`, …) en lugar de un tag
móvil. Si ambas revisiones apuntaran al mismo tag, `helm rollback` restauraría
el manifiesto anterior pero el nodo seguiría ejecutando la última imagen
descargada bajo ese nombre, y el rollback sería solo aparente. Con tags
inmutables, volver a la revisión 1 devuelve exactamente el binario que estaba
corriendo entonces, como confirma la respuesta `version: 1.0.0`.
