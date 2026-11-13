# IPC y CLI, versión 1

## Endpoint y autenticación

Socket Unix `control.sock` dentro de `dev.brisa.ipc` bajo el directorio temporal del usuario, resuelto sin symlinks. Este nombre corto evita el límite de `sockaddr_un` en macOS. El directorio es 0700 y el socket 0600, ambos del UID real de la app (`getuid()`). Los dos extremos verifican al peer mediante `getpeereid`. Se admite ejecución ordinaria sin privilegios, con UID real y efectivo iguales; no se admite lanzar Brisa con setuid ni como helper elevado. Se rechazan componentes simbólicos, propietarios ajenos y padres world-writable. No hay token en argv, entorno o archivos de registro.

Una exclusión `flock` sobre `server.lock` impide que dos instancias se adueñen del endpoint. Solo el dueño del lock retira un socket obsoleto. El servidor atiende hasta ocho conexiones a la vez y una única petición de mutación; una segunda petición de mutación recibe rechazo inmediato mientras la primera sigue pendiente. Las consultas de lectura pueden continuar durante la hoja de revisión. Esto es autenticación de cuenta local, no certificación del binario cliente.

## Formato

Una trama JSON UTF-8 terminada por LF, una solicitud por conexión. El servidor admite 64 KiB de solicitud, con versión exactamente 1, UUID válido, comando acotado y hasta 101 argumentos de 8 KiB sin NUL. Las respuestas admiten hasta 8 MiB. El cliente exige ID y versión coincidentes. Una petición que ya pudo decodificarse conserva su ID en las respuestas de error. Cada recepción aplica un deadline total, incluso si llegan fragmentos parciales.

```json
{"version":1,"id":"3C88A990-8789-46CD-81E0-218AB2F5CC46","command":"status","arguments":[]}
```

```json
{"version":1,"id":"3C88A990-8789-46CD-81E0-218AB2F5CC46","ok":false,"error":{"code":"safety_rejected","message":"Safety: File is open"}}
```

Las claves opcionales `result` o `error` se omiten cuando no corresponden. No se mezclan mensajes de log con JSON en stdout. La CLI ofrece ayuda local incluso sin app. Las respuestas JSON usan números de bytes; consumidores JavaScript deben tener en cuenta la precisión de IEEE-754 para tamaños extremos.

Las fechas de resultados de protocolo se serializan como cadenas ISO 8601 en UTC. El formato de persistencia privado es independiente y usa milisegundos desde Unix epoch; no se expone directamente como contrato de IPC.

## Comandos

El parser se ejecuta tanto en CLI como en la app. Consulta `brisa help` para opciones. `analyse` devuelve inicio aceptado; no resultados ficticios. Sondea `status` hasta `scanning:false`. `categories --category <id>` permite consultar una categoría concreta. `findings` devuelve `items`, `total` y `truncated`; sus flags y límites también se validan al entrar por IPC/MCP. Los IDs se invalidan al cambiar el archivo o analizar de nuevo. `select` admite IDs elegibles, no rutas externas. `clean` y `free` actúan sobre la selección actual, con el mismo diálogo y motor de la UI.

`protect` añade una protección de forma inmediata; `unprotect` requiere confirmación nativa. Eliminar una protección del usuario no retira exclusiones integradas. `alerts on` inicia un flujo explícito de permiso del sistema; `off` solo desactiva avisos propios. `keep-process` registra un PID actual; la terminación de procesos no está implementada, por lo que todos permanecen intactos. `routine` y `update` responden con `available:false` y la causa. `setup`, `open` y `settings` abren la ventana; no conceden permisos.

Los comandos internos `mcp.*` se limitan a consulta del índice y envío de conclusiones. MCP no acepta un nombre de comando arbitrario proporcionado por un cliente. El servidor stdio anuncia protocolos 2024-11-05, 2025-03-26, 2025-06-18 y 2025-11-25, con handshake `initialize` y `notifications/initialized`; no se declara conformidad con revisiones posteriores.

## Timeouts, cancelación y carreras

El servidor espera 5 segundos para una solicitud y limita respuestas con timeout de socket. La CLI espera 15 segundos en las consultas ordinarias y 120 en `clean`, `free`, `undo` y `unprotect`. El coordinador da 115 segundos a la respuesta, y una confirmación nativa caduca a los 90. Una operación aceptada puede seguir terminando aunque el cliente se desconecte o venza su espera: **un timeout no equivale a cancelación ni a fallo del movimiento**. La CLI no reenvía una solicitud ya entregada. Consulta diario e interfaz antes de repetir.

Cancelar una confirmación antes de autorizar la operación devuelve `ok:false` con `error.code:cancelled` (CLI: salida 1) y no muestra un aviso de seguridad en la app. El botón Cancelar restantes es cooperativo entre archivos; no revierte un elemento ya movido. Cancelar un análisis no produce candidatos ficticios ni marca el índice parcial como completo. Quit se rechaza mientras hay análisis u operación. No hay idempotencia persistente por UUID; cada confirmación concede una sola selección capturada por el coordinador. No se deben reintentar operaciones basándose solo en un error de transporte.

El arranque automático busca `Brisa.app` junto a `brisa` y luego en `/Applications`. Espera hasta 5 segundos a la aparición del socket. Un socket existente con servidor caído produce un error claro: abrir la app recupera el socket con el lock correspondiente. La CLI no elimina archivos del endpoint por su cuenta.

## Referencias de implementación

- [Apple: getpeereid](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/getpeereid.3.html)
- [Apple: FileManager.trashItem](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:))
- [MCP: transporte stdio 2025-11-25](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-11-25/basic/transports.mdx)
