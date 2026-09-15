# Diagrama del flujo de entrega

Práctica 8 — María José Tebalán Sánchez — 202100265

Este documento describe el recorrido completo de un cambio, desde que se
publica una versión hasta que llega a los usuarios o es revertido. Se indica en
cada punto qué componente actúa, qué se valida y dónde puede detenerse el
avance.

---

## 1. Actores y componentes

### Actores humanos

| Actor | Responsabilidad | Lo que NO puede hacer |
|---|---|---|
| Desarrollador | Escribe el código y publica una versión etiquetada | Aplicar cambios al entorno productivo |
| Revisor | Aprueba o rechaza la propuesta de promoción | Modificar el entorno sin dejar registro |
| Operador | Consulta el estado y diagnostica incidentes | Alterar el estado sin que se revierta solo |

La primera columna de exclusiones es el fundamento del modelo: **ninguna
persona aplica cambios directamente al entorno productivo.** Todo cambio pasa
por el repositorio de declaración, queda registrado y es reversible.

### Componentes automáticos

| Componente | Función | Ámbito |
|---|---|---|
| Automatización de construcción | Compila, prueba, analiza, firma y propone | Fuera del entorno de ejecución |
| Motor de declaración | Lee el repositorio y aplica lo declarado | Dentro del entorno de ejecución |
| Controlador de promoción | Avanza o revierte por etapas | Dentro del entorno de ejecución |
| Motor de admisión | Rechaza lo que incumple las normas | Dentro del entorno de ejecución |
| Verificador de análisis | Ejecuta pruebas contra la versión candidata | Dentro del entorno de ejecución |

---

## 2. Diagrama general

```
  ACTORES              REPOSITORIOS              AUTOMATIZACIÓN           ENTORNO DE EJECUCIÓN
  =======              ============              ==============           ====================

 +--------------+
 |              |  publica version
 | Desarrollador|-----------------+
 |              |                 |
 +--------------+                 v
                          +----------------+
                          |                |
                          |  Repositorio   |
                          |   de codigo    |
                          |                |
                          +--------+-------+
                                   |
                                   | dispara
                                   v
                          +--------------------------------------+
                          |     CADENA DE CONSTRUCCION           |
                          |                                      |
                          |  (1) Pruebas unitarias        [P1]   |
                          |  (2) Validacion de empaquetado[P2]   |
                          |  (3) Analisis de seguridad    [P3]   |
                          |  (4) Inventario de componentes       |
                          |  (5) Firma del artefacto             |
                          |  (6) Verificacion de la firma        |
                          +------------------+-------------------+
                                             |
                                             | propone (no aplica)
                                             v
                                    +------------------+
 +--------------+   revisa          |                  |
 |              |<------------------|    Propuesta     |
 |   Revisor    |                   |   de promocion   |
 |              |------------------>|                  |
 +--------------+   aprueba         +---------+--------+
                                              |
                                              | se integra
                                              v
                                    +------------------+
                                    |                  |
                                    |  Repositorio de  |
                                    |   declaracion    |<--- UNICA FUENTE DE VERDAD
                                    |                  |
                                    +---------+--------+
                                              |
                                              | lee (el entorno tira,
                                              |      nadie empuja)
                                              v
 - - - - - - - - - - - - - - - - - - - - - - -|- - - - - - - - - - - - - - - - - - - - -
                                              v          FRONTERA DEL ENTORNO
                                    +------------------+
                                    |    Motor de      |
                                    |   declaracion    |
                                    +---------+--------+
                                              |
                                              | solicita aplicar
                                              v
                                    +------------------+
                                    |    Motor de      |
                                    |    admision      |  [P4] rechaza lo no conforme
                                    +---------+--------+
                                              |
                                              | admitido
                                              v
                                    +------------------+
                                    |  Controlador de  |
                                    |    promocion     |
                                    +---------+--------+
                                              |
                                              v
                          +-------------------------------------------+
                          |         PROMOCION POR ETAPAS              |
                          |                                           |
                          |   20% --> [P5] --> 50% --> [P5] -->       |
                          |                                           |
                          |            80% --> [P5] --> 100%          |
                          +------+-----------------------------+------+
                                 |                             |
                       analisis  |                             |  analisis
                       favorable |                             |  desfavorable
                                 v                             v
                        +----------------+            +------------------+
                        |   Version      |            |    REVERSION     |
                        |   promovida    |            |    AUTOMATICA    |
                        |   al 100%      |            |  (sin humanos)   |
                        +--------+-------+            +---------+--------+
                                 |                              |
                                 v                              v
                        +----------------+            +------------------+
                        |    Usuarios    |            | Version estable  |
                        |                |            | recibe el 100%   |
                        +----------------+            +------------------+
                                                               |
                                                               v
                                                      +------------------+
                                                      |    Operador      |
                                                      |   (diagnostica)  |
                                                      +------------------+
```

