# Preguntas teóricas — Práctica 7

**María José Tebalán Sánchez — 202100265**

---

## 1. ¿Qué es CI/CD y qué problema resuelve en un ecosistema de microservicios?

**CI (integración continua)** es la práctica de fusionar el trabajo de todos en
una rama común de forma frecuente, con una verificación automática —compilar y
probar— que se ejecuta en cada integración. **CD** designa dos cosas distintas
que conviene separar: *continuous delivery*, dejar cada cambio validado y listo
para desplegarse, y *continuous deployment*, desplegarlo automáticamente sin
aprobación humana. El pipeline de esta práctica llega hasta la segunda.

El problema que resuelve se agrava justamente en los microservicios. Con una
aplicación monolítica hay un artefacto, una versión y un despliegue. Con siete
componentes como los de esta plataforma hay siete imágenes que construir,
etiquetar y publicar, y siete cargas de trabajo que actualizar de forma
coordinada. Hacerlo a mano tiene tres consecuencias concretas que viví en las
prácticas anteriores:

**Versiones descoordinadas.** Al construir las imágenes una por una es fácil
terminar con un `auth-service` de ayer y un `books-service` de hoy conviviendo en
el clúster. Si entre ambos cambió un contrato, la falla aparece en ejecución y no
hay nada que la explique. El pipeline lo resuelve calculando la versión **una
sola vez** en la etapa 0 y pasándosela a todos los jobs, de modo que las siete
imágenes de una ejecución comparten exactamente el mismo tag.

**Pruebas que se saltan.** Cuando ejecutar las pruebas es un paso manual antes de
publicar, tarde o temprano se omite —normalmente el día que hay prisa, que es
justo cuando más falta hacía. En el pipeline la etapa de Docker depende de la de
test con `needs:`, así que no es una recomendación: si una prueba falla, no
existe forma de que se publique la imagen.

**Entornos que divergen.** "En mi máquina funciona" suele significar que la
máquina tiene una versión distinta de Node, una variable de entorno que nadie
documentó o una dependencia instalada globalmente. El runner parte de una imagen
limpia en cada ejecución e instala con `npm ci` a partir del lockfile, de modo que
la construcción es reproducible por definición.

Hay un cuarto efecto, menos evidente y quizá más valioso: **el pipeline
documenta el proceso de despliegue**. El archivo YAML es la única descripción
verdadera de cómo se construye y despliega el sistema, y no puede quedar
desactualizada respecto a la realidad, porque *es* la realidad.

---

## 2. ¿Qué diferencia hay entre un pipeline de CI y uno de CD? ¿Por qué separarlos en etapas?

**CI responde "¿este cambio es correcto?"** Compila, ejecuta las pruebas, revisa
el estilo. Su salida es un veredicto y un artefacto validado. En mi pipeline son
las etapas 1 y 2, y corren ante cualquier disparo, incluidos los pull requests.

**CD responde "¿este cambio ya está donde debe estar?"** Empaqueta, publica y
aplica los cambios en el clúster. Son las etapas 3 y 4, y no corren en un pull
request: una rama propuesta no tiene por qué ensuciar el registro ni tocar el
ambiente.

Separarlas en jobs distintos tiene cuatro razones prácticas:

**Las puertas de control.** Es la razón principal. Al declarar
`docker: needs: [test-node, test-python]`, la publicación queda subordinada a las
pruebas. Con todo en un solo job habría que confiar en el orden de los comandos y
en que nadie agregue un `|| true` para "desbloquear" algo urgente.

**El diagnóstico.** Cuando el pipeline se pone rojo, el nombre del job dice de
inmediato qué falló: no es lo mismo "2 - Test" que "4 - Despliegue K8s". Con una
sola etapa habría que leer cientos de líneas de log para saber en qué punto se
rompió.

**El paralelismo.** Los jobs independientes corren a la vez. Las siete
construcciones de imagen ocurren en paralelo mediante una matriz; en secuencia
tomarían unos veinte minutos, y así toman entre dos y seis.

**La reejecución selectiva.** Si el despliegue falla por una causa transitoria,
se puede relanzar solo ese job sin repetir veinte minutos de construcción.

