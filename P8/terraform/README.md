# Infraestructura como código — Práctica 8

Toda la infraestructura de esta práctica se crea con Terraform. No hay ningún
recurso creado a mano: el enunciado lo prohíbe expresamente y el estado real
del clúster debe poder derivarse de este directorio.

## Las dos capas

```
terraform/
├── cluster/     Capa 1 — AWS: VPC, EKS, nodos, addons, IRSA
└── platform/    Capa 2 — Kubernetes: namespaces, cuotas, límites, RBAC
```

Están separadas por una razón técnica, no organizativa. Terraform resuelve los
*providers* al comenzar el plan, antes de crear nada. Si los objetos de
Kubernetes vivieran en el mismo estado que el clúster, el provider `kubernetes`
tendría que apuntar a un endpoint que todavía no existe durante el primer
`apply`, y el plan fallaría. Con la separación, cada capa tiene un proveedor
cuyos datos ya están disponibles cuando se la ejecuta.

## Orden de ejecución

La capa 2 no funciona si la capa 1 no se ha aplicado antes.

```bash
# --- Capa 1: el clúster (15-20 min, el plano de control es lo más lento) ---
cd cluster
terraform init
terraform plan -out=plan.tfplan          # evidencia del plan
terraform apply plan.tfplan

# Apuntar kubectl al clúster recién creado
eval "$(terraform output -raw comando_kubeconfig)"
kubectl get nodes

# --- Capa 2: namespaces, cuotas, límites y RBAC ---
cd ../platform
terraform init
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
```

## Verificación

Que la infraestructura la creó Terraform y no una serie de `kubectl create` se
comprueba con la etiqueta que todos los objetos llevan:

```bash
kubectl get namespaces -l gestionado-por=terraform
kubectl describe resourcequota -n sa-p8
kubectl describe limitrange    -n sa-p8
kubectl get roles,rolebindings -n sa-p8
```

Los mismos comandos se emiten como salida de `terraform output
comandos_verificacion`, para que la evidencia del `apply` incluya la forma de
comprobarla de manera independiente.

## Qué crea cada capa

### Capa 1 — `cluster/`

| Recurso | Detalle |
|---|---|
| VPC | `10.0.0.0/16`, 2 AZ, subredes públicas y privadas |
| NAT Gateway | Uno solo, compartido (ahorra ~32 USD/mes frente a uno por AZ) |
| EKS | Plano de control 1.31, endpoint público |
| Nodos | 2 × `t3.medium`, escalables hasta 4 |
| Addons | CoreDNS, kube-proxy, VPC-CNI, EBS CSI |
| IRSA | Rol IAM para el driver de EBS |

`t3.medium` en lugar del `t3.small` de la Práctica 6: la P8 añade ArgoCD, Argo
Rollouts, Kyverno y Sealed Secrets sobre la misma plataforma, y con 2 GiB por
nodo esos componentes compiten por memoria con los de la aplicación.

### Capa 2 — `platform/`

| Recurso | Detalle |
|---|---|
| Namespaces | `sa-p8`, `argocd`, `kyverno`, `sealed-secrets` |
| ResourceQuota | Techo total del namespace de la aplicación |
| LimitRange | Valores por defecto y máximos por contenedor |
| Role + RoleBinding | Identidad de ArgoCD, acotada a `sa-p8` |
| Role | `auditor-solo-lectura`, sin acceso a secretos |

## Una decisión que conviene entender

El chart `sa-platform` de las Prácticas 5 a 7 ya creaba el namespace, la
ResourceQuota, el LimitRange y el RBAC. **Esa responsabilidad se traslada a
Terraform y se apaga en el chart.**

No es una duplicación inocua. Si Terraform y ArgoCD declararan ambos el mismo
ResourceQuota, cada uno lo reclamaría como propio y la aplicación de ArgoCD
oscilaría entre `Synced` y `OutOfSync` sin estabilizarse nunca. Como la rúbrica
exige que esté `Synced` y `Healthy` al momento de calificar, cada objeto tiene
un único dueño:

| Dueño | Objetos |
|---|---|
| Terraform | Namespace, ResourceQuota, LimitRange, RBAC |
| ArgoCD | Rollout, Service, ConfigMap, HPA, Ingress… |

## Costo

Según el desglose medido en la [Práctica 6](../../P6/docs/costos.md), con el
cambio a `t3.medium` y el NAT Gateway que la P6 no tenía:

| Recurso | Costo/hora |
|---|---|
| Plano de control EKS | $0.1000 |
| 2 × `t3.medium` | $0.0832 |
| NAT Gateway | $0.0450 |
| Balanceador | $0.0225 |
| EBS | ~$0.0062 |
| **Total** | **≈ $0.26/hora** |

Son unos **$6.20 al día** si se deja encendido. La práctica se califica el 19
de septiembre con ArgoCD en estado `Synced` y `Healthy`, lo que **no** obliga a
dejarlo corriendo: se destruye tras recolectar la evidencia y se vuelve a crear
el día de la calificación.

```bash
cd platform && terraform destroy
cd ../cluster && terraform destroy
```

El `destroy` de la capa 1 elimina la VPC completa, de modo que no quedan
recursos facturables olvidados. Conviene comprobarlo después:

```bash
aws ec2 describe-instances --region us-east-2 \
  --filters "Name=tag:Practica,Values=P8" \
  --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId'
```

## Archivos que no se versionan

El estado de Terraform contiene identificadores de la cuenta de AWS y valores
de los recursos gestionados. `.gitignore` excluye `terraform.tfstate`,
`.terraform/` y cualquier `*.tfvars`.
