# Diagrama del flujo de telemetría

Práctica 10 · María José Tebalán Sánchez · 202100265

Recorrido de cada señal desde el servicio hasta el tablero, la alerta y la
decisión del canary. Todo lo que aparece aquí lo despliega ArgoCD desde el
repositorio GitOps; nada se instala a mano.

```mermaid
flowchart LR
    subgraph usuarios["Tráfico"]
        U["Usuarios"]
        K6["generador-trafico<br/>(k6 permanente)"]
    end

    subgraph app["namespace sa-p8"]
        GW["api-gateway<br/>Rollout canary<br/>SDK OTel Node"]
        LO["loans-service<br/>SDK OTel Node"]
        BO["books-service<br/>SDK OTel Python"]
        PG[("PostgreSQL")]
        MQ[("RabbitMQ")]
    end

    subgraph obs["namespace observabilidad"]
        COL["OTel Collector<br/>OTLP :4318"]
        TEMPO[("Tempo<br/>trazas, 72 h")]
        PROM[("Prometheus<br/>métricas, 30 d")]
        PT["Promtail<br/>DaemonSet"]
        LOKI[("Loki<br/>registros, 7 d")]
        AM["Alertmanager"]
        GRAF["Grafana<br/>tablero de operación"]
    end

    AR["Argo Rollouts<br/>AnalysisRun"]

    U --> GW
    K6 --> GW
    GW -- "traceparent" --> LO
    GW -- "traceparent" --> BO
    LO -- "traceparent" --> BO
    LO --> PG
    LO -- "contexto en cabeceras" --> MQ
    BO --> PG

    GW & LO & BO -- "trazas + métricas<br/>OTLP/HTTP" --> COL
    COL -- "OTLP gRPC" --> TEMPO
    COL -- ":8889 /metrics<br/>(service_name, rollout_hash)" --> PROM
    GW & LO & BO -. "JSON en stdout<br/>con trace_id" .-> PT
    PT --> LOKI

    PROM -- "reglas SLO<br/>burn rate" --> AM
    PROM -- "tasa de error y p95<br/>del rollout_hash candidato" --> AR
    AR -- "aborta y revierte" --> GW

    PROM --> GRAF
    TEMPO --> GRAF
    LOKI --> GRAF
    AM -- "runbook_url" --> GRAF
```

## Las tres señales y cómo se enlazan

| Señal | Origen | Transporte | Almacén | Enlace hacia las otras |
|---|---|---|---|---|
| Trazas | SDK OTel (spans de http, express, graphql, pg, amqplib, FastAPI, SQLAlchemy) | OTLP → Collector → Tempo | Tempo | Span → registros (Loki por `trace_id`) · Span → métricas del servicio |
| Métricas | SDK OTel: `sa_http_requests_total`, `sa_http_request_duration_seconds`, `biblioteca_*` | OTLP → Collector → `:8889` ← Prometheus | Prometheus | Panel → *Explore* en Tempo con el mismo rango de tiempo |
| Registros | `logger.js` / `observabilidad.py`: una línea JSON con `trace_id` y `span_id` | stdout → Promtail | Loki | Campo `trace_id` → traza en Tempo (*derived field*) |

## Por qué los registros no pasan por el Collector

Si el Collector falla, las trazas y las métricas dejan de llegar. Si los
registros dependieran de él, se perdería también la única señal capaz de
explicar *por qué* falló el Collector. Promtail lee el disco del nodo de forma
independiente.

## El camino de una alerta

```
sa_http_requests_total (cada 10 s desde el SDK, cada 15 s a Prometheus)
  └─ slo:sli_errores:ratio_rate5m / 1h      (regla de registro, cada 30 s)
       └─ SLODisponibilidadConsumoRapido     (ambas ventanas > 7.2 % durante 1 min)
            └─ Alertmanager: receptor "guardia" (agrupa por alertname y slo)
                 └─ anotación runbook_url → docs/runbooks/*.md
```

## El camino de la decisión del canary

```
Rollout crea el ReplicaSet candidato (hash H)
  └─ el pod recibe ROLLOUT_HASH=H (downward API de la etiqueta rollouts-pod-template-hash)
       └─ el SDK lo publica como atributo de recurso rollout.hash
            └─ el Collector lo convierte en la etiqueta rollout_hash
                 └─ AnalysisRun consulta Prometheus con rollout_hash="H"
                      └─ 2 mediciones fallidas → Rollout abortado → 100 % a la estable
```