Hay un matiz importante: separar en etapas **no** es separar en pipelines. Todo
vive en un mismo workflow precisamente para que las dependencias sean explícitas.
Si CI y CD fueran workflows distintos, habría que inventar un mecanismo que
comunique "las pruebas pasaron" entre ambos, y ese mecanismo sería el eslabón
débil.

---

## 3. ¿Qué ventajas ofrece GitHub Actions frente a otras herramientas de CI/CD?

**La cercanía al código.** El workflow vive en el mismo repositorio, en
`.github/workflows/`, y se versiona con él. Un cambio en el proceso de
construcción viaja en el mismo commit que el cambio que lo motivó, y la rama que
lo propone usa su propia versión del pipeline. Con un servidor externo como
Jenkins, la configuración suele vivir aparte y termina desincronizada del código
que construye.

**No requiere infraestructura.** No hay servidor que instalar, parchear ni
mantener disponible. Para un proyecto académico la diferencia es radical: el
pipeline funciona al clonar el repositorio, sin un paso previo de montaje.

**La integración con el ecosistema.** `GITHUB_TOKEN` es el ejemplo más claro:
Actions genera un token efímero por ejecución, con permisos acotados a lo que el
workflow declare, y que expira al terminar. Gracias a eso mi pipeline publica en
GHCR **sin ningún secreto configurado a mano**. Con Docker Hub habría tenido que
crear un token personal, guardarlo como secreto y rotarlo periódicamente.

**El marketplace.** Acciones como `docker/build-push-action`, `helm/kind-action`
o `docker/metadata-action` encapsulan trabajo que de otro modo habría que
escribir a mano. El cálculo de etiquetas que hace `metadata-action` —versión, SHA,
semántico, `latest` solo en la rama por defecto— serían decenas de líneas de bash
frágil.

**Las matrices.** Declarar siete componentes en una lista y obtener siete jobs
paralelos evita repetir el mismo bloque siete veces, que es donde se cuelan las
inconsistencias.

Ahora bien, conviene ser honesta sobre las desventajas. Actions **ata el
proyecto a GitHub**: migrar a GitLab significa reescribir el pipeline entero.
Jenkins, con todo su costo operativo, corre donde uno quiera. El modelo de
minutos también puede encarecerse en repositorios privados con mucho movimiento,
y depurar un workflow es lento: no hay forma de ejecutar paso a paso, así que
cada corrección implica un commit y esperar la ejecución completa.

Para el caso de esta práctica —un repositorio ya alojado en GitHub, sin
infraestructura propia y con necesidad de publicar imágenes— las ventajas pesan
claramente más.

---

## 4. ¿Qué papel juegan Docker y Kubernetes dentro del flujo de CI/CD?

Resuelven dos problemas distintos y complementarios: Docker define **qué** se
entrega, y Kubernetes **cómo** se ejecuta.

### Docker: el artefacto inmutable

Sin contenedores, el artefacto de un pipeline es código fuente más una lista de
instrucciones de instalación, y el resultado depende de lo que haya en la máquina
destino. Con Docker el artefacto es una imagen que incluye el sistema base, el
intérprete, las dependencias y el código. La **misma** imagen que se probó es la
que corre en producción, no una reconstrucción equivalente.

Eso habilita dos cosas que el pipeline aprovecha directamente. La primera es la
**trazabilidad**: la imagen `p7-auth-service:main-a1b2c3d` se puede rastrear
hasta el commit exacto que la produjo. La segunda es el **rollback**: volver
atrás es desplegar la etiqueta anterior, que sigue en el registro, en lugar de
revertir código y reconstruir.

En mi pipeline la construcción es multietapa (`Dockerfile.prod`): una etapa
instala dependencias y compila, y la imagen final copia solo lo necesario. El
resultado no lleva compilador ni dependencias de desarrollo, pesa bastante menos
y expone mucha menos superficie de ataque.

### Kubernetes: el despliegue declarativo

La aportación de Kubernetes al pipeline es que el despliegue se **declara** en
lugar de programarse. El pipeline no ejecuta "detén el servicio viejo, arranca el
nuevo, verifica, y si algo falla revierte": aplica un manifiesto que dice qué
imagen debe correr, y el controlador se encarga del resto —reemplazo gradual,
espera de las probes, detención si los pods nuevos no quedan listos—.

