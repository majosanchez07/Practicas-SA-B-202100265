"""
Configuracion comun a las pruebas de auth-service.

src/config.py declara DATABASE_URL, JWT_SECRET_KEY y AES_SECRET_KEY sin valor
por defecto a proposito: en el clus'ter llegan desde el Secret que genera Helm y
el servicio debe negarse a arrancar si faltan. Eso significa que importar
cualquier modulo de src lanza ValidationError si no estan en el entorno, asi que
aqui se inyectan valores de prueba ANTES de que pytest recolecte los modulos.

Se hace en conftest.py y no dentro de cada archivo de prueba porque pytest
ejecuta este fichero antes de importar nada mas.
"""
import os

# La URL apunta a un Postgres que no existe, y es intencional: src/models/
# database.py construye el engine en tiempo de importacion con pool_size y
# max_overflow, parametros que el dialecto de SQLite rechaza. create_engine no
# abre ninguna conexion —eso ocurre en el primer uso—, de modo que basta una URL
# con la forma correcta para que el modulo importe. Las pruebas de esta suite
# ejercitan logica pura y nunca tocan la base.
os.environ.setdefault('DATABASE_URL', 'postgresql://prueba:prueba@localhost:5432/prueba')
os.environ.setdefault('JWT_SECRET_KEY', 'llave-de-prueba-no-usar-en-produccion')
# AES-256 exige exactamente 32 bytes de llave; el servicio trunca a 32, de modo
# que aqui se da una cadena de esa longitud justa para probar el caso real.
os.environ.setdefault('AES_SECRET_KEY', '01234567890123456789012345678901')
os.environ.setdefault('JWT_EXPIRATION_MINUTES', '30')
os.environ.setdefault('JWT_GRACE_PERIOD_MINUTES', '5')
