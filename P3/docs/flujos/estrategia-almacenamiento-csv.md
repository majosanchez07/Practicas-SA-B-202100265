# Estrategia de Almacenamiento de Archivos CSV

## Descripcion general

Los archivos CSV cargados por el Maker son almacenados en AWS S3 antes de ser procesados. Esto garantiza que el archivo original quede disponible para descarga, auditoria y reprocesamiento en caso de fallo.

## Flujo de almacenamiento

1. El Maker sube el archivo CSV via API Gateway al transaction-service.
2. El transaction-service valida el formato del archivo (cabeceras, delimitadores, encoding UTF-8).
3. Si el formato es valido, el archivo es subido a AWS S3 en el bucket designado.
4. Se genera una URL firmada (presigned URL) con tiempo de expiracion para descarga segura.
5. La ruta S3 del archivo queda registrada en la tabla LOTE_TRANSACCIONES.
6. El transaction-service parsea el CSV y persiste cada transaccion en su base de datos.

## Estructura de carpetas en S3
```bash
s3://banco-transacciones-{ambiente}/
├── lotes/
│ ├── {año}/
│ │ ├── {mes}/
│ │ │ ├── {loteId}-original.csv
│ │ │ └── {loteId}-procesado.csv
```

## Reglas de validacion del CSV

| Regla | Descripcion |
|-------|-------------|
| Formato | El archivo debe ser CSV con delimitador coma |
| Encoding | UTF-8 obligatorio |
| Cabeceras | cuenta_origen, cuenta_destino, monto, moneda, tipo |
| Saldo disponible | La cuenta origen debe tener saldo suficiente |
| Limite de transaccion | El monto no puede superar el limite configurado por tipo |
| Cuentas validas | Las cuentas origen y destino deben existir y estar activas |
| Prevencion de fraude | Se aplican reglas de deteccion de patrones anomalos |

## Politica de retencion

- Los archivos se conservan por 5 anos en S3 Standard.
- Despues de 90 dias se migran automaticamente a S3 Glacier para reducir costos.
- El historial de lotes (metadatos y ruta S3) permanece disponible para descarga desde el sistema en todo momento.

## Descarga del historial

El transaction-service expone un endpoint que genera una presigned URL temporal (15 minutos) para descargar el archivo CSV original desde S3 sin exponer las credenciales del bucket.