Eso significa que el paso de despliegue del pipeline es esencialmente un
`helm upgrade --install --wait`. Toda la complejidad de un despliegue sin caída
vive en el orquestador, no en un script de bash que habría que mantener.

Kubernetes aporta además el **criterio de éxito**. `--wait` no retorna hasta que
los pods pasan sus probes de readiness, de modo que el pipeline sabe si el
despliegue funcionó sin necesidad de inventar una comprobación. Si los pods
nuevos no arrancan, el rollout se detiene solo y los viejos siguen atendiendo.

### Cómo encajan

```
Código → [Docker] → Imagen etiquetada → Registro → [Kubernetes] → Pods
         qué se entrega                             cómo se ejecuta
```

El registro es la frontera entre ambos, y es lo que permite que CI y CD sean
independientes: CI termina cuando la imagen está publicada; CD empieza tomándola
de ahí. Si mañana hubiera que desplegar en otro clúster, el CI no cambiaría en
absoluto.

---

## 5. ¿Qué es una imagen Docker, un registry y qué ventajas tiene usar GHCR o DockerHub?

### Imagen

Una imagen es una plantilla de solo lectura compuesta por **capas** apiladas,
cada una con los cambios respecto a la anterior, más un manifiesto con metadatos
—comando de arranque, variables, usuario, puertos—. Un contenedor es una
instancia en ejecución de una imagen, con una capa de escritura encima.

Dos propiedades importan aquí. La primera es que las capas se **comparten y se
cachean**: si solo cambia el código, las capas de dependencias se reutilizan, y
por eso la caché del pipeline reduce la construcción de minutos a segundos. La
segunda es que la imagen se identifica por un **digest** criptográfico del
contenido: dos imágenes con el mismo digest son idénticas byte a byte, mientras
que una etiqueta es solo un puntero móvil.

Esa distinción explica por qué mi pipeline nunca despliega `latest`. Una
etiqueta puede reapuntar a otra imagen en cualquier momento, así que `latest`
no identifica nada en particular. El despliegue usa siempre la versión única de
la ejecución.

### Registry

Un registry es el servicio que almacena y distribuye imágenes. Expone una API
estándar (OCI Distribution) para subirlas y descargarlas, y organiza el contenido
en repositorios con sus etiquetas.

Es la pieza que desacopla construcción de ejecución. Sin él, el nodo que corre el
contenedor tendría que construirlo, que es lo que hacía `kind load` en las
prácticas locales y lo que deja de ser viable en cuanto hay más de un nodo.

### GHCR frente a Docker Hub

Elegí **GHCR** para esta práctica, por tres razones:

**Autenticación sin secretos.** GHCR acepta el `GITHUB_TOKEN` que Actions genera
por ejecución. No hay que crear ningún secreto en la configuración del
repositorio, ni rotarlo, ni arriesgarse a filtrarlo. Con Docker Hub habría hecho
falta un token personal guardado como secreto, con vigencia indefinida.

**Sin límites de descarga.** Docker Hub limita las descargas anónimas por
dirección IP. Los runners de Actions comparten rangos de IP con muchísimos otros
usuarios, así que ese límite se alcanza con facilidad y produce fallos
intermitentes difíciles de diagnosticar: el pipeline falla sin que nada haya
cambiado en el código.

**Permisos heredados del repositorio.** La visibilidad y el acceso de las
imágenes siguen los del repositorio, en lugar de administrarse en una cuenta
aparte que puede quedar desincronizada.

Docker Hub conserva dos ventajas reales: es el registro por defecto —`postgres`
significa `docker.io/library/postgres`, y de hecho de ahí vienen PostgreSQL y
RabbitMQ en este despliegue— y tiene el catálogo público más amplio. Para
distribuir una imagen a un público general sigue siendo la opción natural. Para
imágenes de un proyecto concreto, ligadas a su repositorio y consumidas por su
propio pipeline, GHCR encaja mejor.

Vale la pena mencionar un detalle que costó depurar: las imágenes publicadas en
GHCR desde un repositorio privado **nacen privadas**. El clúster necesita
credenciales para descargarlas, y por eso la etapa de despliegue crea un `Secret`
de tipo `docker-registry` antes de instalar el chart. Sin él, los pods quedan en
`ImagePullBackOff` con un mensaje que no sugiere en absoluto que el problema sea
de permisos.
