# Informe de la prueba de recuperación ante desastres

Práctica 9 · María José Tebalán Sánchez · 202100265 · Prueba ejecutada el 24/09/2026 (horas en UTC)

## 1. Objetivos declarados

Se declararon antes de cualquier prueba, en [rto-rpo-declarados.md](rto-rpo-declarados.md) (commit `b4f28e1`):

- **RTO: 45 min.** Crear el clúster tarda entre 6 y 10 min en AKS (15–20 en EKS, que se conservó como techo). La plataforma agrega unos 5 min, la restauración de volúmenes 2 y la sincronización de ArgoCD entre 5 y 10, con un margen para detectar el problema. Bajar de ahí exigiría un clúster en espera (*pilot light*), que duplica el costo.
- **RPO: 30 min.** Es el intervalo del schedule `respaldo-sa-p9` (`*/30 * * * *`, retención de 7 días). Para una biblioteca académica, 30 minutos de préstamos se pueden volver a capturar.
- **Pérdida de nodo: 0 peticiones fallidas** en los servicios sin estado. PostgreSQL y RabbitMQ (réplica única) quedaron declarados fuera de este objetivo.

## 2. Escenario ejecutado

Se hicieron tres pruebas, en este orden:

1. **Pérdida de datos** (22:25–22:28), con [`prueba-restauracion-datos.sh`](../scripts/prueba-restauracion-datos.sh):
   1. Se insertó la marca A.
   2. Se tomó un respaldo desde el schedule, con `pg_dump` como hook previo y 2 snapshots de disco.
   3. Se insertó la marca B.
   4. Se ejecutó `DELETE` de todas las filas: `cronjobs.ejecuciones` y `dr.verificacion` quedaron en 0.
   5. Se eliminó el volumen `data-sa-platform-postgresql-0`.
   6. Se restauró el volumen desde el snapshot.
2. **Pérdida de nodo** (22:48–22:50): drenaje de `aks-workers-…vmss000000` mientras un pod sonda consultaba el API Gateway cada segundo desde el otro nodo.
3. **Pérdida total** (desde las 22:51):
   1. [`desastre.sh`](../scripts/desastre.sh) ejecutó `terraform destroy` de la capa `cluster`. Se destruyeron el grupo `rg-sa-p9-202100265` (AKS, los 2 nodos, los discos en uso y la red) y la identidad de Velero.
   2. Solo sobrevivió el grupo `rg-sa-p9-base-202100265`: estado de Terraform, respaldos, snapshots y Key Vault.
   3. Después, [`bootstrap.sh`](../scripts/bootstrap.sh) lo reconstruyó todo, sin intervención.

## 3. Tiempos medidos

Registros:
- [`desastre-20260924T225105Z.log`](evidencias/reconstruccion/desastre-20260924T225105Z.log)
- [`registro-20260924T225712Z.log`](evidencias/reconstruccion/registro-20260924T225712Z.log)

| Marca | Hora UTC | Transcurrido desde la destrucción |
|---|---|---|
| Clúster destruido (fin de `terraform destroy`) | 22:56:56 | 0:00 |
| Inicio de `bootstrap.sh` | 22:57:13 | 0:17 |
| Paso 0 · estado, respaldos y llave externos disponibles | 22:57:17 | 0:21 |
| Paso 1 · AKS y 2 nodos listos | 23:04:14 | 7:18 |
| Paso 2 · Sealed Secrets con la llave de Key Vault, Velero y ArgoCD | 23:07:37 | 10:41 |
| Paso 3 · 2 PVC restaurados del respaldo `respaldo-sa-p9-20260924223043` | 23:07:48 | 10:52 |
| Paso 4 · aplicación raíz `raiz-sa-p9` creada | 23:09:03 | 12:07 |
| Paso 5 · controladores, secretos, políticas y schedule Synced/Healthy | 23:10:28 | 13:32 |
| Paso 5 · `sa-platform` Synced/Healthy | 23:12:10 | 15:14 |
| Verificaciones: secreto descifrado, 3 políticas, schedule `Enabled`, datos presentes | 23:12:16 | **15:20** |

**RTO real: 15 min 20 s**, desde la destrucción confirmada hasta que `sa-platform` quedó Synced/Healthy con los datos verificados. Si se cuenta desde el inicio del desastre (22:51:08) y no desde la destrucción confirmada, son 21 min 8 s. Las dos cifras quedan por debajo de los 45 min declarados.

La creación del clúster (7 min) fue el tramo más largo, como se previó. El resto (8 min) es plataforma más GitOps. El `bootstrap.sh` completo tardó 15 min 4 s, sin ningún paso manual.

Otros tiempos medidos:
- **Restauración de solo datos:** 60 s entre el `velero restore` y la base en línea.
- **Pérdida de nodo:** el drenaje duró 1 min 22 s. La sonda obtuvo **121 de 121 peticiones con HTTP 200 (100 %)** ([`drenaje-20260924T224739Z.log`](evidencias/perdida-nodo/drenaje-20260924T224739Z.log), [`sondeo-20260924T224739Z.log`](evidencias/perdida-nodo/sondeo-20260924T224739Z.log)).

