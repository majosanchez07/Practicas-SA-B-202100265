# Objetivos de recuperación declarados

Práctica 9 · María José Tebalán Sánchez · 202100265

Estos objetivos se declararon **antes** de ejecutar cualquier prueba. La fecha
del commit que agregó este archivo lo demuestra. No se ajustan después: los
valores medidos se comparan con estos en el [informe de la prueba de DR](informe-prueba-dr.md).

| Objetivo | Valor declarado | Justificación |
|---|---|---|
| **RTO** (tiempo hasta volver a operar tras perder el clúster completo) | **45 minutos** | Crear AKS y sus nodos tarda entre 6 y 10 minutos; en EKS (P6 y P8) eran 15 a 20, y la cifra se mantiene como techo conservador. La plataforma (Helm y Terraform) agrega unos 5 minutos, la restauración de volúmenes 2 y la sincronización de ArgoCD entre 5 y 10. Queda un margen de unos 10 minutos para reintentos y para detectar el problema. Bajar de ahí requeriría un clúster en espera (*pilot light*), que duplica el costo de una cuenta con créditos limitados. |
| **RPO** (datos que se aceptan perder) | **30 minutos** | El schedule `respaldo-sa-p9` corre cada 30 minutos (`*/30 * * * *`), así que en el peor caso se pierde lo escrito desde el último respaldo. Para un sistema académico de biblioteca, 30 minutos de préstamos se pueden volver a capturar a mano. Respaldar cada 5 minutos multiplicaría por seis los snapshots de disco sin un beneficio proporcional. |
| **Pérdida de nodo** | **0 peticiones fallidas** en los servicios sin estado | Cada servicio tiene al menos 2 réplicas, anti-afinidad por nodo y un PodDisruptionBudget. PostgreSQL y RabbitMQ tienen una sola réplica y se declaran fuera de este objetivo (punto único de fallo conocido). |
| **Retención** | **7 días** (`ttl: 168h`) | Cubre un fin de semana largo más el tiempo de detectar un daño silencioso en los datos (clase del 17/09: MTTD). |

## Clasificación del estado (efímero / persistente / irrecuperable)

| Clase | Qué es en este sistema | Cómo se recupera |
|---|---|---|
| Efímero | Pods, ReplicaSets, Services, HPA, Rollouts, caché de ArgoCD, nodos | Se reconstruye solo desde Git (ArgoCD) y desde Terraform |
| Persistente | Volumen de PostgreSQL (`biblioteca`), volumen de RabbitMQ, estado de Terraform | Velero (snapshots de disco + pg_dump) y Azure Blob versionado para el estado |
| Irrecuperable | Llave privada de Sealed Secrets | No se puede regenerar: vive en Azure Key Vault, fuera del clúster |
