# Documentación de Prompts de IA

**Herramienta utilizada:** Claude (Anthropic)

A continuación, se documenta el uso de Inteligencia Artificial como herramienta de apoyo durante el desarrollo de la API REST, detallando los prompts utilizados, las respuestas generadas y el análisis crítico aplicado para garantizar que el código final sea seguro y limpio.


---

### Prompt 1: Implementación de Login con Cookies HTTP-only

**Objetivo:** Generar el endpoint de inicio de sesión gestionando los tokens de forma segura.

* **Prompt utilizado:**
> "Escribe un endpoint POST en FastAPI para un sistema de login. El endpoint debe recibir correo y contraseña. Si son correctos, debe generar un token JWT y devolverlo en una cookie HTTP-only para prevenir ataques XSS. Por favor, asegúrate de aplicar principios de Clean Code, validación de entradas y que el código sea seguro."


* **Respuesta obtenida (Resumen):**
La IA generó un código funcional utilizando `FastAPI` y `python-jose`. El endpoint validaba las credenciales y configuraba la cookie usando `response.set_cookie(key="access_token", value=token, httponly=True)`. Sin embargo, la lógica de validación de la base de datos y la creación del JWT estaban mezcladas dentro de la misma función de la ruta, y utilizaba una clave secreta *hardcodeada* (quemada en el código).
* **Ajustes aplicados (Análisis crítico):**
1. **Seguridad:** Se extrajo la clave secreta y los tiempos de expiración a un archivo `.env` utilizando variables de entorno para evitar filtraciones de credenciales. Además, se agregaron las flags `samesite='lax'` y `secure=True` (para entornos de producción con HTTPS) a la configuración de la cookie.
2. **Limpieza de código (SOLID - SRP):** Se aplicó el Principio de Responsabilidad Única. Se eliminó la lógica de validación y generación del token de la ruta y se encapsuló en `src/services/auth_service.py`. La ruta quedó únicamente responsable de recibir la petición, delegar la tarea al servicio, y retornar la respuesta HTTP.



---

### Prompt 2: Encriptación de datos sensibles con AES

**Objetivo:** Crear un servicio para encriptar contraseñas y datos del usuario antes de guardarlos en PostgreSQL.

* **Prompt utilizado:**
> "Crea una clase en Python utilizando la librería pycryptodome para encriptar y desencriptar textos (como contraseñas o correos) usando el algoritmo AES. El código debe ser seguro contra vulnerabilidades comunes, tener manejo de errores adecuado, y seguir los principios SOLID."


* **Respuesta obtenida (Resumen):**
La IA devolvió una clase `AESCipher` que implementaba el algoritmo AES en modo ECB (Electronic Codebook) y rellenaba (padding) el texto para cumplir con los bloques de 16 bytes. El código era fácil de leer pero presentaba una falla grave de seguridad: el modo ECB encripta bloques idénticos de texto plano en bloques idénticos de texto cifrado, lo que lo hace vulnerable a análisis de patrones.
* **Ajustes aplicados (Análisis crítico):**
1. **Seguridad (Prevención de ataques):** Se reemplazó el modo ECB por AES en modo CBC (Cipher Block Chaining). Se implementó la generación de un Vector de Inicialización (IV) aleatorio dinámico de 16 bytes mediante `os.urandom(16)` por cada operación de encriptación.
2. **Diseño:** El IV aleatorio se concatenó al inicio del texto cifrado para que el método de desencriptación pudiera extraerlo antes de procesar el mensaje.
3. **Manejo de errores:** Se añadieron bloques `try-except` específicos para capturar errores de padding incorrecto (por ejemplo, si se intenta desencriptar data corrupta) evitando que la aplicación exponga un *stack trace* (trazabilidad de errores) al usuario.



---

### Prompt 3: Consumo del Microservicio con Retry Loop

**Objetivo:** Comunicar el servicio principal con el servicio de autorización, manejando fallas temporales de red.

* **Prompt utilizado:**
> "Necesito una función en Python que haga una petición POST mediante la librería 'requests' a un microservicio de autorización externo en el puerto 8001. Para que el sistema sea resiliente, implementa un 'retry loop' con backoff exponencial. Asegúrate de que el código sea limpio (nombres descriptivos) y maneje correctamente las excepciones si el microservicio se cae."


* **Respuesta obtenida (Resumen):**
La herramienta generó un ciclo `while` que iteraba haciendo la petición. Si fallaba, usaba `time.sleep()` multiplicando el tiempo de espera por 2 en cada intento. Para el manejo de errores, utilizaba un bloque `except Exception as e:` general que atrapaba cualquier fallo del código.
* **Ajustes aplicados (Análisis crítico):**
1. **Limpieza de código:** Un bloque `except Exception:` general es una mala práctica porque enmascara errores de sintaxis u otros problemas no relacionados con la red. Se ajustó para capturar únicamente `requests.exceptions.RequestException` y `requests.exceptions.Timeout`.
2. **Parametrización:** En la respuesta original, el número máximo de reintentos (3) y el multiplicador estaban en código duro (hardcoded). Se modificó la función para que reciba `max_retries` y `backoff_factor` como variables inyectadas desde el archivo de configuración `config.py`.
3. **Timeouts explícitos:** Se agregó el parámetro `timeout=5` a la petición de `requests.post()`, ya que la IA lo omitió, lo cual podría haber causado que el hilo de ejecución se quedara congelado indefinidamente si el servicio de autorización aceptaba la conexión pero no respondía.