# Índice de capturas de pantalla

Práctica 9 · María José Tebalán Sánchez · 202100265

Todas las capturas se tomaron el 24–25 de septiembre de 2026 (UTC) sobre el
entorno real en Azure: AKS `aks-sa-p9-202100265`, región `centralus`. Cada
una es una ventana de terminal real, con los comandos escritos tal como se
ejecutaron y su salida sin editar. La primera línea de cada captura es
`date -u`, que fija el momento de la ejecución.

---

## Infraestructura y estado remoto

| Captura | Qué muestra |
|---|---|
| [01-cluster-aks-nodos.png](01-cluster-aks-nodos.png) | Contexto `aks-sa-p9-202100265`, los 2 nodos `Ready`, el clúster en `centralus` con workload identity, y los grupos `rg-sa-p9-*` |
| [02-estado-remoto-terraform.png](02-estado-remoto-terraform.png) | Lo que sobrevive al desastre (grupo base: 2 cuentas de almacenamiento y el Key Vault), el bloque `backend "azurerm"`, **0 archivos tfstate en el repositorio** y los dos estados guardados en Azure Blob |
| [03-bloqueo-estado-terraform.png](03-bloqueo-estado-terraform.png) | **Bloqueo del estado:** con un `plan` en curso el blob queda `locked / leased`, un segundo `plan` es rechazado con *"state blob is already locked"* y al terminar vuelve a `unlocked` |

## GitOps: app-of-apps

| Captura | Qué muestra |
|---|---|
| [04-argocd-app-of-apps.png](04-argocd-app-of-apps.png) | Las 7 aplicaciones `Synced/Healthy`; la raíz `raiz-sa-p9` apunta a `apps/` del repositorio GitOps; sus 6 hijas y la ola de sincronización de cada una |
| [05-pods-y-volumenes.png](05-pods-y-volumenes.png) | Las cargas de trabajo de `sa-p8` repartidas en los dos nodos y los volúmenes persistentes de PostgreSQL y RabbitMQ (`managed-csi`) |
| [25-argocd-ui-aplicaciones.png](25-argocd-ui-aplicaciones.png) | Interfaz web de ArgoCD: las 7 aplicaciones del clúster reconstruido |
| [26-argocd-ui-arbol-raiz.png](26-argocd-ui-arbol-raiz.png) | Interfaz web: `raiz-sa-p9` Healthy / Synced / Sync OK contra `main` del repositorio GitOps, con sus 6 aplicaciones hijas |
| [26b-argocd-ui-raiz-hijas.png](26b-argocd-ui-raiz-hijas.png) | Interfaz web, vista de lista de la raíz: las 6 hijas `Synced` y su **orden de sincronización** (olas 0 → 1 → 3) |
| [27-argocd-ui-sa-platform.png](27-argocd-ui-sa-platform.png) | Interfaz web: árbol de recursos de `sa-platform` (Rollout, StatefulSets, Services, PDB) tras la reconstrucción |

## Respaldos con Velero

| Captura | Qué muestra |
|---|---|
| [06-velero-configuracion.png](06-velero-configuracion.png) | Ubicación de respaldos `Available` en Azure Blob y de snapshots; schedule `*/30 * * * *` con retención `168h`, namespace `sa-p8` y snapshots de volúmenes; identidad de workload del ServiceAccount; **hook `pg_dump`** declarado en el pod de PostgreSQL |
| [07-velero-respaldos.png](07-velero-respaldos.png) | Respaldos `Completed` (programados y de prueba) y el detalle de uno programado |
| [08-respaldos-fuera-del-cluster.png](08-respaldos-fuera-del-cluster.png) | Los respaldos en la cuenta `sap9velero202100265` y los snapshots de disco en el grupo base, **fuera del clúster** |

## Continuidad de los secretos

