# Guía para la revisión en vivo

Práctica 8 — María José Tebalán Sánchez — 202100265

Qué tener listo y qué mostrar, en orden, cuando el auxiliar revise el sistema.

---

## Antes de empezar

### 1. Comprobar que el entorno responde

```bash
kubectl get nodes
```

Si no responde, reconectar:

```bash
cd P8/terraform/cluster
eval "$(terraform output -raw comando_kubeconfig)"
```

### 2. Dejar abiertos los dos canales

En terminales separadas, **antes** de que empiece la revisión:

```bash
# Interfaz del operador
kubectl port-forward svc/argocd-server -n argocd 8081:80
```

```bash
# Componente expuesto, para las pruebas
kubectl port-forward svc/sa-platform-api-gateway -n sa-p8 18080:8080
```

Ambos deben seguir corriendo durante toda la sesión.

### 3. Acceso a la interfaz

- Dirección: **http://localhost:8081** — con `http`, no `https`
- Usuario: `admin`
- Contraseña:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

---

## Comprobación rápida de que todo está en pie

Un solo comando que resume el estado:

```bash
kubectl get application sa-platform -n argocd -o wide && \
kubectl get clusterpolicies && \
kubectl argo rollouts get rollout sa-platform-api-gateway -n sa-p8 | head -8
```

Estado esperado:

| Comprobación | Valor |
|---|---|
| Aplicación | `Synced` / `Healthy` |
| Políticas | 3, todas `Ready` |
| Promoción | `Healthy`, 6 de 6 etapas |

---

## Datos que pueden preguntar

| Dato | Valor |
|---|---|
| Aplicación | `sa-platform` |
| Espacio del operador | `argocd` |
| Espacio de la aplicación | `sa-p8` |
| Carga con entrega progresiva | `sa-platform-api-gateway` |
| Artefacto firmado | `ghcr.io/majosanchez07/practicas-sa-b-202100265/p8-api-gateway:1.0.1` |
| Repositorio de declaración | https://github.com/majosanchez07/Practicas-SA-B-202100265-gitops |

---

## Orden sugerido para mostrar

### 1. La aplicación está sincronizada y sana

```bash
kubectl get application sa-platform -n argocd -o wide
```

Es el requisito de calificación. Conviene abrirlo también en la interfaz
gráfica: el árbol de recursos se ve claro y muestra los 72 objetos
sincronizados.

### 2. La infraestructura no se creó a mano

```bash
kubectl get namespaces -l gestionado-por=terraform
kubectl describe resourcequota -n sa-p8
```

Esa etiqueta la pone la declaración de infraestructura. Un recurso creado con un
comando suelto no la llevaría.

### 3. La automatización no puede desplegar

```bash
./P8/scripts/verificar-sin-despliegue-directo.sh
```

Y para mostrar que el control detecta de verdad, no que siempre aprueba:

```bash
./P8/scripts/verificar-sin-despliegue-directo.sh \
  .github/workflows-p7-archivado/p7-cicd.yml
```

El primero pasa; el segundo falla, porque esa automatización sí desplegaba.

### 4. La promoción avanza por etapas condicionadas al análisis

```bash
kubectl argo rollouts get rollout sa-platform-api-gateway -n sa-p8
```

Se ven las etapas, la estrategia y los análisis ejecutados.

### 5. La reversión automática ocurrió

```bash
kubectl get analysisruns -n sa-p8
```

Aparecen dos análisis fallidos. El detalle:

```bash
AR=$(kubectl get analysisruns -n sa-p8 --sort-by=.metadata.creationTimestamp \
     -o name | tail -1)
kubectl get "$AR" -n sa-p8 \
  -o jsonpath='{range .status.metricResults[*]}{.name}: {.phase}{"\n"}{end}'
```

**Este es el punto fuerte de la entrega.** El resultado muestra que la prueba de
disponibilidad y la de rendimiento dieron por buena una versión defectuosa, y
solo la de funcionalidad la detectó. La recuperación tomó 66 segundos con un
20% del tráfico afectado.

Si piden verlo documentado:

```bash
cat P8/docs/evidencias/rollouts/reversion-automatica.txt
```

### 6. Las políticas rechazan lo no conforme

En vivo, es instantáneo y se ve bien:

```bash
kubectl apply -f P8/policies/pruebas/pod-que-viola-las-politicas.yaml
```

Devuelve el rechazo con el detalle de cada regla incumplida. Comprobar que el
objeto no se creó:

