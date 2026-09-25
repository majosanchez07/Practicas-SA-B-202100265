# Índice de capturas de pantalla

Práctica 8 — María José Tebalán Sánchez — 202100265

Todas las capturas se tomaron el 18 de septiembre de 2026 sobre el entorno real
desplegado en la nube. Los comandos se ejecutaron en la terminal y la salida es
la que aparece en pantalla, sin edición.

---

## Infraestructura declarada

| Captura | Qué muestra |
|---|---|
| [01-nodos-cluster.png](01-nodos-cluster.png) | Los dos nodos del entorno en estado operativo, en la región `us-east-2` |
| [02-terraform-namespaces-cuotas.png](02-terraform-namespaces-cuotas.png) | Los cuatro espacios de trabajo con la etiqueta `gestionado-por=terraform`, y las cuotas aplicadas |
| [03-terraform-rbac.png](03-terraform-rbac.png) | Permisos y clase de almacenamiento declarados |

La etiqueta `gestionado-por=terraform` es la prueba de que ningún espacio se
creó a mano: un recurso creado con un comando suelto no la llevaría.

---

## Estado declarativo

| Captura | Qué muestra |
|---|---|
| [04-argocd-synced-healthy.png](04-argocd-synced-healthy.png) | **Aplicación sincronizada y sana**, con el repositorio de declaración como origen |
| [05-pods-corriendo.png](05-pods-corriendo.png) | Las once cargas de trabajo operativas |
| [16-argocd-interfaz-y-pipeline.png](16-argocd-interfaz-y-pipeline.png) | Interfaz gráfica del operador junto al historial de ejecuciones de la automatización |
| [17-argocd-arbol-recursos.png](17-argocd-arbol-recursos.png) | Árbol completo de recursos gestionados |
| [18-argocd-historial.png](18-argocd-historial.png) | Historial de sincronizaciones |

---

## Entrega progresiva y reversión

| Captura | Qué muestra |
|---|---|
| [06-rollout-promocion.png](06-rollout-promocion.png) | Promoción completada: seis de seis etapas, estado sano |
| [07-reversion-cronologia.png](07-reversion-cronologia.png) | **Mensaje de aborto** con la métrica que falló |
| [08-reversion-analisis.png](08-reversion-analisis.png) | Cronología del incidente y resultado de cada prueba |

### El dato central

La captura 08 muestra el resultado que justifica todo el diseño del análisis:

| Prueba | Resultado |
|---|---|
| Disponibilidad | Superada — el componente estaba vivo |
| Rendimiento | Superada — respondía dentro de los umbrales |
| **Funcionalidad** | **Fallida** — el servicio esencial devolvía error |

Dos de tres pruebas aprobaron una versión defectuosa. Un análisis limitado a
comprobar disponibilidad la habría promovido a la totalidad de los usuarios.

**Recuperación en 66 segundos, con un 20% del tráfico afectado durante 24
segundos, sin intervención humana.**

---

## Políticas de admisión

| Captura | Qué muestra |
|---|---|
| [09-politicas-activas.png](09-politicas-activas.png) | Las tres normas activas en modo de rechazo |
| [10-rechazo-politica.png](10-rechazo-politica.png) | **Rechazo en vivo** de un despliegue no conforme, con el detalle de cada regla incumplida |

---

## Validación automatizada

| Captura | Qué muestra |
|---|---|
| [11-pruebas-humo.png](11-pruebas-humo.png) | Pruebas ejecutándose contra el sistema desplegado |
| [12-prueba-carga.png](12-prueba-carga.png) | Resultado de la prueba de rendimiento con su veredicto |

La prueba de rendimiento midió un percentil 95 de 122 ms frente al umbral de
500 ms fijado como criterio. Esa holgura es la que evita reversiones por
variabilidad del entorno.

---

## Cadena de suministro y flujo de trabajo

| Captura | Qué muestra |
|---|---|
| [13-firma-verificada.png](13-firma-verificada.png) | Verificación de la firma del artefacto |
| [14-flujo-git.png](14-flujo-git.png) | Los dos repositorios separados con sus historiales |
| [15-secretos-cifrados.png](15-secretos-cifrados.png) | Credenciales cifradas en el repositorio público |

La verificación de firma confirma que el artefacto lo construyó el flujo de
trabajo de este repositorio y no otro: la identidad registrada en el
certificado incluye la ruta del flujo y la etiqueta de versión.

Las credenciales viven cifradas en un repositorio público sin riesgo: solo el
controlador que las cifró puede descifrarlas, con una clave que nunca sale del
entorno.

---

## Capturas previas

Las que empiezan por `00` se tomaron antes de la secuencia final y se conservan
porque registran momentos que ya no se pueden reproducir:

| Captura | Qué muestra |
|---|---|
| [00a-argocd-synced-previa.png](00a-argocd-synced-previa.png) | Primer momento en que la aplicación alcanzó el estado sano |
| [00b-reversion-previa.png](00b-reversion-previa.png) | Reversión automática recién ocurrida |
