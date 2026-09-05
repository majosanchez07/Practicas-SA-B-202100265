# Costos del despliegue y procedimiento de eliminación

> Precios de la región `us-east-2`, consultados en septiembre de 2026 en la
> documentación oficial de AWS. Los precios varían por región y con el tiempo:
> la referencia vigente siempre es la
> [calculadora oficial](https://calculator.aws/).

## 1. Fuentes de costo

El despliegue enciende cuatro recursos facturables. Ninguno está cubierto por la
capa gratuita de AWS, con la excepción parcial de EBS.

Las cantidades de esta tabla no son estimaciones: se consultaron con
`aws ec2 describe-volumes` y `aws ec2 describe-instances` sobre el despliegue
real (ver [evidencias](evidencias/01-evidencias.md)).

| Recurso | Cantidad real | Precio unitario | Costo por hora |
|---|---|---|---|
| Plano de control de EKS | 1 clúster | $0.10 / hora | $0.1000 |
| Nodos EC2 `t3.small` | 2 nodos | $0.0208 / hora | $0.0416 |
| Network Load Balancer | 1 (`nlb`) | ~$0.0225 / hora | $0.0225 |
| Volúmenes EBS `gp3` de datos | 16 GiB (2 × 8) | $0.08 / GiB-mes | $0.0018 |
| Discos raíz de los nodos | 40 GiB (2 × 20) | $0.08 / GiB-mes | $0.0044 |
| **Total** | | | **≈ $0.17 / hora** |

El plano de control es el **59 %** del costo horario y es el único renglón que
no se puede reducir dimensionando: cuesta lo mismo con carga o sin ella.

Al total hay que sumarle dos renglones menores que dependen del uso y no del
tiempo encendido: las **LCU del balanceador** (unidades de capacidad, que para el
tráfico de una demostración se quedan en el mínimo facturable) y el
**almacenamiento en ECR**, a $0.10 por GiB-mes; las siete imágenes de esta
plataforma ocupan bastante menos de 1 GiB en total.

## 2. Costo real de esta práctica

El clúster `sa-p6-202100265` se creó el **4 de septiembre de 2026 a las 20:47**
(hora de Guatemala) y se eliminó el mismo día tras recolectar las evidencias,
con un tiempo total encendido de aproximadamente **2 horas**:

```
0.17 USD/hora × 2 horas ≈ 0.34 USD
```

A eso se suma el almacenamiento de las 7 imágenes en ECR, muy por debajo de
1 GiB y por tanto inferior a $0.01 en el periodo. **El costo total de la
práctica fue inferior a $0.40**, cubierto por los créditos de estudiante. La cifra importante no es ésa, sino la que se habría generado
al olvidar el clúster encendido:

| Tiempo encendido | Costo acumulado |
|---|---|
| 2 horas (esta práctica) | ~$0.34 |
| 4 horas | ~$0.68 |
| 1 día | ~$4.08 |
| 1 semana | ~$28.56 |
| **1 mes** | **~$122.40** |

Un mes de olvido consume cerca de la mitad de los créditos de estudiante
habituales. **Ésta es la razón por la que el paso de eliminación no es opcional.**

## 3. Cómo reducir el costo

Ordenadas por impacto:

**Apagar el clúster al terminar (100 % de ahorro).** El plano de control cobra
por hora exista o no carga sobre él; es el 59 % del costo horario y no tiene
modo suspendido. La única forma de dejar de pagarlo es destruir el clúster.

**Instancias Spot (~70 % sobre los nodos).** Un `t3.small` Spot ronda los
$0.006/hora. Para una carga de laboratorio, que AWS reclame la instancia con dos
minutos de aviso es tolerable. Se activa en `01-crear-cluster.sh` añadiendo
`--spot` al grupo de nodos.

**Un solo balanceador.** El chart expone únicamente el API Gateway. Un
LoadBalancer por microservicio sumaría cinco veces $0.0225/hora sin beneficio.

**No sobredimensionar el disco.** Los 8 GiB por volumen son el mínimo cómodo
para PostgreSQL y RabbitMQ en esta plataforma.

**Presupuesto con alerta.** Un AWS Budget avisa por correo al superar un umbral;
es la red de seguridad contra el olvido:

```bash
aws budgets create-budget --account-id "$ACCOUNT_ID" \
  --budget '{"BudgetName":"sa-p6","BudgetLimit":{"Amount":"10","Unit":"USD"},
             "TimeUnit":"MONTHLY","BudgetType":"COST"}'
```

## 4. Procedimiento de eliminación

Automatizado en [`scripts/99-eliminar.sh`](../scripts/99-eliminar.sh):

```bash
cd P6 && ./scripts/99-eliminar.sh
```

**El orden no es arbitrario.** El script sigue estos cuatro pasos por una razón
concreta:

1. **`helm uninstall` primero.** Al borrar el Service de tipo LoadBalancer, el
   cloud-controller-manager pide a AWS que retire el balanceador. Si se destruye
   el clúster antes, ese controlador desaparece sin haber limpiado: el NLB y sus
   security groups quedan huérfanos, **siguen facturándose**, y además impiden
   borrar la VPC porque quedan interfaces de red asociadas.

2. **Esperar a que el balanceador desaparezca** antes de continuar.

3. **Borrar los PVC explícitamente.** Helm no elimina los
   PersistentVolumeClaim de un StatefulSet: los conserva a propósito para no
   destruir datos. Los volúmenes EBS asociados seguirían cobrándose.

4. **`eksctl delete cluster`,** que destruye el grupo de nodos, el plano de
   control y la VPC con todas sus subredes y tablas de rutas.

Finalmente se borran los repositorios de ECR.

### Verificación

El script termina comprobando que no queda nada. Conviene confirmarlo también en
la consola, ya que un recurso olvidado sigue costando:

```bash
eksctl get cluster --region us-east-2
aws elbv2 describe-load-balancers --region us-east-2 --query 'LoadBalancers[].LoadBalancerName'
aws ec2 describe-volumes --region us-east-2 --filters Name=status,Values=available
aws ecr describe-repositories --region us-east-2 --query 'repositories[].repositoryName'
```

Los cuatro deben salir vacíos. El tercero es el que más se olvida: un volumen en
estado `available` es un disco sin usar que se sigue facturando.
