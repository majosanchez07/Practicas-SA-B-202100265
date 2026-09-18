/**
 * Prueba de carga contra el API Gateway — Práctica 5, Software Avanzado
 * Carné 202100265
 *
 * Objetivo: someter al gateway a una concurrencia creciente para provocar el
 * escalado automático del HPA, y comprobar después el descenso de réplicas al
 * cesar la carga.
 *
 * Uso:
 *   k6 run carga.js
 *   k6 run -e BASE_URL=http://127.0.0.1 -e HOST=sa-p5.local carga.js
 *
 * El tráfico entra por el Ingress, que es la única puerta de entrada al
 * clúster; no se golpea ningún microservicio directamente.
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1';
const HOST = __ENV.HOST || 'sa-p5.local';

// Métricas propias, además de las que k6 calcula por defecto.
const erroresRate = new Rate('errores_totales');
const latenciaRaiz = new Trend('latencia_raiz', true);

export const options = {
  // Concurrencia creciente por escalones: cada tramo da tiempo al HPA a
  // observar el consumo y decidir, en lugar de un pico instantáneo que
  // terminaría antes de que el autoescalado reaccione.
  stages: [
    { duration: '30s', target: 10 },   // calentamiento
    { duration: '45s', target: 30 },   // primer escalón
    { duration: '60s', target: 60 },   // segundo escalón: debería disparar el HPA
    { duration: '60s', target: 100 },  // tercer escalón: carga sostenida alta
    { duration: '30s', target: 0 },    // descenso, para observar el scale down
  ],

  thresholds: {
    // El servicio debe seguir respondiendo correctamente bajo carga.
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2000'],
  },

  // El Ingress local usa un certificado propio; no aplica aquí porque se
  // trabaja sobre HTTP, pero se deja explícito.
  insecureSkipTLSVerify: true,
};

const params = {
  headers: {
    Host: HOST,
    'Content-Type': 'application/json',
  },
  timeout: '10s',
};

export default function () {
  // Petición principal: la raíz del gateway. Es la que mide la capacidad de
  // atención del propio gateway, que es el Deployment gobernado por el HPA.
  const res = http.get(`${BASE_URL}/`, params);

  const ok = check(res, {
    'status 200': (r) => r.status === 200,
    'responde el gateway': (r) => r.body && r.body.includes('API Gateway'),
  });

  erroresRate.add(!ok);
  latenciaRaiz.add(res.timings.duration);

  // Una parte del tráfico atraviesa el gateway hacia un microservicio, para
  // que la prueba ejercite también el enrutamiento y no solo la raíz.
  if (__ITER % 4 === 0) {
    const health = http.get(`${BASE_URL}/loans/health/live`, params);
    check(health, { 'proxy hacia loans 200': (r) => r.status === 200 });
    erroresRate.add(health.status !== 200);
  }

  sleep(0.1);
}

export function handleSummary(data) {
  const m = data.metrics;
  const rps = m.http_reqs ? m.http_reqs.values.rate : 0;
  const p95 = m.http_req_duration ? m.http_req_duration.values['p(95)'] : 0;
  const errRate = m.http_req_failed ? m.http_req_failed.values.rate * 100 : 0;

  const resumen = `
=========================================================
  RESULTADOS DE LA PRUEBA DE CARGA — Carné 202100265
=========================================================
  Peticiones totales : ${m.http_reqs ? m.http_reqs.values.count : 0}
  Peticiones/segundo : ${rps.toFixed(2)} RPS
  Latencia media     : ${m.http_req_duration ? m.http_req_duration.values.avg.toFixed(2) : 0} ms
  Latencia p95       : ${p95.toFixed(2)} ms
  Latencia máxima    : ${m.http_req_duration ? m.http_req_duration.values.max.toFixed(2) : 0} ms
  Tasa de error      : ${errRate.toFixed(2)} %
  VUs máximos        : ${m.vus_max ? m.vus_max.values.max : 0}
=========================================================
`;

  return {
    stdout: resumen,
    'resultado-carga.json': JSON.stringify(data, null, 2),
  };
}
