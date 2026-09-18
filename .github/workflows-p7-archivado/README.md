# Pipeline archivado de la Práctica 7

Este directorio contiene el pipeline de la Práctica 7, ya calificada. **No se
ejecuta**: GitHub Actions solo lee los archivos que están directamente en
`.github/workflows/`.

## Por qué se movió

La Práctica 8 establece como requisito eliminatorio que ningún flujo de trabajo
aplique cambios directamente al entorno ni almacene credenciales de acceso.

El pipeline de la Práctica 7 sí desplegaba directamente, y eso era correcto en
aquel momento: el modelo de aquella práctica era precisamente ése. Pero la
verificación de la Práctica 8 revisa el directorio completo, sin distinguir a
qué práctica pertenece cada archivo.

Se conserva aquí por dos razones:

1. Es la evidencia de la Práctica 7, que forma parte del historial del
   repositorio.
2. Permite comparar ambos modelos, que es justamente el objeto de la
   Práctica 8: el de la 7 empuja los cambios hacia el entorno; el de la 8
   propone un cambio y espera a que el entorno lo tome.

## Cómo reactivarlo

Moverlo de vuelta a `.github/workflows/`. Hacerlo mientras la Práctica 8 esté
en evaluación provocaría que su requisito eliminatorio no se cumpla.
