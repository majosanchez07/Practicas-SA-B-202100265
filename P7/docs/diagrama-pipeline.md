# Diagrama del pipeline CI/CD

**María José Tebalán Sánchez — 202100265**

## 1. Vista general del flujo

Las cuatro fases solicitadas por el enunciado —**build, test, dockerización y
despliegue**— más la etapa de versionado que las precede y la verificación que
las cierra.

```mermaid
flowchart TD
    subgraph disparadores["Disparadores"]
        direction LR
        T1["push a main"]
        T2["push a develop"]
        T3["tag v*.*.*"]
        T4["pull request"]
        T5["manual<br/>workflow_dispatch"]
    end

    disparadores --> V

    V["<b>ETAPA 0 — Versión</b><br/>Calcula una sola versión<br/>para toda la ejecución<br/><i>main-a1b2c3d / 1.2.0</i>"]

    V --> BN
    V --> BP

    subgraph fase1["FASE 1 — BUILD"]
        direction LR
        BN["<b>build-node</b><br/>npm ci + node --check<br/>api-gateway<br/>loans-service<br/>notifications-service"]
        BP["<b>build-python</b><br/>pip install + compileall<br/>auth-service · books-service<br/>cronjob-insert · cronjob-summary"]
    end

    BN --> TN
    BP --> TP

    subgraph fase2["FASE 2 — TEST"]
        direction LR
        TN["<b>test-node</b><br/>node --test<br/>54 pruebas"]
        TP["<b>test-python</b><br/>pytest + cobertura<br/>55 pruebas"]
    end

    TN --> D
    TP --> D

    subgraph fase3["FASE 3 — DOCKERIZACIÓN"]
        D["<b>docker</b> — matriz de 7 componentes<br/>Dockerfile.prod multietapa, target prod<br/>build + tag + push"]
    end

    D --> GHCR[("<b>GHCR</b><br/>ghcr.io<br/>7 imágenes etiquetadas")]

    GHCR --> DEP

    subgraph fase4["FASE 4 — DESPLIEGUE"]
        DEP["<b>desplegar</b><br/>crear clúster kind<br/>+ Secret de registro<br/>+ helm upgrade --install<br/>--wait"]
        VER["<b>verificar</b><br/>réplicas · reinicios<br/>imágenes · humo · cronjobs"]
        EVI["<b>evidencia</b><br/>artefacto de la ejecución"]
        DEP --> VER --> EVI
    end

    EVI --> R["<b>ETAPA 5</b><br/>Resumen del pipeline"]

    classDef etapa fill:#1e3a5f,stroke:#4a90d9,stroke-width:2px,color:#fff
    classDef registro fill:#4a2b5f,stroke:#a06cd5,stroke-width:2px,color:#fff
    classDef resultado fill:#1e4d2b,stroke:#4caf50,stroke-width:2px,color:#fff
    class V,BN,BP,TN,TP,D,DEP,VER,EVI etapa
    class GHCR registro
    class R resultado
```

## 2. Puertas de control: qué detiene el pipeline

Las dependencias `needs:` no son decorativas. Definen en qué punto se detiene
todo cuando algo sale mal, y ese es el valor real de la integración continua.

```mermaid
flowchart LR
    A["Commit"] --> B{"¿Compila?"}
    B -->|no| X1["DETENIDO<br/>no se ejecutan pruebas"]
    B -->|sí| C{"¿Pruebas<br/>en verde?"}
    C -->|no| X2["DETENIDO<br/><b>no se publica<br/>ninguna imagen</b>"]
    C -->|sí| D{"¿Imagen<br/>construida?"}
    D -->|no| X3["DETENIDO<br/>no se toca el clúster"]
    D -->|sí| E{"¿Es un<br/>pull request?"}
    E -->|sí| P["Imagen construida<br/>pero NO publicada"]
    E -->|no| F["Push a GHCR"]
    F --> G{"¿Pods<br/>listos?"}
    G -->|no| X4["DETENIDO<br/>+ logs y eventos<br/>como diagnóstico"]
    G -->|sí| H{"¿Gateway<br/>responde?"}
    H -->|no| X5["DETENIDO<br/>despliegue no verificado"]
    H -->|sí| OK["ENTREGADO<br/>+ evidencia archivada"]

    classDef falla fill:#5f1e1e,stroke:#d94a4a,stroke-width:2px,color:#fff
    classDef exito fill:#1e4d2b,stroke:#4caf50,stroke-width:2px,color:#fff
    classDef neutro fill:#3d3d1e,stroke:#d9d94a,stroke-width:2px,color:#fff
    class X1,X2,X3,X4,X5 falla
    class OK,F exito
    class P neutro
```

