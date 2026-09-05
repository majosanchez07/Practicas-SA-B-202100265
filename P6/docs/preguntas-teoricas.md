# Preguntas teóricas — Práctica 6

## 1. ¿Qué es un clúster de Kubernetes administrado y qué diferencias tiene frente a uno local?

Un clúster administrado es aquel en el que el proveedor de nube se hace cargo del
**plano de control** —el API server, etcd, el scheduler y los controladores— y lo
opera como un servicio: lo replica entre zonas de disponibilidad, lo respalda, lo
parchea y lo actualiza. El usuario recibe únicamente un endpoint contra el que
apuntar `kubectl` y decide qué nodos de trabajo conectar.

Al llevar esta plataforma de un clúster local (kind) a EKS aparecieron cuatro
diferencias concretas, y cada una obligó a un cambio real en el chart:

**Origen de las imágenes.** En kind bastaba con `kind load docker-image`, que
copia la imagen del Docker local al nodo. Un clúster administrado corre sobre
máquinas EC2 que no tienen acceso a ese Docker, así que las siete imágenes
tuvieron que publicarse en Amazon ECR y descargarse por red.

**Almacenamiento.** kind provee una StorageClass `standard` con el provisionador
`rancher.io/local-path`, que no es más que un directorio del contenedor que hace
de nodo: si el nodo desaparece, el dato desaparece. En EKS los volúmenes son
discos EBS reales, independientes del nodo, creados bajo demanda por el driver
CSI. Un pod reprogramado en otra máquina vuelve a montar su mismo disco.

**Exposición.** En local, un Service de tipo LoadBalancer se queda en `<pending>`
para siempre porque no hay nada que lo resuelva; por eso la práctica anterior usó
un Ingress con el host ficticio `sa-p5.local` en `/etc/hosts`. En EKS el
cloud-controller-manager traduce ese mismo objeto en un balanceador real de AWS
con un nombre DNS público.

**Costo e identidad.** Un clúster local es gratuito y no tiene noción de
identidad. En EKS cada objeto cuesta dinero por hora y el acceso se gobierna con
IAM, que se integra con el RBAC de Kubernetes mediante OIDC.

La contrapartida es la pérdida de control: no hay acceso por SSH a los nodos
maestros, ni posibilidad de modificar banderas del API server, ni de elegir
libremente la versión de Kubernetes.

## 2. ¿Qué es un Service de tipo LoadBalancer y cómo lo implementa el proveedor de nube?

Es el tipo de Service que pide a la infraestructura subyacente un balanceador
externo con una dirección propia alcanzable desde fuera del clúster. Los otros
dos tipos no bastan: `ClusterIP` sólo es visible dentro del clúster, y `NodePort`
abre un puerto alto en cada nodo, obligando al cliente a conocer las IP de los
nodos y a que éstas no cambien.

El mecanismo tiene tres tiempos. Primero, `kubectl apply` crea el objeto en la
API de Kubernetes, que por sí solo no hace nada. Segundo, el
**cloud-controller-manager** —un componente que EKS ejecuta dentro del plano de
control con credenciales de AWS— observa la aparición de Services de este tipo y
llama a la API de Elastic Load Balancing para crear el balanceador, sus listeners
y su target group. Tercero, cuando AWS termina de aprovisionarlo, el controlador
escribe el nombre DNS resultante en `status.loadBalancer.ingress`, que es lo que
`kubectl get svc` muestra en la columna `EXTERNAL-IP`.

En esta práctica se solicitó explícitamente un **Network Load Balancer** en modo
`nlb-ip` mediante anotaciones:

```yaml
service.beta.kubernetes.io/aws-load-balancer-type: nlb-ip
service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
```

El modo `ip` registra como destinos las direcciones IP de los propios pods en
lugar de los NodePorts de los nodos, lo que elimina un salto de red y hace que el
balanceador reaccione a los cambios de réplicas del HPA sin reconfigurarse.

Conviene notar que el balanceador vive **fuera** del clúster y se factura aparte:
es un recurso de AWS que sobrevive a la destrucción del clúster si no se borra el
Service primero. Por eso el script de limpieza desinstala el release antes de
destruir el clúster.

## 3. ¿Qué es un registro de contenedores y por qué es necesario para desplegar en la nube?

Un registro es un servidor que almacena y distribuye imágenes de contenedor,
organizadas por repositorio y etiqueta, y que el kubelet consulta cada vez que
necesita arrancar un contenedor cuya imagen no tiene en caché local.

