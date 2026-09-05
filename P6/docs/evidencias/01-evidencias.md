# Evidencias de funcionamiento — Práctica 6

Despliegue de la plataforma de microservicios en **Amazon EKS**, cuenta
`949867896677`, región `us-east-2` (Ohio). Capturas y salidas obtenidas el
4 de septiembre de 2026 sobre el despliegue real.

Dirección pública del sistema:

```
http://a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com
```

Cada sección presenta primero la captura de la consola o del clúster y después
la salida literal de los comandos que la respaldan. Ninguna salida está
transcrita a mano.

---

## 1. El clúster administrado

![Clúster EKS](capturas/01-eks-cluster.png)

El clúster `sa-p6-202100265` en estado **Activo**, con Kubernetes **1.31** y el
proveedor **EKS**. Se aprecian el punto de enlace del servidor de la API, la URL
del proveedor OpenID Connect y el ARN del rol de IAM: elementos que sólo existen
en un clúster administrado y que no tienen equivalente en uno local.

![Listado de clústeres](capturas/03-eks-listado-clusters.png)

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

---

## 2. Los nodos de trabajo

![Nodos EC2](capturas/02-nodos-ec2.png)

Las **dos instancias `t3.small`** del grupo de nodos, en ejecución y repartidas
entre las zonas de disponibilidad `us-east-2a` y `us-east-2c`, cada una con sus
3/3 comprobaciones de estado superadas. Son las máquinas que aparecen como nodos
en la salida de `kubectl get nodes` de la sección anterior.

![Nodos y almacenamiento](capturas/09-nodos-y-almacenamiento.png)

---

## 3. El registro de contenedores

![Repositorios de ECR](capturas/04-ecr-repositorios.png)

Los **siete repositorios privados** creados en Amazon ECR, uno por componente:
los cinco microservicios y los dos cronjobs. Se muestra la URI completa de cada
uno, que es exactamente la que aparece en el campo `image` de los Deployments.

Que los pods estén en `Running` y no en `ImagePullBackOff` demuestra que el
clúster descarga las imágenes de este registro sin errores.

---

## 4. Los componentes en ejecución

![Pods en ejecución](capturas/08-pods-en-ejecucion.png)

Los **siete pods en `Running`** —los cinco microservicios más PostgreSQL y
RabbitMQ— repartidos entre los dos nodos, junto con los CronJobs en
`Completed`. Ningún pod en error.

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

---

## 5. Almacenamiento persistente del proveedor

Los PersistentVolumeClaim quedan en estado `Bound` sobre la StorageClass
**`gp3`**, respaldada por el driver CSI de EBS (`ebs.csi.aws.com`). A diferencia
del `local-path` de un clúster local, estos volúmenes son discos de red
independientes del nodo: el dato sobrevive a que el pod se reprograme en otra
máquina.

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

---

## 6. Gestión de credenciales

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

Ninguna de estas credenciales está versionada en el repositorio: se generan al
desplegar y Helm las materializa como Secret dentro del clúster.

---

## 7. Exposición pública del sistema

![Network Load Balancer](capturas/05-load-balancer.png)

El **Network Load Balancer** creado automáticamente por el
cloud-controller-manager de EKS al aplicar el Service de tipo LoadBalancer:
estado **Activo**, tipo **network**, esquema **Internet-facing**, distribuido en
**3 zonas de disponibilidad**.

### Aislamiento de la red

![Servicios y petición](capturas/10-servicios-y-peticion.png)

Todos los Services son `ClusterIP` excepto el único `LoadBalancer`, que expone
el API Gateway. La base de datos, el broker y los microservicios internos no son
alcanzables desde internet.

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

---

## 8. Peticiones realizadas desde internet

![Health check desde el navegador](capturas/06-app-desde-internet.png)

El navegador apuntando a la dirección pública del balanceador. La respuesta JSON
declara `status: "ready"` y las cuatro dependencias internas (`auth`, `books`,
`loans`, `notifications`) en `"up"`, lo que demuestra a la vez el acceso público
y el enrutamiento interno entre microservicios.

![Endpoint /books](capturas/07-books-desde-internet.png)

### Resolución DNS

```
$ getent hosts a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com
16.59.131.119   a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com
3.131.200.215   a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com
77.112.128.107  a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com
```

Las direcciones devueltas son IP públicas de AWS, una por zona de
disponibilidad, lo que confirma que el balanceador es `internet-facing` y opera
en varias zonas.

### Peticiones y códigos de respuesta

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

### Respuesta completa del health check

```json
{"status":"ready","service":"api-gateway","dependencias":{"auth":"up","books":"up","loans":"up","notifications":"up"}}
```
