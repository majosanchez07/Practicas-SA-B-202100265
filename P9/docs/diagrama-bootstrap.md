# Diagrama del bootstrap: orden de reconstrucción

Práctica 9 · María José Tebalán Sánchez · 202100265

El diagrama muestra el **orden** en que se reconstruye el sistema y de qué
depende cada paso. No es un diagrama de arquitectura. Las cajas **grises** viven
fuera del clúster, en `rg-sa-p9-base-202100265`, y sobreviven al desastre. Las **naranjas** son el único paso
manual, que se hace una sola vez y antes de cualquier incidente. Las **verdes**
son automáticas y las lanza `P9/scripts/bootstrap.sh`.

```mermaid
flowchart TD
    classDef manual fill:#f6ad55,stroke:#9c4221,color:#000
    classDef externo fill:#e2e8f0,stroke:#4a5568,color:#000
    classDef auto fill:#9ae6b4,stroke:#276749,color:#000
    classDef gitops fill:#90cdf4,stroke:#2c5282,color:#000

    M1["crear-backend.sh<br/>(una vez, antes del incidente)"]:::manual
    M2["respaldar-llave-sealed.sh<br/>(una vez, antes del incidente)"]:::manual

    S3E[("Blob sap9tfstate<br/>estado + lease (bloqueo)")]:::externo
    S3V[("Blob sap9velero<br/>+ snapshots de disco")]:::externo
    SM[("Key Vault kv-sa-p9<br/>llave Sealed Secrets")]:::externo
    GIT[("GitHub: repo de código<br/>+ repo GitOps")]:::externo

    M1 --> S3E & S3V
    M2 --> SM

    B0(["./P9/scripts/bootstrap.sh<br/>PUNTO DE ENTRADA ÚNICO"]):::auto
    B1["1 · Terraform cluster/<br/>grupo · AKS · nodos · identidad Velero"]:::auto
    B2a["2a · Terraform platform/<br/>namespaces · cuotas · RBAC · LimitRange"]:::auto
    B2b["2b · Secret con la llave<br/>(leída de Key Vault)"]:::auto
    B2c["2c · Sealed Secrets controller"]:::auto
    B2d["2d · Velero (BSL → Blob)"]:::auto
    B2e["2e · ArgoCD"]:::auto
    B3["3 · velero restore<br/>PVC + PV del último respaldo"]:::auto
    B4["4 · Terraform: app raíz raiz-sa-p9"]:::auto

    S3E -. estado .-> B1
    B0 --> B1 --> B2a --> B2b --> B2c --> B2e
    SM -. llave .-> B2b
    B2a --> B2d
    S3V -. respaldos .-> B3
    B2d --> B3 --> B4
    B2e --> B4

    subgraph ARGO["5 · ArgoCD app-of-apps (automático, desde Git)"]
      W0["ola 0: argo-rollouts · kyverno"]:::gitops
      W1["ola 1: secretos-cifrados · politicas-admision · respaldos-velero"]:::gitops
      W3["ola 3: sa-platform<br/>(adopta el PVC restaurado)"]:::gitops
      W0 --> W1 --> W3
    end
    GIT -. manifiestos .-> ARGO
    B4 --> W0
    B2c -. descifra .-> W1
    W3 --> V["6 · Verificaciones:<br/>secreto descifrado · filas en la BD · políticas · schedule"]:::auto
```

## Dependencias críticas

| Paso | Depende de | Por qué ese orden |
|---|---|---|
| 2b llave antes de 2c controlador | Key Vault | Si el controlador arranca sin la llave, genera una nueva y los SealedSecret del repositorio quedan ilegibles. |
| 3 restauración antes de 4 app raíz | Velero listo y respaldos en Blob | Si ArgoCD crea PostgreSQL antes, nace un PVC vacío con el mismo nombre y Velero no lo sobrescribe. |
| Ola 0 antes de la ola 1 | CRDs de Kyverno y Rollouts | Las políticas (`ClusterPolicy`) y el `Rollout` necesitan sus CRD. |
| Ola 1 antes de la ola 3 | `sa-platform-secret` descifrado | PostgreSQL y los servicios leen sus credenciales de ese Secret. |
| Todo | Sesión `az login` del operador | Es la única credencial que se necesita. Las demás se derivan de ella (workload identity, credenciales de AKS). |
