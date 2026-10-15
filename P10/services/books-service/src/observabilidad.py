"""
Observabilidad de books-service — Practica 10.

Concentra los tres pilares en un solo modulo para que main.py solo tenga que
llamar a configurar(app, engine):

  Trazas    FastAPI y SQLAlchemy instrumentados. El span de FastAPI CONTINUA la
            traza que inicia el gateway: el traceparent llega en la cabecera
            de la peticion que reenvia loans-service.
  Metricas  sa_http_requests_total y sa_http_request_duration_seconds con los
            mismos nombres que los servicios en Node, de modo que una sola
            consulta del tablero cubre a los tres; y la metrica de negocio
            biblioteca_libros_consultados_total.
  Registros JSON por stdout con trace_id y span_id tomados del span activo.

Todo sale por OTLP hacia el Collector (OTEL_EXPORTER_OTLP_ENDPOINT).
"""
import asyncio
import json
import logging
import os
import random
import sys
import time
from datetime import datetime, timezone

from fastapi.responses import JSONResponse
from opentelemetry import metrics, trace

SERVICIO = os.getenv("OTEL_SERVICE_NAME", "books-service")
RUTAS_IGNORADAS = ("/health", "/metrics")


# ------------------------------------------------------------------------------
# Registros estructurados
# ------------------------------------------------------------------------------
class FormatoJSON(logging.Formatter):
    """Una linea JSON por evento, con el identificador de traza si existe."""

    def format(self, record):
        linea = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "level": record.levelname.lower(),
            "service": SERVICIO,
            "logger": record.name,
            "message": record.getMessage(),
        }
        linea.update(getattr(record, "campos", {}) or {})

        ctx = trace.get_current_span().get_span_context()
        if ctx.is_valid:
            linea["trace_id"] = format(ctx.trace_id, "032x")
            linea["span_id"] = format(ctx.span_id, "016x")

        if record.exc_info:
            linea["exception"] = self.formatException(record.exc_info)
        return json.dumps(linea, ensure_ascii=False)


def configurar_registros():
    manejador = logging.StreamHandler(sys.stdout)
    manejador.setFormatter(FormatoJSON())
    nivel = os.getenv("LOG_LEVEL", "info").upper()
    raiz = logging.getLogger()
    raiz.handlers = [manejador]
    raiz.setLevel(nivel)
    # uvicorn trae su propio formato de texto; se redirige al JSON para que
    # Loki no reciba dos formatos distintos del mismo contenedor. El registro
    # de acceso se apaga: lo sustituyen las metricas y las trazas.
    for nombre in ("uvicorn", "uvicorn.error"):
        logging.getLogger(nombre).handlers = []
        logging.getLogger(nombre).propagate = True
    logging.getLogger("uvicorn.access").disabled = True


log = logging.getLogger("books-service")


def registrar(nivel, mensaje, **campos):
    log.log(nivel, mensaje, extra={"campos": campos})


# ------------------------------------------------------------------------------
# Metricas
# ------------------------------------------------------------------------------
_medidor = metrics.get_meter("books-service")
_peticiones = _medidor.create_counter("sa_http_requests", description="Peticiones HTTP atendidas")
_duracion = _medidor.create_histogram(
    "sa_http_request_duration_seconds", description="Duracion de las peticiones HTTP en segundos"
)
_consultados = _medidor.create_counter(
    "biblioteca_libros_consultados", description="Consultas al catalogo de libros"
)


def libro_consultado(encontrado: bool):
    _consultados.add(1, {"resultado": "encontrado" if encontrado else "no_encontrado"})


def ruta_de(path: str) -> str:
    segmento = (path or "/").split("?")[0].strip("/").split("/")[0]
    return f"/{segmento}" if segmento else "/"