---

## 3. Los cinco puntos de validación

Un cambio defectuoso puede detenerse en cinco lugares distintos. Cada uno
atrapa una clase de problema que los anteriores no pueden ver.

| Punto | Qué valida | Si falla |
|---|---|---|
| P1 | La lógica del código es correcta | No se construye el artefacto |
| P2 | El empaquetado es válido y coherente | No se construye el artefacto |
| P3 | No hay vulnerabilidades críticas conocidas | El artefacto no se publica ni se firma |
| P4 | El despliegue cumple las normas del entorno | Se rechaza la admisión |
| P5 | La versión funciona con tráfico real | Reversión automática |

### Por qué hacen falta los cinco

Los cuatro primeros ocurren **antes** de que la versión reciba tráfico. Son
baratos y rápidos, pero comparten una limitación: analizan el artefacto en
reposo. Ninguno puede responder a la pregunta que de verdad importa —¿funciona
esto cuando lo usan personas?— porque para responderla hay que ejecutarlo.

El quinto punto es el único que observa la versión **en funcionamiento**, y por
eso es el único capaz de detectar una regresión de rendimiento, una dependencia
que responde distinto en el entorno real o una función que falla solo con
ciertos datos.

A la inversa: el quinto punto es el más caro, porque expone tráfico real a la
versión candidata. Los cuatro anteriores existen precisamente para que llegue
allí lo menos posible.

---

## 4. Detalle de la promoción por etapas

El componente expuesto al exterior es el único que se promueve por etapas. Es
la puerta de entrada del sistema, de modo que una versión defectuosa allí
afecta a la totalidad de los usuarios; el resto de componentes se actualizan de
forma convencional.

```
   ESTADO INICIAL
   +-----------------------------------------------+
   |  Version estable . . . . . . . . . . . 100%   |
   +-----------------------------------------------+

   ETAPA 1                      analisis --> desfavorable --+
   +-----------------------------------------------+        |
   |  Version estable . . . . . . . . . . .  80%   |        |
   |  Version candidata . . . . . . . . . .  20%   |        |
   +-----------------------------------------------+        |
                    |  favorable                            |
                    v                                       |
   ETAPA 2                      analisis --> desfavorable --+
   +-----------------------------------------------+        |
   |  Version estable . . . . . . . . . . .  50%   |        |
   |  Version candidata . . . . . . . . . .  50%   |        |
   +-----------------------------------------------+        |
                    |  favorable                            |
                    v                                       |
   ETAPA 3                      analisis --> desfavorable --+
   +-----------------------------------------------+        |
   |  Version estable . . . . . . . . . . .  20%   |        |
   |  Version candidata . . . . . . . . . .  80%   |        |
   +-----------------------------------------------+        |
                    |  favorable                            |
                    v                                       v
   PROMOCION                                    REVERSION AUTOMATICA
   +---------------------------+                +---------------------------+
   | Candidata . . . . . 100%  |                | Estable . . . . . . 100%  |
   | Pasa a ser la estable     |                | Candidata retirada        |
   +---------------------------+                +---------------------------+
```

### Qué se mide en cada análisis

| Prueba | Pregunta que responde | Frecuencia |
|---|---|---|
| Disponibilidad | ¿El componente responde y se declara operativo? | Cada 20 s |
| Funcionalidad | ¿Los servicios esenciales devuelven resultados válidos? | Cada 20 s |
| Rendimiento | ¿Se sostiene bajo concurrencia? | Cada 60 s |