```bash
kubectl get pod pod-violador -n sa-p8
```

### 7. Las pruebas corren contra el sistema desplegado

```bash
cd P8/tests
BASE_URL=http://localhost:18080 ./humo.sh
BASE_URL=http://localhost:18080 ./integracion.sh
```

Seis de seis y nueve de nueve.

### 8. El artefacto está firmado y la firma se verifica

```bash
cosign verify \
  ghcr.io/majosanchez07/practicas-sa-b-202100265/p8-api-gateway:1.0.1 \
  --certificate-identity-regexp "^https://github.com/majosanchez07/Practicas-SA-B-202100265/.*$" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

### 9. Las credenciales están cifradas

```bash
kubectl get sealedsecrets -n sa-p8
grep -E "PASSWORD|JWT" \
  ../Practicas-SA-B-202100265-gitops/platform/sealed-secrets/credenciales.yaml
```

Solo devuelve valores cifrados.

---

## Preguntas probables y cómo responderlas

### ¿Por qué solo un servicio tiene entrega progresiva?

Es la única puerta de entrada del sistema: una versión defectuosa ahí afecta a
todos los usuarios. Aplicarla a los siete multiplicaría el tiempo de despliegue
sin reducir el riesgo de forma proporcional, porque los componentes internos
solo son alcanzables a través de esa puerta.

### ¿Por qué esos umbrales y no otros?

El percentil 95 medido en condiciones normales está por debajo de 200 ms; el
umbral se fijó en 500 ms, más del doble. Un umbral ajustado saltaría por
variabilidad del entorno y revertiría versiones correctas — y un equipo que ve
revertirse despliegues sanos acaba desactivando el mecanismo.

La prueba de carga ejecutada midió 122 ms, lo que confirma que la holgura es
razonable.

### ¿Por qué el análisis genera tráfico en vez de observarlo?

En la primera etapa la versión candidata recibe el 20% del tráfico. Sin usuarios
reales, ese 20% de nada sigue siendo nada: un análisis por observación
concluiría "sin errores" por ausencia de datos, que produce la misma señal que
un éxito legítimo.

### ¿Por qué rechazar en lugar de corregir automáticamente?

Una corrección silenciosa hace que el despliegue funcione pero oculta que
alguien propuso algo incorrecto. El rechazo obliga a corregirlo en el origen.
Además, los valores que la corrección asignaría no estarían pensados para esa
carga concreta.

### ¿Qué pasó con las vulnerabilidades que bloquearon la construcción?

Tres casos, tres respuestas distintas:

- Una sin versión base que la evite y no explotable en este contexto → excluida
  con su justificación documentada en `P8/.trivyignore`.
- Tres en un paquete del sistema con parche disponible → actualización de la
  imagen.
- Una en una dependencia declarada del servicio de autenticación, con parche →
  actualización de versión, verificando que las pruebas siguieran pasando.

El criterio: se excluye solo lo que no se puede corregir **y** no es explotable.
Cuando el parche existe, se aplica.

---

## Si algo falla durante la revisión

### La aplicación aparece como no sincronizada

```bash
kubectl patch application sa-platform -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

Esperar unos treinta segundos.

### Un canal dejó de responder

Los `port-forward` se cortan si la conexión se interrumpe. Basta relanzarlos.

### El entorno no responde

```bash
cd P8/terraform/cluster
eval "$(terraform output -raw comando_kubeconfig)"
```

---

## Coste mientras siga encendido

Aproximadamente 0.35 dólares por hora, unos 8.40 al día.

Cuando la revisión termine:

```bash
cd P8/terraform/platform && terraform destroy
cd ../cluster            && terraform destroy
```

Después conviene comprobar que no quedan recursos sueltos, porque los que crea
el orquestador —balanceadores, volúmenes— no siempre están en el estado de la
declaración:

```bash
aws ec2 describe-nat-gateways --region us-east-2 \
  --filter "Name=state,Values=available" --query 'NatGateways[].NatGatewayId'
aws elbv2 describe-load-balancers --region us-east-2 \
  --query 'LoadBalancers[].LoadBalancerName'
aws ec2 describe-volumes --region us-east-2 \
  --filters "Name=status,Values=available" --query 'Volumes[].VolumeId'
```

Los tres deben devolver listas vacías. En esta práctica aparecieron restos de la
anterior por no haberlo comprobado en su momento.