# ------------------------------------------------------------------------------
# Fallo inducido (recorrido sintoma -> causa)
#
# books-service no es un Rollout, de modo que su fallo no lo contiene el
# canary: llega a todos los usuarios y es el que debe detectar la alerta por
# consumo del presupuesto de error. Se enciende con FALLO_LATENCIA_MS y
# FALLO_TASA_ERROR desde el repositorio GitOps; sin ellas no hace nada.
# ------------------------------------------------------------------------------
FALLO_LATENCIA_MS = int(os.getenv("FALLO_LATENCIA_MS", "0"))
FALLO_TASA_ERROR = float(os.getenv("FALLO_TASA_ERROR", "0"))


FALLO_ACTIVO = FALLO_LATENCIA_MS > 0 or FALLO_TASA_ERROR > 0


def configurar(app, engine):
    configurar_registros()

    if os.getenv("OTEL_SDK_DISABLED", "false").lower() != "true":
        from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
        from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
        from opentelemetry.sdk.metrics import MeterProvider
        from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
        from opentelemetry.sdk.metrics.view import ExplicitBucketHistogramAggregation, View
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor

        recurso = Resource.create({
            "service.name": SERVICIO,
            "service.namespace": "biblioteca",
            "service.version": os.getenv("SERVICE_VERSION", "dev"),
            "rollout.hash": os.getenv("ROLLOUT_HASH", "none"),
        })
        proveedor = TracerProvider(resource=recurso)
        proveedor.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
        trace.set_tracer_provider(proveedor)
        # Los cubos por defecto del SDK de Python estan pensados en
        # milisegundos (5, 10, 25...); en segundos todo caeria en el primero.
        cubos = View(
            instrument_name="sa_http_request_duration_seconds",
            aggregation=ExplicitBucketHistogramAggregation(
                [0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 0.75, 1, 2, 5]),
        )
        # Los instrumentos de arriba se crearon con el proveedor vacio de la
        # API; son proxies que empiezan a registrar en cuanto este se instala.
        metrics.set_meter_provider(MeterProvider(
            resource=recurso,
            views=[cubos],
            metric_readers=[PeriodicExportingMetricReader(OTLPMetricExporter(), export_interval_millis=10000)],
        ))

        SQLAlchemyInstrumentor().instrument(engine=engine)

    @app.middleware("http")
    async def fallo_inducido(request, call_next):
        if not FALLO_ACTIVO or not request.url.path.startswith("/graphql"):
            return await call_next(request)
        if FALLO_LATENCIA_MS > 0:
            await asyncio.sleep(FALLO_LATENCIA_MS / 1000)
        if random.random() < FALLO_TASA_ERROR:
            # Simula el agotamiento del pool de conexiones a la base: el
            # mensaje es el que veria quien opera el sistema, y causa deja
            # claro en Loki que el fallo fue deliberado.
            registrar(logging.ERROR, "pool de conexiones agotado: no se obtuvo conexion a la base de datos",
                      route="/graphql", status_code=503, espera_ms=FALLO_LATENCIA_MS,
                      causa="fallo-inducido-p10")
            return JSONResponse({"error": "catalogo no disponible"}, status_code=503)
        return await call_next(request)

    # Se registra despues para quedar POR FUERA del fallo: Starlette envuelve
    # en orden inverso, y asi la latencia y el 503 inducidos tambien se miden.
    @app.middleware("http")
    async def medir(request, call_next):
        if request.url.path.startswith(RUTAS_IGNORADAS):
            return await call_next(request)
        inicio = time.perf_counter()
        codigo = 500
        try:
            respuesta = await call_next(request)
            codigo = respuesta.status_code
            return respuesta
        finally:
            atributos = {"route": ruta_de(request.url.path), "method": request.method, "status_code": str(codigo)}
            _peticiones.add(1, atributos)
            _duracion.record(time.perf_counter() - inicio, atributos)

    # La instrumentacion de FastAPI se registra AL FINAL para quedar por fuera
    # de los dos middlewares anteriores: el 503 inducido ocurre dentro del span
    # del servidor, que lo marca como error, y su registro lleva trace_id.
    if os.getenv("OTEL_SDK_DISABLED", "false").lower() != "true":
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
        FastAPIInstrumentor.instrument_app(app, excluded_urls="health,metrics")

    registrar(logging.INFO, "books-service iniciado",
              fallo_inducido=FALLO_ACTIVO)
