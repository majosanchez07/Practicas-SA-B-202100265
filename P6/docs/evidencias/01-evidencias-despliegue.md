# Evidencias de funcionamiento — Práctica 6

Generado el 2026-09-04 21:23:57 CST con `scripts/04-evidencias.sh`.

Toda la salida de esta página proviene de la ejecución real de los comandos
contra el clúster administrado; no hay salidas transcritas a mano.

## 1. Clúster administrado y sus nodos
```
$ eksctl get cluster --name sa-p6-202100265 --region us-east-2
NAME		VERSION	STATUS	CREATED			VPC			SUBNETS																			SECURITYGROUPS		PROVIDER
sa-p6-202100265	1.31	ACTIVE	2026-09-05T02:47:41Z	vpc-077b1ce248cde4d31	subnet-0301f95540ac4d773,subnet-064c08151c3d93018,subnet-09d02b1ee99323edf,subnet-0a73a0c8e08f4196f,subnet-0fbf77c815693e970,subnet-0fd5b22ec726aefaf	sg-00106a21d0ce6b278	EKS

$ kubectl config current-context
iam-root-account@sa-p6-202100265.us-east-2.eksctl.io

$ kubectl get nodes -o wide
NAME                                           STATUS   ROLES    AGE   VERSION                INTERNAL-IP      EXTERNAL-IP     OS-IMAGE                        KERNEL-VERSION                    CONTAINER-RUNTIME
ip-192-168-6-197.us-east-2.compute.internal    Ready    <none>   24m   v1.31.14-eks-cb19647   192.168.6.197    3.135.203.107   Amazon Linux 2023.12.20260817   6.1.180-225.360.amzn2023.x86_64   containerd://2.2.5+unknown
ip-192-168-73-161.us-east-2.compute.internal   Ready    <none>   24m   v1.31.14-eks-cb19647   192.168.73.161   18.216.47.253   Amazon Linux 2023.12.20260817   6.1.180-225.360.amzn2023.x86_64   containerd://2.2.5+unknown
```

