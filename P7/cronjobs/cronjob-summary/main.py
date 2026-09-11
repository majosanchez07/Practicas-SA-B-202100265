"""
Cronjob 2 — Resumen de ejecuciones publicado en el broker.

Se ejecuta cada 10 minutos, consulta los registros generados por el Cronjob 1,
calcula cuantas ejecuciones hubo por hora y publica ese resumen como un mensaje
en RabbitMQ. El mensaje lo consume notifications-service, que lo almacena; con
eso queda cerrada la cadena que pide el enunciado:

    Cronjob 1 -> BD -> Cronjob 2 -> broker -> notifications-service -> BD

El mensaje se publica como persistente sobre un exchange durable, de modo que
si notifications-service esta caido el resumen se conserva en la cola hasta que
vuelva a levantarse.
"""
import json
import os
import sys
from datetime import datetime, timedelta, timezone

import pika
import psycopg
from psycopg import sql

GMT_MENOS_6 = timezone(timedelta(hours=-6))

DATABASE_URL = os.environ["DATABASE_URL"]
DB_SCHEMA = os.getenv("DB_SCHEMA", "cronjobs")
CARNE = os.environ["CARNE"]
TABLA = "ejecuciones"

# Se usa el nombre de la zona y no un desplazamiento literal: en la sintaxis
# POSIX que acepta PostgreSQL, "UTC-6" significa UTC+6, con lo que el resumen
# quedaria agrupado en la hora equivocada. America/Guatemala es GMT-6 fijo.
ZONA_HORARIA = os.getenv("TZ_REPORTE", "America/Guatemala")

RABBITMQ_URL = os.environ["RABBITMQ_URL"]
EXCHANGE = os.getenv("BROKER_EXCHANGE", "biblioteca.events")
ROUTING_KEY = os.getenv("BROKER_ROUTING_KEY_RESUMEN", "resumen.generado")


def calcular_resumen(conn):
    """Cantidad de ejecuciones agrupadas por hora, en GMT-6."""
    with conn.cursor() as cur:
        cur.execute(
            sql.SQL("""
                SELECT to_char(ejecutado_en AT TIME ZONE %s, 'YYYY-MM-DD HH24:00') AS hora,
                       COUNT(*) AS cantidad
                FROM {}.{}
                WHERE carne = %s
                GROUP BY hora
                ORDER BY hora
            """).format(sql.Identifier(DB_SCHEMA), sql.Identifier(TABLA)),
            (ZONA_HORARIA, CARNE),
        )
        filas = cur.fetchall()

    por_hora = [{"hora": h, "cantidad": c} for h, c in filas]
    total = sum(item["cantidad"] for item in por_hora)
    return por_hora, total


def publicar(por_hora, total):
    parametros = pika.URLParameters(RABBITMQ_URL)
    parametros.socket_timeout = 10
    parametros.connection_attempts = 5
    parametros.retry_delay = 3

    conexion = pika.BlockingConnection(parametros)
    try:
        canal = conexion.channel()
        canal.exchange_declare(exchange=EXCHANGE, exchange_type="topic", durable=True)

        mensaje = {
            "evento": ROUTING_KEY,
            "emitidoEn": datetime.now(GMT_MENOS_6).isoformat(),
            "origen": "cronjob-summary",
            "datos": {
                "carne": CARNE,
                "totalEjecuciones": total,
                "porHora": por_hora,
            },
        }

        canal.basic_publish(
            exchange=EXCHANGE,
            routing_key=ROUTING_KEY,
            body=json.dumps(mensaje).encode("utf-8"),
            properties=pika.BasicProperties(
                delivery_mode=2,          # mensaje persistente
                content_type="application/json",
            ),
        )
    finally:
        conexion.close()


def main():
    try:
        with psycopg.connect(DATABASE_URL, connect_timeout=10) as conn:
            por_hora, total = calcular_resumen(conn)

        if total == 0:
            print("[cronjob-summary] aun no hay registros del Cronjob 1, no se publica nada")
            sys.exit(0)

        publicar(por_hora, total)

        detalle = ", ".join(f"{i['hora']}={i['cantidad']}" for i in por_hora)
        print(f"[cronjob-summary] resumen publicado en '{ROUTING_KEY}' | "
              f"carne {CARNE} | total {total} | {detalle}")
    except Exception as exc:
        print(f"[cronjob-summary] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