Las tres son necesarias, y la razón se comprueba con el defecto que se induce
deliberadamente en esta práctica: **un componente puede estar operativo y aun
así devolver errores en su función principal.** Sus comprobaciones de
disponibilidad pasan, figura como sano, y sin embargo ningún usuario puede
usarlo. Solo la prueba de funcionalidad lo detecta.

Un análisis que se limitara a la comprobación más barata promovería esa versión
a la totalidad de los usuarios.

### Umbrales que deciden

| Medida | Umbral | Fundamento |
|---|---|---|
| Proporción de errores | Menor al 1% | En condiciones normales es nula. El margen cubre un reinicio puntual, no un fallo sistemático |
| Tiempo de respuesta (percentil 95) | Menor a 500 ms | El valor observado en condiciones normales es inferior a 200 ms. El doble de holgura evita reversiones por variabilidad del entorno |

Se usa el percentil 95 y no el promedio porque el promedio oculta los casos
extremos: si de cada cien peticiones noventa y cinco tardan 50 ms y cinco tardan
cinco segundos, el promedio resulta aceptable mientras uno de cada veinte
usuarios espera cinco segundos.

---

## 5. Recorrido de la reversión

La reversión no requiere intervención humana ni acceso al entorno.

```
  1. El análisis detecta que se superó un umbral
                    |
                    v
  2. El controlador de promoción detiene el avance
                    |
                    v
  3. Se retira el reparto de tráfico hacia la versión candidata
                    |
                    v
  4. La versión estable vuelve a recibir la totalidad del tráfico
                    |
                    v
  5. Los recursos de la versión candidata se retiran
                    |
                    v
  6. El estado queda registrado para su consulta posterior
```

El tráfico afectado durante todo el incidente es, como máximo, el porcentaje de
la etapa en que se detectó el problema. Si el defecto se detecta en la primera
etapa, ochenta de cada cien usuarios nunca llegaron a ver la versión defectuosa.

Comparado con el modelo de la práctica anterior —en el que la versión nueva
sustituía a la anterior de una vez— la diferencia es que allí el cien por cien
de los usuarios recibía el cambio antes de que nadie pudiera comprobar si
funcionaba.

---

## 6. Separación de responsabilidades

El punto central del diseño es que ningún componente concentra la capacidad de
alterar el entorno productivo.

| Componente | Puede | No puede |
|---|---|---|
| Automatización de construcción | Proponer un cambio de versión | Aplicar nada al entorno |
| Repositorio de declaración | Registrar el estado deseado | Actuar por sí mismo |
| Motor de declaración | Aplicar lo que el repositorio declara | Inventar un estado no declarado |
| Motor de admisión | Rechazar lo no conforme | Modificar lo que admite |
| Controlador de promoción | Avanzar o revertir | Alterar el contenido de la versión |

En el modelo de la práctica anterior, la automatización de construcción poseía
credenciales de administración del entorno. Comprometer el repositorio de código
equivalía a comprometer la infraestructura completa.

En este modelo, la automatización no posee ninguna credencial del entorno. Su
capacidad máxima es modificar una línea en una propuesta de cambio, que a su
vez debe ser aprobada, admitida por el motor de normas y validada por el
análisis progresivo antes de alcanzar a la totalidad de los usuarios.

---

## 7. Detección de desviaciones

El motor de declaración compara de forma continua lo declarado en el
repositorio con lo que existe realmente en el entorno.

```
   +------------------+          compara          +------------------+
   |   Declarado      |<------------------------->|      Real        |
   |  (repositorio)   |                           |    (entorno)     |
   +------------------+                           +------------------+
                                  |
                 +----------------+----------------+
                 |                                 |
            coinciden                        difieren
                 |                                 |
                 v                                 v
        +------------------+           +--------------------------+
        |  Estado: SANO    |           |  Se restablece lo        |
        |  No se actúa     |           |  declarado y se registra |
        +------------------+           +--------------------------+
```

Esto resuelve la tercera debilidad señalada en el enunciado: *el estado real
puede diferir del declarado y nadie lo detecta*. Con esta comparación continua,
no solo se detecta: se corrige de forma automática, y cualquier modificación
manual queda deshecha y registrada.
