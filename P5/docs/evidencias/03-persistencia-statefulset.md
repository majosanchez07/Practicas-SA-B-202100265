# Evidencia — Persistencia: los datos sobreviven al borrado del pod

La base de datos se despliega como **StatefulSet** con su **PersistentVolumeClaim**
y su **headless service** asociado:

```
$ kubectl get statefulset,pvc,svc -n sa-p5 | grep postgres
statefulset.apps/sa-platform-postgresql   1/1
persistentvolumeclaim/data-sa-platform-postgresql-0   Bound   pvc-fcc3c1d7-...   1Gi   RWO   standard
service/sa-platform-postgresql      ClusterIP   10.96.190.116   5432/TCP
service/sa-platform-postgresql-hl   ClusterIP   None            5432/TCP     <- headless
```

## 1. Estado inicial

```
            tabla            | count
-----------------------------+-------
 cronjobs.ejecuciones        |    13
 loans.loans                 |     1
 notifications.notifications |     1
 notifications.resumenes     |     3
```

## 2. Marcador insertado antes del borrado

```sql
INSERT INTO cronjobs.ejecuciones (carne, ejecutado_en, fecha_texto, origen)
VALUES ('202100265', now(), 'MARCADOR-PERSISTENCIA-PRE-BORRADO', 'prueba-persistencia');
```

```
 id |            fecha_texto
----+-----------------------------------
 14 | MARCADOR-PERSISTENCIA-PRE-BORRADO
```

Identidad del pod y del volumen antes de la prueba:

```
PVC: data-sa-platform-postgresql-0  volumen: pvc-fcc3c1d7-7d80-4994-84c4-79a74aaedafe
pod uid: 22ef9833-3b77-4eaf-b00f-4d958336c180  inicio: 2026-08-27T16:49:00Z
```

## 3. Borrado del pod

```bash
kubectl delete pod sa-platform-postgresql-0 -n sa-p5
```

```
pod "sa-platform-postgresql-0" deleted from sa-p5 namespace
```

El StatefulSet lo recrea de inmediato:

```
NAME                       READY   STATUS              RESTARTS   AGE
sa-platform-postgresql-0   0/1     ContainerCreating   0          0s
```

## 4. Pod nuevo, mismo volumen

```
pod uid: 98ded22e-1a7f-4979-9866-e15fc854b236  inicio: 2026-08-27T17:16:14Z
PVC: data-sa-platform-postgresql-0  volumen: pvc-fcc3c1d7-7d80-4994-84c4-79a74aaedafe
```

El **uid del pod cambió** (`22ef9833…` → `98ded22e…`), confirmando que es una
instancia distinta, mientras que el **volumen es el mismo** (`pvc-fcc3c1d7…`).
Ahí está la diferencia entre un StatefulSet y un Deployment: la identidad del
pod y su volumen se mantienen ligados entre reinicios.

## 5. Los datos sobrevivieron

```
 id |   carne   |            fecha_texto            |       origen
----+-----------+-----------------------------------+---------------------
 14 | 202100265 | MARCADOR-PERSISTENCIA-PRE-BORRADO | prueba-persistencia
```

```
            tabla            | count
-----------------------------+-------
 cronjobs.ejecuciones        |    15     <- eran 14; el cronjob siguió corriendo
 loans.loans                 |     1
 notifications.notifications |     1
 notifications.resumenes     |     3
```

No se perdió ningún registro. El conteo de `cronjobs.ejecuciones` subió de 14 a
15 porque el Cronjob 1 continuó ejecutándose durante la prueba, lo que confirma
además que la base quedó plenamente operativa tras el reinicio.