## 3. Qué se construye y dónde termina

Los siete componentes recorren el pipeline en paralelo mediante estrategias
matriciales, y terminan como pods en el clúster.

```mermaid
flowchart LR
    subgraph codigo["Código fuente — P7/"]
        direction TB
        S1["services/api-gateway<br/><i>Node</i>"]
        S2["services/auth-service<br/><i>Python</i>"]
        S3["services/books-service<br/><i>Python</i>"]
        S4["services/loans-service<br/><i>Node</i>"]
        S5["services/notifications-service<br/><i>Node</i>"]
        C1["cronjobs/cronjob-insert<br/><i>Python</i>"]
        C2["cronjobs/cronjob-summary<br/><i>Python</i>"]
    end

    codigo -->|"Dockerfile.prod<br/>multietapa"| IMG

    subgraph IMG["Imágenes en GHCR"]
        direction TB
        I1["p7-api-gateway"]
        I2["p7-auth-service"]
        I3["p7-books-service"]
        I4["p7-loans-service"]
        I5["p7-notifications-service"]
        I6["p7-cronjob-insert"]
        I7["p7-cronjob-summary"]
    end

    IMG -->|"helm upgrade --install<br/>values-ci.yaml"| K8S

    subgraph K8S["Clúster — namespace sa-p7"]
        direction TB
        D1["5 Deployments"]
        D2["2 CronJobs"]
        D3["PostgreSQL + RabbitMQ<br/><i>subcharts Bitnami<br/>desde Docker Hub</i>"]
    end

    classDef fuente fill:#1e3a5f,stroke:#4a90d9,color:#fff
    classDef imagen fill:#4a2b5f,stroke:#a06cd5,color:#fff
    classDef cluster fill:#1e4d2b,stroke:#4caf50,color:#fff
    class S1,S2,S3,S4,S5,C1,C2 fuente
    class I1,I2,I3,I4,I5,I6,I7 imagen
    class D1,D2,D3 cluster
```

## 4. Esquema de versionado

Una misma ejecución etiqueta cada imagen varias veces, según el disparador.

```mermaid
flowchart TD
    subgraph entrada["Referencia de git"]
        R1["rama main<br/>commit a1b2c3d"]
        R2["rama develop<br/>commit e4f5g6h"]
        R3["tag v1.2.0"]
    end

    R1 --> T1["<b>main-a1b2c3d</b><br/>sha-a1b2c3d<br/><b>latest</b>"]
    R2 --> T2["<b>develop-e4f5g6h</b><br/>sha-e4f5g6h<br/><i>sin latest</i>"]
    R3 --> T3["<b>1.2.0</b><br/>1.2<br/>sha-...<br/><b>latest</b>"]

    T1 --> N1["El tag latest se mueve<br/>SOLO desde la rama por defecto"]
    T2 --> N1
    T3 --> N1

    classDef ref fill:#1e3a5f,stroke:#4a90d9,color:#fff
    classDef tag fill:#4a2b5f,stroke:#a06cd5,color:#fff
    classDef nota fill:#3d3d1e,stroke:#d9d94a,color:#fff
    class R1,R2,R3 ref
    class T1,T2,T3 tag
    class N1 nota
```

## 5. Tiempos aproximados

| Etapa | Duración típica | Paralelismo |
|---|---|---|
| 0 — Versión | ~10 s | 1 job |
| 1 — Build | ~1 min | 7 jobs en paralelo |
| 2 — Test | ~1 min | 5 jobs en paralelo |
| 3 — Docker | 2–6 min | 7 jobs en paralelo (con caché, ~2 min) |
| 4 — Despliegue | 6–10 min | 1 job |
| **Total** | **~10–18 min** | |

La etapa de despliegue domina el tiempo porque crea un clúster desde cero,
descarga PostgreSQL y RabbitMQ, y espera a que todos los pods pasen sus probes.