Es imprescindible en la nube por una razón de topología: el nodo que ejecuta el
pod es una máquina remota que no comparte el demonio de Docker de la estación de
trabajo. Cuando el scheduler asigna un pod a un nodo, el kubelet de ese nodo debe
poder obtener la imagen **por sí mismo**, y el único camino es una URL accesible
por red con credenciales válidas. Sin registro, el resultado es `ImagePullBackOff`.

En esta práctica se usó **Amazon ECR** por su integración con IAM: el rol del
grupo de nodos incluye `AmazonEC2ContainerRegistryReadOnly`, de modo que los
nodos se autentican solos y no hace falta crear un `imagePullSecret`.

Dos detalles que costaron trabajo real durante el despliegue:

- **La arquitectura importa.** Las imágenes se construyeron con
  `--platform linux/amd64` porque los nodos `t3.small` son x86_64; una imagen
  ARM fallaría con `exec format error` en tiempo de ejecución, no al descargarla.
- **Las etiquetas móviles no sirven.** En local `IfNotPresent` con un tag fijo
  era suficiente. En la nube se usa el SHA del commit como etiqueta y
  `pullPolicy: Always`, para que cada despliegue sea reproducible y se sepa
  exactamente qué código está corriendo.

## 4. ¿Qué componentes del clúster administra el proveedor y cuáles siguen siendo responsabilidad del estudiante?

La división sigue el modelo de responsabilidad compartida: AWS responde por la
seguridad **de** la nube, y el usuario por la seguridad **en** la nube.

**Administra AWS:** el API server, etcd (con sus respaldos y su cifrado), el
scheduler, el controller-manager y el cloud-controller-manager; el parcheo del
sistema operativo de las AMI optimizadas para EKS; la disponibilidad del plano de
control entre zonas; y el aprovisionamiento físico de balanceadores y volúmenes
EBS cuando un objeto de Kubernetes los solicita.

**Sigue siendo responsabilidad del estudiante:** todo lo que se despliega dentro.
En concreto, en esta práctica:

- Los manifiestos y el chart: réplicas, probes, límites de recursos, estrategia
  de actualización.
- La seguridad de las cargas: el `securityContext` restrictivo heredado de la
  P5 (`runAsNonRoot`, `readOnlyRootFilesystem`, `drop: ALL`).
- El aislamiento de red interno: las NetworkPolicies que deniegan por defecto.
  EKS no las aplica solo; requieren un CNI que las soporte.
- **La gestión de las credenciales.** Ninguna contraseña está en el repositorio:
  se generan al desplegar y viven en un Secret del clúster.
- **El costo.** AWS factura lo que se deja encendido, sin avisar.
- Las actualizaciones de versión: AWS avisa del fin de soporte, pero es el
  usuario quien decide y ejecuta la actualización.

Un matiz que suele pasarse por alto: aunque AWS administra el plano de control,
la **configuración** del acceso a ese plano (quién puede llamarlo, con qué rol
IAM, mapeado a qué grupo de RBAC) es responsabilidad del usuario. Un clúster
administrado mal configurado sigue siendo un clúster inseguro.

## 5. ¿Qué costos genera el despliegue realizado y cómo podrían reducirse?

Los costos se detallan con cifras verificadas en [costos.md](costos.md). En
resumen, el despliegue tiene cuatro fuentes de gasto: el plano de control de EKS
(tarifa fija por hora, sin capa gratuita), los nodos EC2, el Network Load
Balancer y los volúmenes EBS. Predominan el plano de control y los nodos.

Las vías de reducción, de mayor a menor impacto:

**Apagar lo que no se usa.** Es la de mayor efecto y la más ignorada: un clúster
olvidado un mes cuesta cerca de diez veces lo que costó la práctica. Por eso el
entregable incluye `99-eliminar.sh`.

**Instancias Spot.** Para una carga de laboratorio que tolera interrupciones,
reducen el costo de los nodos en torno a un 70 %.

**Dimensionar al mínimo.** Se eligieron `t3.small` (2 vCPU, 2 GiB) por ser el
menor tamaño donde la plataforma completa cabe con holgura.

**Un solo balanceador.** Se expone únicamente el API Gateway. Poner un
LoadBalancer por microservicio multiplicaría por cinco ese renglón; un Ingress
Controller es la alternativa cuando hacen falta varias rutas públicas.

**Vigilar el tráfico de salida.** No es significativo aquí, pero el tráfico entre
zonas de disponibilidad se factura, y una aplicación descuidada puede generarlo
sin que se note.
