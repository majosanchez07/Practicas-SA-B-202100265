# Informe de incidente

Práctica 8 — María José Tebalán Sánchez — 202100265

**Versión afectada:** 1.0.2
**Versión estable de retorno:** 1.0.1
**Fecha:** 18 de septiembre de 2026, 07:26:56 – 07:28:02

> Los tiempos y porcentajes de este informe son los medidos durante la
> ejecución real sobre el entorno desplegado, no estimaciones.

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

Resultados registrados por el análisis durante el incidente:

| Prueba del análisis | Resultado | Qué significa |
|---|---|---|
| Disponibilidad | **Superada** (2 éxitos) | El componente estaba vivo y respondía |
| Rendimiento | **Superada** (1 éxito) | Respondía dentro de los umbrales de latencia |
| **Funcionalidad** | **Fallida** (1 fallo) | El servicio esencial devolvía error |

Este es el dato central del incidente y no una hipótesis: dos de las tres
pruebas dieron por buena la versión defectuosa. El componente arrancó, superó
sus comprobaciones de estado, figuró como disponible y respondió con baja
latencia. **Solo la prueba que ejecuta la función real la detectó.**

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

**Tráfico afectado:** el veinte por ciento durante veinticuatro segundos —el
intervalo entre alcanzar la primera etapa (07:27:38) y abortar (07:28:02)—.
Ochenta de cada cien usuarios nunca fueron dirigidos a la versión defectuosa, y
la promoción no llegó a avanzar a la segunda etapa.

**Comparación con el modelo anterior:** en la práctica precedente, la versión
nueva sustituía a la anterior en una sola operación. El cien por cien de los
usuarios habría recibido la versión defectuosa, y habría permanecido así hasta
que una persona lo advirtiera y ejecutara manualmente la reversión.

---

## 4. Tiempo de recuperación

| Momento | Hora | Tiempo acumulado |
|---|---|---|
| Se publica la versión defectuosa | 07:26:56 | 0 s |
| El controlador inicia la promoción | 07:27:15 | 19 s |
| Primera etapa alcanzada: 20% del tráfico | 07:27:38 | 42 s |
| El análisis detecta el resultado desfavorable | 07:28:02 | 66 s |
| El tráfico vuelve íntegro a la versión estable | 07:28:02 | 66 s |

**Tiempo total de recuperación: 66 segundos.**

El mensaje registrado por el controlador fue:

```
RolloutAborted: Rollout aborted update to revision 4:
Metric "prueba-integracion" assessed Failed due to failed (1) > failureLimit (0)
```

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