| Captura | Qué muestra |
|---|---|
| [09-secretos-key-vault.png](09-secretos-key-vault.png) | La llave en Key Vault; el controlador la registra (`registered private key … sealed-secrets-key-respaldada`); **huella SHA-256 idéntica** entre el certificado del repositorio y la llave del clúster; los SealedSecret y sus Secret descifrados; el archivo cifrado del repositorio (ilegible) |

## Resiliencia ante pérdida de nodo

| Captura | Qué muestra |
|---|---|
| [10-pdb-antiafinidad-probes.png](10-pdb-antiafinidad-probes.png) | PodDisruptionBudget por servicio, anti-afinidad por `kubernetes.io/hostname` en cada carga, reparto de réplicas entre nodos y readiness probe del gateway |
| [16-perdida-nodo-1-drenaje-en-curso.png](16-perdida-nodo-1-drenaje-en-curso.png) | Drenaje en curso: los PDB frenan el desalojo (*"Cannot evict pod as it would violate the pod's disruption budget"*) hasta que haya reemplazos listos |
| [17-perdida-nodo-2-resultado.png](17-perdida-nodo-2-resultado.png) | Resultado: **125 de 125 peticiones con HTTP 200 (100 %)** durante el drenaje, y las últimas respuestas de la sonda |

## Restauración de datos verificada (en vivo)

| Captura | Qué muestra |
|---|---|
| [12-restauracion-1-marcas-y-respaldo.png](12-restauracion-1-marcas-y-respaldo.png) | Marca A insertada; filas reales del cronjob; respaldo `Completed`; volcado `biblioteca.sql` del hook dentro del volumen; marca B insertada **después** del respaldo |
| [13-restauracion-2-borrado-y-desastre.png](13-restauracion-2-borrado-y-desastre.png) | Desastre de datos: `DELETE` y tablas en **0 filas**; sincronización automática pausada; base detenida y **volumen eliminado** |
| [14-restauracion-3-restauracion.png](14-restauracion-3-restauracion.png) | `velero restore` `Completed`; el volumen vuelve `Bound` desde el snapshot; la base en línea; las 7 aplicaciones de nuevo `Synced/Healthy` |
| [15-restauracion-4-verificacion-rpo.png](15-restauracion-4-verificacion-rpo.png) | **Verificación del contenido:** marca A recuperada, marca B perdida, filas reales de vuelta, y el cálculo del RPO |

## Reconstrucción completa cronometrada (en vivo)

| Captura | Qué muestra |
|---|---|
| [18-dr-1-estado-previo.png](18-dr-1-estado-previo.png) | Antes del desastre: aplicaciones sincronizadas, respaldos existentes, datos y grupos de recursos |
| [19-dr-2-destruccion.png](19-dr-2-destruccion.png) | `desastre.sh`: `terraform destroy` completo, la marca de tiempo desde la que corre el RTO; solo queda el grupo base y `kubectl` ya no alcanza el clúster |
| [20-dr-3-bootstrap-restauracion.png](20-dr-3-bootstrap-restauracion.png) | `bootstrap.sh`, el punto de entrada único: clúster nuevo, llave de Key Vault, Velero y ArgoCD instalados, volúmenes restaurados del último respaldo |
| [21-dr-4-bootstrap-fin.png](21-dr-4-bootstrap-fin.png) | Todas las aplicaciones `Synced/Healthy`, verificaciones (secreto descifrado, datos presentes, políticas, schedule) y **duración total** |
| [24-dr-5-sistema-recuperado.png](24-dr-5-sistema-recuperado.png) | Después de la reconstrucción: datos y marcas presentes, secretos descifrados, respaldos visibles desde el clúster nuevo |

## Conservación del flujo de la Práctica 8

| Captura | Qué muestra |
|---|---|
| [11-flujo-p8-politicas-rollout.png](11-flujo-p8-politicas-rollout.png) | Las 3 políticas de Kyverno activas; un pod que las viola es **rechazado**; el Rollout canary del API Gateway sano |
