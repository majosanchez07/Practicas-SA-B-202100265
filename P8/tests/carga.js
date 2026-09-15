/**
 * ============================================================================
 * Prueba de carga — Practica 8
 * Maria Jose Tebalan Sanchez — 202100265
 *
 * En que se diferencia de la prueba de carga de la Practica 5
 * -----------------------------------------------------------
 * La de la P5 tenia un objetivo distinto: provocar el escalado del HPA. Subia
 * hasta 100 usuarios virtuales en escalones y observaba como crecia el numero
 * de replicas. Sus umbrales eran generosos a proposito (p95 < 2000 ms), porque
 * el objetivo era estresar el sistema, no juzgarlo.
 *
 * Esta prueba juzga. Sus umbrales son el criterio que decide si una version se
 * promueve o se revierte, de modo que tienen que estar calibrados para
 * distinguir una regresion real del ruido normal del entorno.
 *
 * ----------------------------------------------------------------------------
 * JUSTIFICACION DE LOS UMBRALES (la rubrica pide justificarlos)
 * ----------------------------------------------------------------------------
 *
 * Tasa de error < 1%  (http_req_failed: rate<0.01)
 *
 *     El sistema de las Practicas 5 a 7 no tiene ninguna fuente conocida de
 *     error intermitente: en condiciones normales la tasa observada es 0%.
 *
 *     El 1% NO significa "se tolera un poco de error". Significa: durante una
 *     ventana de medicion de 60 segundos puede ocurrir un reinicio de pod, una
 *     conexion cortada por el balanceador o un timeout puntual de red. Con
 *     unas 600 peticiones por ventana, el 1% deja margen para unas 6 de esas
 *     anomalias. Una version que falla de forma sistematica supera ese margen
 *     de inmediato.
 *
 * Latencia p95 < 500 ms  (http_req_duration: p(95)<500)
 *
 *     Medido sobre el despliegue de la Practica 5: el p95 del api-gateway con
 *     carga moderada se situaba por debajo de 200 ms.
 *
 *     El umbral se fija en 500 ms, mas del doble del valor observado. Esa
 *     holgura es deliberada: un umbral de 250 ms saltaria por la variabilidad
 *     normal de un entorno compartido -un vecino ruidoso en el nodo, el
 *     calentamiento de la JIT, una consulta que no estaba en cache- y
 *     provocaria reversiones de versiones sanas. Un equipo que ve revertirse
 *     despliegues correctos aprende a desconfiar del mecanismo y acaba
 *     desactivandolo.
 *
 *     A la vez, 500 ms es lo bastante estricto para detectar una regresion
 *     real: una consulta sin indice, una llamada sincrona anadida en el camino
 *     critico o un bucle de reintentos multiplican la latencia, no la aumentan
 *     un 20%.
 *
 * Por que el p95 y no la media
 *
 *     La media esconde los casos malos. Si 95 peticiones tardan 50 ms y 5
 *     tardan 5 segundos, la media es 297 ms -aparentemente correcta- mientras
 *     que uno de cada veinte usuarios espera cinco segundos. El p95 expone
 *     justamente esa cola.
 *
 * ----------------------------------------------------------------------------
 * Uso
 * ----------------------------------------------------------------------------
 *   k6 run carga.js
 *   k6 run -e BASE_URL=http://mi-gateway:8080 carga.js
 *   k6 run -e VUS=10 -e DURACION=2m carga.js
 *
 * k6 devuelve codigo 99 cuando un threshold no se cumple. Ese codigo distinto
 * de cero es lo que hace fallar el Job del AnalysisTemplate y, con el, aborta
 * la promocion del canary.
 * ============================================================================
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const VUS = parseInt(__ENV.VUS || '10', 10);
const DURACION = __ENV.DURACION || '1m';

// Metricas propias, ademas de las que k6 calcula por defecto.
const erroresNegocio = new Rate('errores_de_negocio');
const latenciaCatalogo = new Trend('latencia_catalogo', true);
const latenciaSalud = new Trend('latencia_salud', true);
const peticionesLentas = new Counter('peticiones_sobre_500ms');

export const options = {
  scenarios: {
    // Carga constante, no escalonada. A diferencia de la P5 -que buscaba
    // disparar el HPA con escalones crecientes-, aqui interesa una medicion
    // estable y comparable entre versiones: si la carga variara durante la
    // prueba, no se podria saber si una latencia alta se debe a la version
    // candidata o al escalon en que se midio.
    constante: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURACION,
    },
  },

  thresholds: {
    // LOS DOS UMBRALES QUE DECIDEN LA PROMOCION. Ver la justificacion arriba.
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500'],

    // Umbrales por endpoint: permiten saber CUAL se degrado, no solo que algo
    // se degrado. Sin esto, un p95 global alto obliga a investigar a ciegas.
    'latencia_catalogo': ['p(95)<800'],
    'latencia_salud': ['p(95)<200'],

    // Los errores de negocio se miden aparte de los de transporte: un 500 y
    // una respuesta 200 con contenido invalido son fallos distintos.
    'errores_de_negocio': ['rate<0.01'],
  },

  // No se aborta ante el primer fallo de umbral: interesa completar la ventana
  // para tener la medicion completa en el reporte.
  noConnectionReuse: false,
  insecureSkipTLSVerify: true,
};

const params = {
  headers: { 'Content-Type': 'application/json' },
  timeout: '10s',
};

export default function () {
  // --------------------------------------------------------------------------
  // 1. Endpoint de salud — el mas ligero, se consulta en cada iteracion.
  // --------------------------------------------------------------------------
  const salud = http.get(`${BASE_URL}/health/ready`, params);
  latenciaSalud.add(salud.timings.duration);
  const saludOk = check(salud, {
    'salud responde 200': (r) => r.status === 200,
  });
  erroresNegocio.add(!saludOk);
  if (salud.timings.duration > 500) peticionesLentas.add(1);

  // --------------------------------------------------------------------------
  // 2. Catalogo de libros — atraviesa el gateway hasta books-service y toca la
  //    base de datos. Es la ruta que mas revela una regresion de rendimiento.
  //
  //    Se consulta en una de cada tres iteraciones: es mas cara que la de
  //    salud y saturarla distorsionaria la medicion de las demas.
  // --------------------------------------------------------------------------
  if (__ITER % 3 === 0) {
    const catalogo = http.get(`${BASE_URL}/api/books`, params);
    latenciaCatalogo.add(catalogo.timings.duration);

    const catalogoOk = check(catalogo, {
      'catalogo responde 200': (r) => r.status === 200,
      // Un 200 con cuerpo vacio no es una respuesta correcta: se comprueba que
      // devuelve algo parseable, no solo que el codigo es 200.
      'catalogo devuelve JSON': (r) => {
        try {
          return r.json() !== null;
        } catch (e) {
          return false;
        }
      },
    });
    erroresNegocio.add(!catalogoOk);
    if (catalogo.timings.duration > 500) peticionesLentas.add(1);
  }

  // Pausa breve entre iteraciones: sin ella, cada usuario virtual generaria
  // peticiones en bucle cerrado, lo que mide la capacidad maxima del servidor
  // pero no se parece al comportamiento de un usuario real.
  sleep(0.2);
}

// ============================================================================
// Reporte
// ============================================================================
export function handleSummary(data) {
  const m = data.metrics;
  const v = (metrica, campo, def = 0) =>
    m[metrica] && m[metrica].values[campo] !== undefined ? m[metrica].values[campo] : def;

  const p95 = v('http_req_duration', 'p(95)');
  const errRate = v('http_req_failed', 'rate') * 100;
  const total = v('http_reqs', 'count');

  // Se recalculan los veredictos aqui para que el resumen legible diga
  // explicitamente si la version se promoveria o se revertiria.
  const pasaError = errRate < 1.0;
  const pasaLatencia = p95 < 500;
  const veredicto = pasaError && pasaLatencia ? 'PROMOVER' : 'REVERTIR';

  const resumen = `
=================================================================
  PRUEBA DE CARGA — Practica 8 — Carne 202100265
=================================================================
  Destino            : ${BASE_URL}
  Usuarios virtuales : ${VUS}
  Duracion           : ${DURACION}
  Fecha              : ${new Date().toISOString()}

  ---------------------------------------------------------------
  RESULTADOS
  ---------------------------------------------------------------
  Peticiones totales : ${total}
  Peticiones/segundo : ${v('http_reqs', 'rate').toFixed(2)} RPS
  Latencia media     : ${v('http_req_duration', 'avg').toFixed(2)} ms
  Latencia p90       : ${v('http_req_duration', 'p(90)').toFixed(2)} ms
  Latencia p95       : ${p95.toFixed(2)} ms
  Latencia maxima    : ${v('http_req_duration', 'max').toFixed(2)} ms
  Tasa de error      : ${errRate.toFixed(3)} %
  Sobre 500 ms       : ${v('peticiones_sobre_500ms', 'count')}

  Por endpoint:
    /health/ready p95: ${v('latencia_salud', 'p(95)').toFixed(2)} ms
    /api/books    p95: ${v('latencia_catalogo', 'p(95)').toFixed(2)} ms

  ---------------------------------------------------------------
  UMBRALES DE PROMOCION
  ---------------------------------------------------------------
  Tasa de error < 1%     : ${pasaError ? 'CUMPLE' : 'NO CUMPLE'}  (${errRate.toFixed(3)}%)
  Latencia p95  < 500 ms : ${pasaLatencia ? 'CUMPLE' : 'NO CUMPLE'}  (${p95.toFixed(2)} ms)

  VEREDICTO: ${veredicto}
=================================================================
`;

  return {
    stdout: resumen,
    'reporte-carga.json': JSON.stringify(data, null, 2),
    'reporte-carga.txt': resumen,
  };
}