## 2. Componentes en ejecución
```
$ kubectl get pods -n sa-p6 -o wide
NAME                                                       READY   STATUS      RESTARTS      AGE    IP               NODE                                           NOMINATED NODE   READINESS GATES
sa-p6-postgresql-0                                         1/1     Running     0             12m    192.168.17.74    ip-192-168-6-197.us-east-2.compute.internal    <none>           <none>
sa-p6-rabbitmq-0                                           1/1     Running     0             12m    192.168.87.63    ip-192-168-73-161.us-east-2.compute.internal   <none>           <none>
sa-p6-sa-platform-api-gateway-778c8fbc97-mjvlx             1/1     Running     0             12m    192.168.16.240   ip-192-168-6-197.us-east-2.compute.internal    <none>           <none>
sa-p6-sa-platform-auth-service-5df7d58d57-g9lnm            1/1     Running     2 (12m ago)   12m    192.168.6.57     ip-192-168-6-197.us-east-2.compute.internal    <none>           <none>
sa-p6-sa-platform-books-service-57ffc9d447-fglhp           1/1     Running     2 (12m ago)   12m    192.168.70.148   ip-192-168-73-161.us-east-2.compute.internal   <none>           <none>
sa-p6-sa-platform-cronjob-insert-29809638-rk7db            0/1     Completed   0             6m3s   192.168.78.15    ip-192-168-73-161.us-east-2.compute.internal   <none>           <none>
sa-p6-sa-platform-cronjob-insert-29809640-tjjh2            0/1     Completed   0             4m3s   192.168.78.15    ip-192-168-73-161.us-east-2.compute.internal   <none>           <none>
sa-p6-sa-platform-cronjob-insert-29809642-xjdr8            0/1     Completed   0             2m3s   192.168.78.15    ip-192-168-73-161.us-east-2.compute.internal   <none>           <none>
sa-p6-sa-platform-cronjob-insert-29809644-sxvgd            1/1     Running     0             3s     192.168.78.15    ip-192-168-73-161.us-east-2.compute.internal   <none>           <none>
sa-p6-sa-platform-cronjob-summary-29809640-2z57f           0/1     Completed   0             4m3s   192.168.10.101   ip-192-168-6-197.us-east-2.compute.internal    <none>           <none>
sa-p6-sa-platform-loans-service-657d9d9549-h6mmn           1/1     Running     2 (12m ago)   12m    192.168.22.131   ip-192-168-6-197.us-east-2.compute.internal    <none>           <none>
sa-p6-sa-platform-notifications-service-756fb6dfcb-9frqx   1/1     Running     2 (12m ago)   12m    192.168.78.113   ip-192-168-73-161.us-east-2.compute.internal   <none>           <none>

$ kubectl get deploy,sts,svc,pvc,hpa,cronjob -n sa-p6
NAME                                                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/sa-p6-sa-platform-api-gateway             1/1     1            1           12m
deployment.apps/sa-p6-sa-platform-auth-service            1/1     1            1           12m
deployment.apps/sa-p6-sa-platform-books-service           1/1     1            1           12m
deployment.apps/sa-p6-sa-platform-loans-service           1/1     1            1           12m
deployment.apps/sa-p6-sa-platform-notifications-service   1/1     1            1           12m

NAME                                READY   AGE
statefulset.apps/sa-p6-postgresql   1/1     12m
statefulset.apps/sa-p6-rabbitmq     1/1     12m

NAME                                              TYPE           CLUSTER-IP       EXTERNAL-IP                                                                     PORT(S)                                 AGE
service/sa-p6-postgresql                          ClusterIP      10.100.102.165   <none>                                                                          5432/TCP                                12m
service/sa-p6-postgresql-hl                       ClusterIP      None             <none>                                                                          5432/TCP                                12m
service/sa-p6-rabbitmq                            ClusterIP      10.100.196.164   <none>                                                                          5672/TCP,4369/TCP,25672/TCP,15672/TCP   12m
service/sa-p6-rabbitmq-headless                   ClusterIP      None             <none>                                                                          4369/TCP,5672/TCP,25672/TCP,15672/TCP   12m
service/sa-p6-sa-platform-api-gateway             ClusterIP      10.100.80.40     <none>                                                                          8080/TCP                                12m
service/sa-p6-sa-platform-api-gateway-public      LoadBalancer   10.100.126.10    a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com   80:30288/TCP                            3m17s
service/sa-p6-sa-platform-auth-service            ClusterIP      10.100.238.145   <none>                                                                          8000/TCP                                12m
service/sa-p6-sa-platform-books-service           ClusterIP      10.100.18.184    <none>                                                                          8001/TCP                                12m
service/sa-p6-sa-platform-loans-service           ClusterIP      10.100.8.246     <none>                                                                          8002/TCP                                12m
service/sa-p6-sa-platform-notifications-service   ClusterIP      10.100.172.160   <none>                                                                          8003/TCP                                12m

NAME                                            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/data-sa-p6-postgresql-0   Bound    pvc-7088a713-be78-400b-b22f-9f8bc83836ff   8Gi        RWO            gp3            <unset>                 12m
persistentvolumeclaim/data-sa-p6-rabbitmq-0     Bound    pvc-37eb9d34-e912-454d-b01b-7f06fede53bf   8Gi        RWO            gp3            <unset>                 12m

NAME                                                                          REFERENCE                                            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/sa-p6-sa-platform-api-gateway             Deployment/sa-p6-sa-platform-api-gateway             cpu: 4%/70%   1         2         1          12m
horizontalpodautoscaler.autoscaling/sa-p6-sa-platform-auth-service            Deployment/sa-p6-sa-platform-auth-service            cpu: 6%/70%   1         2         1          12m
horizontalpodautoscaler.autoscaling/sa-p6-sa-platform-books-service           Deployment/sa-p6-sa-platform-books-service           cpu: 6%/70%   1         2         1          12m
horizontalpodautoscaler.autoscaling/sa-p6-sa-platform-loans-service           Deployment/sa-p6-sa-platform-loans-service           cpu: 2%/70%   1         2         1          12m
horizontalpodautoscaler.autoscaling/sa-p6-sa-platform-notifications-service   Deployment/sa-p6-sa-platform-notifications-service   cpu: 2%/70%   1         2         1          12m

NAME                                              SCHEDULE       TIMEZONE            SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/sa-p6-sa-platform-cronjob-insert    */2 * * * *    America/Guatemala   False     1        6s              12m
cronjob.batch/sa-p6-sa-platform-cronjob-summary   */10 * * * *   America/Guatemala   False     0        4m6s            12m
```

## 3. Almacenamiento con la StorageClass del proveedor
```
$ kubectl get storageclass
NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp2             kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  31m
gp3 (default)   ebs.csi.aws.com         Delete          WaitForFirstConsumer   true                   21m

$ kubectl get pv -o custom-columns=NOMBRE:.metadata.name,CAPACIDAD:.spec.capacity.storage,SC:.spec.storageClassName,ESTADO:.status.phase
NOMBRE                                     CAPACIDAD   SC    ESTADO
pvc-37eb9d34-e912-454d-b01b-7f06fede53bf   8Gi         gp3   Bound
pvc-7088a713-be78-400b-b22f-9f8bc83836ff   8Gi         gp3   Bound
```

## 4. Secretos gestionados dentro del clúster

Se listan los nombres y el número de claves; **nunca los valores**.
```
$ kubectl get secrets -n sa-p6 -o custom-columns=NOMBRE:.metadata.name,TIPO:.type
NOMBRE                        TIPO
sa-p6-postgresql              Opaque
sa-p6-rabbitmq                Opaque
sa-p6-rabbitmq-config         Opaque
sa-p6-sa-platform-secret      Opaque
sh.helm.release.v1.sa-p6.v1   helm.sh/release.v1
```

## 5. Peticiones desde internet a la dirección pública

Dirección pública del Network Load Balancer: `http://a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com`

```
$ curl -s -o /dev/null -w 'GET / -> HTTP %{http_code} en %{time_total}s\n' http://a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com/
GET / -> HTTP 200 en 0.283686s
$ curl -s -w '\n-> HTTP %{http_code}\n' http://a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com/health/ready
{"status":"ready","service":"api-gateway","dependencias":{"auth":"up","books":"up","loans":"up","notifications":"up"}}
-> HTTP 200

# El DNS del balanceador resuelve a direcciones publicas de AWS:
$ getent hosts a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com
3.131.200.215   a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com
```

## 6. Capturas de pantalla