## 4. Pérdida medida

- **Prueba de datos** ([`prueba-datos-20260924T222531Z.log`](evidencias/restauracion/prueba-datos-20260924T222531Z.log)):
  - Se recuperó la marca A y 26 filas reales del cronjob. La última restaurada es de las 22:26:02.
  - La marca B, escrita 20 s después de iniciar el respaldo, **se perdió**, como se esperaba.
  - El RPO medido es de **20 s**, pero solo porque el respaldo se lanzó a mano justo antes del desastre. No es representativo.
- **Pérdida total** (el valor honesto):
  - El último respaldo programado terminó a las 22:30:53. Antes de destruir había 31 filas, la última de las 22:50:04.
  - Tras la reconstrucción volvieron **26 filas, la última de las 22:26:02**: el contenido real del respaldo de las 22:30:43.
  - La última escritura fue a las 22:50:04 y la destrucción empezó a las 22:51:08, así que se perdieron **5 filas**, las escritas entre las 22:30:43 y las 22:50:04.
  - **RPO real: 20 min 25 s** (22:51:08 − 22:30:43), dentro de los 30 min declarados.
  - También volvieron las marcas `antes-del-respaldo-*` de `dr.verificacion`: la restauración trajo contenido real, no un volumen vacío.
  - Lo no recuperado son las ejecuciones del cronjob entre el respaldo de las 22:30 y el desastre. Se perdieron porque se escribieron después del último respaldo; ningún mecanismo las copia fuera del clúster antes del siguiente ciclo.
- **Peor caso con el diseño actual:** 30 min más la duración del respaldo, es decir, el RPO declarado.

## 5. Puntos únicos de fallo detectados

1. **Capacidad sin N+1.** El primer drenaje ([`intento1-fallido-…log`](evidencias/perdida-nodo/intento1-fallido-drenaje-20260924T222856Z.log)) dejó pods en `Pending`: cada nodo tiene 1,9 CPU asignables y la suma de *requests* no cabía en uno solo. Se corrigió ajustando los *requests* al consumo medido (3–4m reales por servicio → 25m; Kyverno de 400m a 100m). Solo después el segundo drenaje dio 100 %.
2. **PostgreSQL y RabbitMQ con réplica única.** El primer drenaje cayó en su nodo: la base quedó fuera de servicio y los servicios que dependen de ella entraron en `CrashLoopBackOff`. Sin réplica de lectura, perder ese nodo interrumpe todo lo que escribe.
3. **ArgoCD podaba los respaldos.** Los `Backup` creados desde el schedule heredaban la etiqueta de seguimiento de ArgoCD. Con `prune` activo, ArgoCD los borraba al nacer ("not found"). Sin la prueba, el schedule habría reportado respaldos que nunca existieron. Es el mismo modo de fallo silencioso de GitLab en 2017, visto en clase. Se corrigió con el seguimiento por anotación.
4. **Región y cuota únicas.** El sistema depende de `centralus` y de su cuota de 4 vCPU. `Standard_D2s_v5` fue rechazado por la suscripción en el primer intento. Si la región cae, los snapshots (también en `centralus`) no sirven para otra región.
5. **El grupo base es la raíz de todo.** Un borrado de `rg-sa-p9-base-202100265`, o credenciales comprometidas con permiso sobre él, elimina estado, respaldos y llave a la vez (el caso de Code Spaces).

## 6. Brecha y plan

| Objetivo | Declarado | Medido | Brecha |
|---|---|---|---|
| RTO | 45 min | 15 min 20 s | −29 min 40 s: se cumplió con holgura. El objetivo se había dimensionado con los tiempos de EKS (15–20 min por clúster); AKS tardó 7 |
| RPO | 30 min | 20 min 25 s (peor caso diseñado: 30 min) | Dentro del objetivo |
| Pérdida de nodo | 0 fallos | 121/121 OK en el 2.º intento; el 1.º falló por capacidad | Cumplido después de corregir |

Qué haría para cerrar las brechas:
1. **Réplica de PostgreSQL** (`architecture: replication`) o un servicio administrado (Azure Database for PostgreSQL) con PITR: bajaría el RPO a segundos y quitaría el punto único de fallo.
2. **Respaldos inmutables y en otra región:** bloqueo de inmutabilidad en el contenedor `velero`, copia GRS o snapshots copiados a otra región, y credenciales de borrado separadas de las de operación.
3. **Alerta de respaldo fallido:** métrica `velero_backup_failure_total` con alerta. Sin ella, el fallo del punto 3 de la sección 5 habría pasado inadvertido (MTTD).
4. **Autoescalado de nodos** (`min 2, max 3`) cuando la cuota lo permita, para absorber un drenaje sin depender de *requests* ajustados al límite.
5. **Ensayar la prueba de forma periódica:** "un respaldo que nunca se ha restaurado es una suposición". Programar `prueba-restauracion-datos.sh` una vez por semana.
