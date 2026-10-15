# Runbook: SLODisponibilidadConsumoRapido

**Severidad:** critical (se atiende de inmediato) · **SLO:** disponibilidad 99.5 % en 30 días

## Qué significa

En la última hora, y también en los últimos 5 minutos, más del 7.2 % de las
peticiones de usuario que pasan por el api-gateway terminaron en error 5xx.
Eso es 14.4 veces el ritmo sostenible: si sigue así, el presupuesto de error
del mes se agota en unos 2 días.

## Por qué hay que intervenir

Ningún mecanismo automático lo corrige. El canary solo protege al api-gateway
durante una promoción, y este fallo ya está afectando a todos los usuarios.
Cada hora a este ritmo consume el 2 % del presupuesto mensual.

## Pasos (objetivo: llegar al registro del error en menos de 3 minutos)

1. **¿Qué funcionalidad está rota?** Grafana → tablero *Biblioteca: operación*
   → fila **Errores** → panel *Errores del gateway por ruta*.
   - `/books` → catálogo · `/loans` → préstamos · `/auth` → inicio de sesión.
2. **¿Qué servicio lo origina?** Mismo tablero, panel *Tasa de error 5xx por
   servicio*. Si un servicio interno (books-service, loans-service) tiene la
   misma curva que el gateway, el origen es ese servicio; si solo falla el
   gateway, el problema está en el gateway o en la red.
3. **¿Por qué falla?** Grafana → *Explore* → Tempo → *Search*:
   `service.name = api-gateway`, `status = error`, últimos 15 min. Abrir una
   traza: el span rojo más profundo indica el servicio y la operación que
   falló, con su duración.
4. **¿Qué dijo el servicio?** Desde el span, *Logs for this span* (abre Loki
   filtrado por el `trace_id`). Alternativamente, en el panel *Registros de
   error* del tablero, hacer clic en el `trace_id`. Consulta manual:

   ```logql
   {namespace="sa-p8", container=~"api-gateway|loans-service|books-service"} | json | level="error"
   ```
5. **¿Cambió algo?** ArgoCD → aplicación `sa-platform` → *History*. Un cambio
   en los últimos minutos en `environments/prod/values.yaml` es el primer
   sospechoso.

## Mitigación

| Causa encontrada | Acción |
|---|---|
| Cambio reciente en el repositorio GitOps | `git revert` del commit en el repositorio GitOps y push. ArgoCD sincroniza solo. |
| Un servicio sin réplicas listas | `kubectl -n sa-p8 get pods` / `describe`; revisar *Saturación* en el tablero (memoria al límite = OOMKilled). |
| PostgreSQL o RabbitMQ caídos | `kubectl -n sa-p8 get statefulset`; seguir el runbook de recuperación de la Práctica 9. |
| Registro `pool de conexiones agotado` con `causa=fallo-inducido-p10` | Es el fallo de la demostración: `services.books-service.fault.enabled: false` en el repositorio GitOps. |

No se aplica nada con `kubectl apply` ni `kubectl edit`: ArgoCD revertiría el
cambio (selfHeal). Toda corrección pasa por el repositorio GitOps.

## Cómo saber que terminó

- Panel *Tasa de error 5xx por servicio* por debajo de 0.5 %.
- La alerta pasa a *resolved* (la ventana de 5 minutos baja primero; por eso
  la alerta se apaga en minutos y no en una hora).
