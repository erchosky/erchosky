# Modelo de amenazas y privacidad

## Activos y límites de confianza

Los activos son los datos personales del usuario, credenciales, sesiones de trabajo, integridad de los archivos seleccionados y trazabilidad de operaciones. Se consideran no fiables los nombres y rutas del sistema de archivos, respuestas de comandos, mensajes IPC y conclusiones de agentes.

Brisa se ejecuta sin privilegios elevados, sin helper privilegiado y sin acceso total al disco concedido por la aplicación. No pertenece al App Sandbox de Apple: necesita operaciones locales de monitorización y Papelera. **Eso no constituye aislamiento de un proveedor de IA.** No se ejecuta ningún proveedor en esta versión.

El IPC autentica al UID local, no a la identidad criptográfica de un proceso específico. Otro proceso de la misma cuenta puede consultar el inventario o solicitar un diálogo de limpieza; no puede confirmar silenciosamente por la ruta IPC. Un usuario local distinto queda fuera por permisos y credenciales del kernel. No se ha probado todavía ese rechazo con una segunda cuenta real.

## Controles

- Las raíces deben ser carpetas propias dentro del home, sin enlaces, y no pueden ser el propio home o una ubicación integrada protegida. No se aceptan rutas relativas ni NUL. Las exclusiones se comparan conservadoramente sin distinguir mayúsculas.
- Se excluyen datos personales, llaveros, SSH, GnuPG, .env, sesiones, iCloud, Correo, Mensajes, bases de datos, carpetas de aplicaciones y Papelera. Se rechazan rutas con controles o caracteres de formato invisibles para reducir suplantación en la revisión.
- Solo archivos regulares, propios, con un único enlace, legibles, escribibles, sin flags inmutables/append/dataless y sin padres que sean enlaces. No se borran directorios. Los archivos gestionados por iCloud quedan fuera.
- La clasificación necesita una ubicación de caché/log y extensión específica, además de antigüedad. La actividad se comprueba en el análisis y antes de la operación. `lsof` con errores o salida incierta causa rechazo. Las sesiones de agentes CLI reconocidas bloquean limpieza de forma global y conservadora.
- Antes de mover se comparan dispositivo, inode, tamaño, mtime, ctime, modo, UID y número de enlaces. Se abre el archivo con `O_NOFOLLOW`, se verifica `fstat`, se toma un `flock` consultivo y se revalida después de guardar la intención en el diario. Una última consulta a `lsof` excluye únicamente el descriptor propio.
- La confirmación se hace en un NSAlert nativo con lista de rutas y tamaños. Cancelar es la respuesta predeterminada. No hay `--yes`. No hay limpiador desde MCP ni ruta de ejecución basada en texto generado.
- Restaurar valida la identidad del objeto en Papelera, prohíbe enlaces y usa `renamex_np(RENAME_EXCL)` para no sobrescribir un destino recreado. Si el archivo desaparece, cambia, está abierto o pertenece a la Papelera de otro volumen no soportada, se rechaza. No se promete restauración tras vaciado ni borrado irreversible.
- El diario registra intención antes de mover y resultado después. Si el resultado no puede escribirse tras mover, se detiene el lote y se comunica la ambigüedad. Una intención sin resultado requiere inspección manual, no un reintento automático.

## Riesgos residuales

`FileManager.trashItem` recibe una ruta. Las validaciones previas y el descriptor abierto reducen las carreras accidentales, pero no proporcionan una transacción atómica entre `lstat`, consultas a procesos y el movimiento a Papelera. `flock` es consultivo: otro proceso puede ignorarlo. **No se afirma resistencia completa a un proceso hostil de la misma cuenta que cambie repetidamente padres o entradas en la última ventana de carrera.** El proceso ya tendría capacidad para modificar los mismos archivos. Un backend futuro necesitaría una estrategia de movimiento atómica basada en descriptores o un servicio con un contrato de seguridad distinto, sin afirmar que NSFileCoordinator elimine por sí solo ese problema.

`lsof` y `ps` tienen visibilidad limitada por macOS. El no ver un descriptor no prueba que una app nunca vaya a abrir un archivo. Los agentes bajo un runtime genérico, otra cuenta, contenedor o ejecutable no reconocido pueden no detectarse. Por eso la limpieza está restringida a archivos temporales antiguos, los padres recientes se conservan y se requiere revisión. La ausencia de actividad no se infiere del simple nombre de una carpeta.

La cadena SHA-256 detecta corrupción y alteración de registros sin recomputar la cadena. No es una firma: alguien con acceso de escritura al estado puede reescribir o truncar toda la cadena. No hay autenticidad externa ni ancla protegida por hardware. El estado usa permisos 0700/0600 y no contiene secretos.

Los totales del índice usan bloques asignados por archivo, no un análisis de bloques compartidos de APFS. Los clones y archivos dispersos pueden hacer que la suma no equivalga a espacio recuperable. El tamaño lógico de candidatos tampoco garantiza ahorro; el sistema y las apps pueden recrear cachés.

## Datos que salen del dispositivo

La app, CLI y MCP de Brisa no implementan tráfico de red, telemetría, analítica ni descargas. El sistema operativo puede gestionar sus propias operaciones de Finder, Papelera o permisos. Si conectas explícitamente `brisa-mcp` a un cliente de IA, ese cliente puede transmitir los metadatos a su proveedor. Se comparte: rutas permitidas, nombres, tamaños, tiempos, categorías, procesos del UID con nombre de ejecutable y PIDs de archivos abiertos. No se comparte contenido, argumentos de procesos, variables de entorno, archivos de autenticación ni secretos.

Las conclusiones son texto sin autoridad, se renderizan como texto y no se ejecutan. Un proveedor con acceso a otras herramientas puede hacer cosas fuera de Brisa: el servidor MCP no es un sandbox del cliente. La herramienta `submit_conclusions` vuelve a comprobar ID, tamaño y elegibilidad; no cambia selección ni preferencias.
