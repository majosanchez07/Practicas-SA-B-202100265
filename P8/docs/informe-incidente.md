# Informe de incidente

Práctica 8 — María José Tebalán Sánchez — 202100265

**Versión afectada:** 1.0.1
**Versión estable de retorno:** 1.0.0
**Fecha:** _(se completa al ejecutar la demostración)_

> Los tiempos y porcentajes de este informe se completan con los datos reales
> de la ejecución. La estructura y el análisis corresponden al defecto que se
> introduce deliberadamente y al comportamiento esperado del mecanismo de
> contención, verificado previamente contra un simulador del componente.

---

## 1. Qué falló

Se introdujo deliberadamente un defecto en el componente expuesto al exterior:
el servicio de consulta del catálogo devuelve un error del servidor en lugar de
la lista de elementos.

El defecto se eligió con un criterio concreto: **debía ser invisible para las
comprobaciones de disponibilidad.** El componente arranca con normalidad,
responde a las comprobaciones de estado, se declara operativo y su instancia
figura como disponible. Un observador que solo mirara el estado de las
instancias concluiría que el despliegue fue correcto.

Sin embargo, la función principal del sistema —consultar el catálogo— no
funciona para ningún usuario.

Esa elección no es casual. Un defecto evidente, como un componente que no
arranca, sería detenido por las comprobaciones de arranque antes de recibir
tráfico, y no demostraría nada sobre el análisis progresivo. El defecto elegido
solo puede detectarse ejecutando la función real del componente.

---

## 2. Cómo se detectó

**Validación que lo identificó:** la prueba de funcionalidad del análisis
progresivo, en la primera etapa de la promoción.

**Umbral superado:** la comprobación del servicio de catálogo esperaba una
respuesta correcta y recibió un error del servidor. El análisis está
configurado con cero fallos tolerados, de modo que una sola comprobación
fallida aborta la promoción.

**Lo que no lo detectó, y por qué importa:**

| Validación | Resultado | Motivo |
|---|---|---|
| Comprobación de arranque | Superada | El componente arranca correctamente |
| Comprobación de vitalidad | Superada | El proceso responde |
| Comprobación de disponibilidad | Superada | El componente se declara listo |
| Prueba de disponibilidad del análisis | Superada | Los puntos de estado responden |
| **Prueba de funcionalidad del análisis** | **Fallida** | El servicio esencial devuelve error |

Este contraste se verificó de forma independiente antes de la demostración,
ejecutando las pruebas contra un simulador del componente en ambos estados. El
resultado confirmó que la prueba de disponibilidad concluye con éxito ante la
versión defectuosa, mientras que la de funcionalidad la detecta.

La conclusión operativa es que **un análisis limitado a comprobar
disponibilidad habría promovido esta versión a la totalidad de los usuarios.**

---

## 3. Cómo se contuvo

**Mecanismo:** el controlador de promoción, de forma autónoma y sin
intervención humana.

**Secuencia:**

1. La prueba de funcionalidad devuelve un resultado desfavorable.
2. El controlador detiene el avance de la promoción.
3. Se retira el reparto de tráfico hacia la versión candidata.
4. La versión estable vuelve a recibir la totalidad del tráfico.
5. Los recursos de la versión candidata se retiran.
6. El estado queda registrado para consulta posterior.

**Tráfico afectado:** como máximo el veinte por ciento, correspondiente a la
primera etapa de la promoción. Ochenta de cada cien usuarios nunca fueron
dirigidos a la versión defectuosa.

**Comparación con el modelo anterior:** en la práctica precedente, la versión
nueva sustituía a la anterior en una sola operación. El cien por cien de los
usuarios habría recibido la versión defectuosa, y habría permanecido así hasta
que una persona lo advirtiera y ejecutara manualmente la reversión.

---

## 4. Tiempo de recuperación

| Momento | Tiempo acumulado |
|---|---|
| Se integra la propuesta de promoción | 0 |
| El componente interno detecta el cambio y sincroniza | _(pendiente)_ |
| Comienza la primera etapa de la promoción | _(pendiente)_ |
| El análisis ejecuta la prueba de funcionalidad | _(pendiente)_ |
| Se detecta el resultado desfavorable | _(pendiente)_ |
| El tráfico vuelve íntegro a la versión estable | _(pendiente)_ |

**Tiempo total estimado:** entre uno y dos minutos, determinado por el intervalo
de comprobación del componente interno y por la frecuencia del análisis, que es
de veinte segundos.

Ninguna persona intervino en la detección ni en la contención. El tiempo de
recuperación no depende de que alguien esté disponible, revisando registros o
atendiendo una alerta.

---

## 5. Cómo prevenirlo

El defecto llegó a la etapa de promoción porque **ninguna validación previa
ejecutaba la función real del componente.** Las pruebas unitarias comprueban
piezas aisladas; el análisis de vulnerabilidades examina el artefacto en
reposo; las normas de admisión verifican la forma del despliegue, no su
comportamiento.

**Control adicional propuesto:** ejecutar las pruebas de funcionalidad contra
el artefacto ya construido, en un entorno desechable, antes de proponer la
promoción.

Concretamente: levantar el componente junto con sus dependencias en un entorno
efímero dentro de la propia automatización, ejecutar contra él las mismas
pruebas de funcionalidad que usa el análisis progresivo, y bloquear la
propuesta si fallan.

**Por qué este control y no otro:**

- Es el mismo conjunto de pruebas que ya existe, reutilizado antes en la
  cadena. No requiere escribir pruebas nuevas ni mantener dos definiciones de
  lo que significa "funciona".
- Se ejecuta sin exponer tráfico a ningún usuario.
- Traslada la detección desde un punto donde ya hay usuarios afectados hasta
  otro donde no hay ninguno.

**Lo que este control no resolvería:** un defecto que solo se manifieste con
datos reales o bajo carga sostenida seguiría llegando a la etapa de promoción.
Por eso el control propuesto complementa al análisis progresivo en lugar de
sustituirlo: cada uno detecta una clase distinta de problema, y el análisis
progresivo sigue siendo la última línea de contención.
