# Evidencia del despliegue automatico — Practica 7

- Namespace: `sa-p7`
- Fecha (UTC): 2026-09-11 05:16:46
- Commit: `local`
- Ejecucion: `local`

## Pods

```
NAME                                                 READY   STATUS      RESTARTS       AGE    IP            NODE                         NOMINATED NODE   READINESS GATES
sa-platform-api-gateway-5dfdd8fb9-wvsx5              1/1     Running     0              114s   10.244.0.17   p7-202100265-control-plane   <none>           <none>
sa-platform-auth-service-5cf475865b-nktr5            1/1     Running     2 (107s ago)   114s   10.244.0.21   p7-202100265-control-plane   <none>           <none>
sa-platform-books-service-74cb6f59d4-jbfg8           1/1     Running     2 (107s ago)   114s   10.244.0.19   p7-202100265-control-plane   <none>           <none>
sa-platform-cronjob-insert-29818396-5jsnj            0/1     Completed   0              46s    10.244.0.26   p7-202100265-control-plane   <none>           <none>
sa-platform-loans-service-67d5d9c8f5-n7wcj           1/1     Running     2 (108s ago)   114s   10.244.0.20   p7-202100265-control-plane   <none>           <none>
sa-platform-notifications-service-76466f6f6b-ld7wz   1/1     Running     2 (110s ago)   114s   10.244.0.18   p7-202100265-control-plane   <none>           <none>
sa-platform-postgresql-0                             1/1     Running     0              114s   10.244.0.24   p7-202100265-control-plane   <none>           <none>
sa-platform-rabbitmq-0                               1/1     Running     0              114s   10.244.0.25   p7-202100265-control-plane   <none>           <none>
```

## Imagenes desplegadas

```
TIPO         NOMBRE                              IMAGEN
Deployment   sa-platform-api-gateway             p7-api-gateway:local
Deployment   sa-platform-auth-service            p7-auth-service:local
Deployment   sa-platform-books-service           p7-books-service:local
Deployment   sa-platform-loans-service           p7-loans-service:local
Deployment   sa-platform-notifications-service   p7-notifications-service:local
CronJob   sa-platform-cronjob-insert    p7-cronjob-insert:local
CronJob   sa-platform-cronjob-summary   p7-cronjob-summary:local
```
