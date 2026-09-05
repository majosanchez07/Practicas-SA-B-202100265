"""
Cronjob 1 — Registro de ejecuciones.

Se ejecuta cada 2 minutos e inserta un registro con la fecha y hora de
ejecucion en zona horaria GMT-6 y el numero de carne del estudiante.

Corre como un Job de Kubernetes: hace su trabajo y termina con codigo 0. Si
falla, sale con codigo distinto de 0 para que Kubernetes lo contabilice como
fallido y respete el backoffLimit configurado en el chart.
"""
import os
import sys
from datetime import datetime, timedelta, timezone

import psycopg
from psycopg import sql

# GMT-6 sin ajuste de horario de verano, que es como opera Guatemala.
GMT_MENOS_6 = timezone(timedelta(hours=-6))

DATABASE_URL = os.environ["DATABASE_URL"]
DB_SCHEMA = os.getenv("DB_SCHEMA", "cronjobs")
CARNE = os.environ["CARNE"]
TABLA = "ejecuciones"


def preparar_esquema(conn):
    """Idempotente: el cronjob puede ser el primero en tocar la base."""
    with conn.cursor() as cur:
        cur.execute(sql.SQL("CREATE SCHEMA IF NOT EXISTS {}").format(sql.Identifier(DB_SCHEMA)))
        cur.execute(
            sql.SQL("""
                CREATE TABLE IF NOT EXISTS {}.{} (
                    id            SERIAL PRIMARY KEY,
                    carne         VARCHAR(20)  NOT NULL,
                    ejecutado_en  TIMESTAMPTZ  NOT NULL,
                    fecha_texto   VARCHAR(40)  NOT NULL,
                    origen        VARCHAR(50)  NOT NULL DEFAULT 'cronjob-insert'
                )
            """).format(sql.Identifier(DB_SCHEMA), sql.Identifier(TABLA))
        )
    conn.commit()


def insertar_ejecucion(conn):
    ahora = datetime.now(GMT_MENOS_6)
    fecha_texto = ahora.strftime("%Y-%m-%d %H:%M:%S GMT-6")

    with conn.cursor() as cur:
        cur.execute(
            sql.SQL("""
                INSERT INTO {}.{} (carne, ejecutado_en, fecha_texto)
                VALUES (%s, %s, %s)
                RETURNING id
            """).format(sql.Identifier(DB_SCHEMA), sql.Identifier(TABLA)),
            (CARNE, ahora, fecha_texto),
        )
        registro_id = cur.fetchone()[0]
    conn.commit()
    return registro_id, fecha_texto


def main():
    try:
        with psycopg.connect(DATABASE_URL, connect_timeout=10) as conn:
            preparar_esquema(conn)
            registro_id, fecha_texto = insertar_ejecucion(conn)
            print(f"[cronjob-insert] registro #{registro_id} | carne {CARNE} | {fecha_texto}")
    except Exception as exc:
        print(f"[cronjob-insert] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
