# Índice de evidencias

Práctica 8 — María José Tebalán Sánchez — 202100265

Toda la evidencia de este directorio se recogió sobre el entorno real
desplegado en la nube, no sobre simulaciones. Cada archivo lleva la fecha y la
hora de su captura.

---

> **Capturas de pantalla:** el índice visual está en
> [capturas/INDICE-CAPTURAS.md](capturas/INDICE-CAPTURAS.md) — 20 imágenes del
> sistema funcionando, con los comandos ejecutados en terminal.

---

## Requisitos para optar a la calificación

| Requisito | Evidencia | Estado |
|---|---|---|
| Aplicación sincronizada y sana | [argocd/estado.txt](argocd/estado.txt) · [capturas/04](capturas/04-argocd-synced-healthy.png) | **Synced / Healthy** |
| Sin despliegue directo | Job "1 - Verificar que no hay despliegue directo" en la ejecución del pipeline | Superado |
| Evidencia de reversión | [rollouts/reversion-automatica.txt](rollouts/reversion-automatica.txt) · [capturas/07](capturas/07-reversion-cronologia.png) | **Verificada** |
| Repositorios accesibles | Ambos repositorios son públicos | Comprobado |

---

## 1. Infraestructura declarada

| Archivo | Contenido |
|---|---|
| [terraform/plan-cluster.txt](terraform/plan-cluster.txt) | Plan de la capa de entorno: 62 recursos |
| [terraform/apply-cluster.txt](terraform/apply-cluster.txt) | Aplicación de la capa de entorno |
| [terraform/plan-platform.txt](terraform/plan-platform.txt) | Plan de espacios de trabajo, cuotas y permisos |
| [terraform/apply-platform.txt](terraform/apply-platform.txt) | Aplicación: 9 recursos |
| [terraform/namespaces.txt](terraform/namespaces.txt) | Los cuatro espacios, con la etiqueta que prueba su origen |
| [terraform/cuotas.txt](terraform/cuotas.txt) | Cuotas del espacio de la aplicación |
| [terraform/rbac.txt](terraform/rbac.txt) | Permisos declarados |

Que la infraestructura no se creó a mano se comprueba con:

```
kubectl get namespaces -l gestionado-por=terraform
```

Ningún espacio creado manualmente llevaría esa etiqueta.

---

## 2. Estado declarativo

| Archivo | Contenido |
|---|---|
| [argocd/estado.txt](argocd/estado.txt) | Aplicación sincronizada y sana, con su origen |
| [argocd/estado-sistema.txt](argocd/estado-sistema.txt) | Nodos y cargas de trabajo |
| [capturas/04-argocd-synced-healthy.png](capturas/04-argocd-synced-healthy.png) | Captura del estado |

---

## 3. Entrega progresiva

| Archivo | Contenido |
|---|---|
| [rollouts/promocion-exitosa.txt](rollouts/promocion-exitosa.txt) | Promoción completa: 6/6 pasos, estado sano |
| [rollouts/reversion-automatica.txt](rollouts/reversion-automatica.txt) | Reversión con su cronología |
| [capturas/07-reversion-cronologia.png](capturas/07-reversion-cronologia.png) | Captura de la reversión |

### El resultado que justifica el diseño

Durante la reversión, el análisis registró:

| Prueba | Resultado |
|---|---|
| Disponibilidad | Superada — el componente estaba vivo |
| Rendimiento | Superada — respondía rápido |
| **Funcionalidad** | **Fallida** — el servicio esencial devolvía error |

Dos de las tres pruebas dieron por buena una versión defectuosa. Un análisis
limitado a comprobar disponibilidad la habría promovido a la totalidad de los
usuarios.

**Tiempo de recuperación: 66 segundos. Tráfico afectado: 20% durante 24
segundos. Intervención humana: ninguna.**

---

## 4. Validación automatizada

| Archivo | Resultado |
|---|---|
| [pruebas/humo-cluster.txt](pruebas/humo-cluster.txt) | 6 de 6 comprobaciones |
| [pruebas/integracion-cluster.txt](pruebas/integracion-cluster.txt) | 9 de 9 comprobaciones |
| [carga/reporte-carga.txt](carga/reporte-carga.txt) | 612 peticiones, 0% error, p95 122 ms |
| [carga/reporte-carga.json](carga/reporte-carga.json) | Métricas completas |

La prueba de rendimiento valida empíricamente el umbral elegido: el percentil 95
medido fue de 122 ms, muy por debajo de los 500 ms fijados como criterio de
promoción. Esa holgura es la que evita reversiones por variabilidad del entorno.

---

## 5. Políticas de admisión

| Archivo | Contenido |
|---|---|
| [politicas/rechazo.txt](politicas/rechazo.txt) | Despliegue rechazado, con las reglas incumplidas |

Las tres políticas están activas en modo de rechazo. El manifiesto de prueba
incumple las tres a propósito y el objeto no llega a crearse.

---

## 6. Cadena de suministro

| Archivo | Contenido |
|---|---|
| [seguridad/verificacion-firma.txt](seguridad/verificacion-firma.txt) | Verificación de la firma del artefacto |
| [seguridad/imagen-base-vulnerable.txt](seguridad/imagen-base-vulnerable.txt) | Análisis de la imagen usada en la demostración de bloqueo |

La verificación confirma que el artefacto lo construyó el flujo de trabajo de
este repositorio, y no otro: la identidad registrada es
`.github/workflows/p8-gitops.yml@refs/tags/v1.0.1`.

### Vulnerabilidades encontradas durante el desarrollo

El análisis bloqueó la construcción tres veces, y cada caso requirió una
respuesta distinta:

| Vulnerabilidad | Origen | Respuesta |
|---|---|---|
| Denegación de servicio en la librería de archivos comprimidos | Gestor de paquetes de la imagen base | Excluida con justificación documentada |
| Tres vulnerabilidades en un paquete del sistema | Imagen base de los servicios en Python | Actualización de paquetes |
| Confusión de algoritmo en la librería de tokens | Dependencia declarada del servicio de autenticación | Actualización de versión |

El criterio: se excluye solo lo que no tiene corrección disponible **y** no es
explotable en este contexto. Cuando el parche existe, se aplica.

---

## 7. Gestión de credenciales

Las credenciales viven cifradas en el repositorio de declaración
(`platform/sealed-secrets/credenciales.yaml`). Ese archivo puede publicarse sin
riesgo: solo el controlador que lo cifró puede descifrarlo, con una clave que
nunca sale del entorno.

Comprobación de que no hay nada legible:

```
grep -E "JWT_SECRET|PASSWORD" platform/sealed-secrets/credenciales.yaml
```

Solo devuelve las claves cifradas, nunca sus valores.

---

## Cómo reproducir estas comprobaciones

Con acceso al entorno:

```
kubectl get application sa-platform -n argocd
kubectl get clusterpolicies
kubectl argo rollouts get rollout sa-platform-api-gateway -n sa-p8
kubectl get namespaces -l gestionado-por=terraform
kubectl describe resourcequota -n sa-p8
```

Sin acceso al entorno, la documentación de [P8/docs/](..) explica el diseño y
las decisiones, y [P8/docs/despliegue.md](../despliegue.md) el procedimiento
completo de recreación.
