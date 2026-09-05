# Evidencia — Peticiones desde internet a la dirección pública

Dirección pública del Network Load Balancer:

```
http://a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com
```

Esta dirección es un nombre DNS de AWS resoluble desde cualquier punto de
internet; no requiere VPN, túnel ni entrada en `/etc/hosts`.

## Resolución DNS

```
$ getent hosts a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com
16.59.131.119   a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com
3.131.200.215   a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com
77.112.128.107  a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com
```

Las direcciones devueltas son IP públicas de AWS, una por zona de
disponibilidad, lo que confirma que el balanceador es `internet-facing` y opera
en varias zonas.

## Peticiones realizadas

Ejecutadas el 2026-09-04 a las 21:26:07 CST desde una máquina fuera del clúster:

```
$ curl -i http://<NLB>/health/live    ->  HTTP 200 en 0.298343s
$ curl -i http://<NLB>/health/ready   ->  HTTP 200 en 0.197117s
$ curl -i http://<NLB>/               ->  HTTP 200 en 0.400185s
$ curl -i http://<NLB>/books          ->  HTTP 200 en 0.293669s
$ curl -i http://<NLB>/auth/docs      ->  HTTP 200 en 0.247897s
```

Todas responden **HTTP 200**, incluidas las rutas enrutadas por el API Gateway
hacia los microservicios internos (`/books` al books-service y `/auth/docs` al
auth-service), lo que demuestra que el enrutamiento interno funciona a través
del único punto de entrada público.

## Respuesta completa del health check

```json
{"status":"ready","service":"api-gateway","dependencias":{"auth":"up","books":"up","loans":"up","notifications":"up"}}
```

## Verificación del tipo de balanceador

```
$ kubectl get svc -n sa-p6 -l sa-platform.io/role=public-entrypoint
NAME                                   TYPE           CLUSTER-IP      EXTERNAL-IP                                                                     PORT(S)        AGE
sa-p6-sa-platform-api-gateway-public   LoadBalancer   10.100.126.10   a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com   80:30288/TCP   5m23s
```

El resto de los Services del namespace conservan su `ClusterIP` y no son
alcanzables desde fuera:

```
sa-p6-postgresql                              ClusterIP
sa-p6-postgresql-hl                           ClusterIP
sa-p6-rabbitmq                                ClusterIP
sa-p6-rabbitmq-headless                       ClusterIP
sa-p6-sa-platform-api-gateway                 ClusterIP
sa-p6-sa-platform-api-gateway-public          LoadBalancer
sa-p6-sa-platform-auth-service                ClusterIP
sa-p6-sa-platform-books-service               ClusterIP
sa-p6-sa-platform-loans-service               ClusterIP
sa-p6-sa-platform-notifications-service       ClusterIP
```
