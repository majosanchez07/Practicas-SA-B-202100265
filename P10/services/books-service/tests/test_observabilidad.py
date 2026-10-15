"""
Pruebas de la observabilidad de la Practica 10.

Se ejercita la app real con TestClient y OTEL_SDK_DISABLED, de modo que no se
necesita Collector: lo que se verifica es el formato de los registros, la
agrupacion de rutas y que el fallo inducido este apagado por defecto.
"""
import json
import logging

from src import observabilidad


def test_ruta_de_agrupa_por_prefijo():
    assert observabilidad.ruta_de("/graphql") == "/graphql"
    assert observabilidad.ruta_de("/graphql/algo?x=1") == "/graphql"
    assert observabilidad.ruta_de("/") == "/"


def test_registro_es_json_con_campos():
    registro = logging.LogRecord("books-service", logging.ERROR, __file__, 1, "fallo", None, None)
    registro.campos = {"status_code": 503}
    linea = json.loads(observabilidad.FormatoJSON().format(registro))
    assert linea["level"] == "error"
    assert linea["message"] == "fallo"
    assert linea["status_code"] == 503
    assert linea["service"] == "books-service"
    # Sin span activo no se inventa un trace_id.
    assert "trace_id" not in linea


def test_registro_incluye_trace_id_dentro_de_un_span(monkeypatch):
    # El conftest apaga el SDK; esta prueba necesita un span real.
    monkeypatch.setenv("OTEL_SDK_DISABLED", "false")
    from opentelemetry.sdk.trace import TracerProvider

    tracer = TracerProvider().get_tracer("prueba")
    with tracer.start_as_current_span("op") as span:
        registro = logging.LogRecord("x", logging.INFO, __file__, 1, "m", None, None)
        linea = json.loads(observabilidad.FormatoJSON().format(registro))
    assert linea["trace_id"] == format(span.get_span_context().trace_id, "032x")


def test_fallo_inducido_apagado_por_defecto():
    assert observabilidad.FALLO_ACTIVO is False
