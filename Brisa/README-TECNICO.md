# Brisa

Aplicación nativa de barra de menús y ventana principal para macOS, escrita en Swift y SwiftUI. Diseñada para operar principalmente desde la **barra de menús (`MenuBarExtra`)** con exploración en el mismo panel, casillas triestado, protección inline de elementos y navegación de retorno sin forzar saltos a la ventana principal. Monitoriza CPU, RAM, swap, presión de memoria, instantáneas APFS locales y espacio libre; inventaría carpetas autorizadas en 11 categorías; ofrece **cinco flujos de limpieza revisada e integrados** (artefactos de proyectos, gestores de paquetes, duplicados exactos, desinstalador de aplicaciones y gestor de Docker); mantiene un Mapa de espacio proporcional sincronizado con el índice; y exige revisión explícita de cada `OperationPlan` antes de actuar. Incluye una CLI con IPC autenticado por UID del kernel y un servidor MCP separado de solo lectura.

**Alcance conservador y verificable.** Las funciones o elementos sin acceso o pendientes de autorización se indican explícitamente. Identidad, icono y código propios. Las referencias externas de catálogo y herramientas se atribuyen en [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Ejecutar

Requisitos: macOS 14 o posterior, Xcode o Command Line Tools con Swift 6.0 o posterior y Python 3 para los scripts de construcción y verificación. No hay dependencias de paquetes externos ni conexiones de red; las comprobaciones de gestores de paquetes y Docker ejecutan únicamente binarios locales ya instalados mediante argumentos estructurados (sin concatenar shell). Consulta el [informe de verificación](docs/VERIFICATION.md).

```sh
bash scripts/package.sh
open dist/Brisa.app
./dist/brisa status --json
```

En la bienvenida, pulsa **Empezar**. Se preparan `~/Library/Caches` y `~/Library/Logs` como raíces de limpieza revisada; las carpetas de proyecto detectadas o autorizadas permanecen como inventario/alcance separado. El análisis comienza únicamente al pulsar **Analizar** o ejecutar `brisa analyse`. Cerrar la ventana mantiene la app en la barra de menús. El menú **Brisa > Salir** o `brisa quit` termina el proceso si no hay tareas activas.

El paquete genera `dist/Brisa.zip` (bundle autocontenido), `dist/Brisa.app` (enlace a `~/Library/Caches/dev.brisa.build/Brisa.app`, fuera de la carpeta gestionada por FileProvider), `dist/brisa` y `dist/brisa-mcp`. Usa firma ad hoc para ejecutar localmente. **No está notarizado ni firmado con un Developer ID.**

## Lo que puedes hacer

- **Experiencia centrada en la barra de menús (`MenuBarExtra`)**:
  - Inicio simplificado del popover con espacio libre, estado del análisis actual, acción principal adaptada al estado (`Analizar` o `Revisar N archivos · X`), accesos secundarios (`Explorar espacio`, `Más herramientas`), desplegable de rendimiento en vivo (`CPU`, `RAM`, `GPU`, swap y presión de memoria) y salida o apertura explícita de la ventana principal (`Abrir ventana`).
  - Flujo completo dentro del mismo panel (`Analizar → Archivos para revisar → seleccionar → Revisar antes de mover → confirmar → resultado`), apertura de candidatos verificados cuando no hay selección previa (sin saltar a categorías protegidas), exploración separada de las 11 categorías (`Explorar espacio`), casillas individuales y por categoría (`MenuTriStateCheckbox`), protección inline, navegación por pila (`Esc`/volver) y persistencia en sesión de ruta y selección al cerrar y reabrir.
- **Ventana principal orientada a tareas y cinco módulos con plan revisable (`OperationPlan`)**:
  - Barra lateral organizada por tareas cotidianas: **Inicio** (tarjetas de qué quiere hacer el usuario con explicación práctica), **Limpiar** (`Candidatos`, `Explorar espacio`, `Duplicados` y `Avanzado` para proyectos/paquetes/Docker), **Aplicaciones** e **Historial**; **Ajustes** queda como utilidad secundaria (idioma ES/EN/Sistema, apariencia Automático/Claro/Oscuro, espacio libre en la barra de menús y sección desplegable **Avanzado** para herramientas locales/MCP).
  - Revisión previa estructurada en tres preguntas inmediatas (**Qué cambiará**, **Cuánto ocupa**, **Cómo se recupera**), con comandos de reconstrucción y detalles técnicos en sección desplegable (`Detalles técnicos`), manteniendo siempre visibles las advertencias críticas (borrado irreversible, datos compartidos o procesos activos).
  1. **Limpieza de artefactos de proyectos (`ProjectArtifactCleaner` + `ProjectArtifactCleanupPolicy`)**: agrupa `.build`, `target`, `node_modules` y salidas de compilación por proyecto y tecnología; muestra asignado y lógico, fecha de modificación (sin presentarla como último uso), motivo regenerable y pasos de reconstrucción; bloquea archivos rastreados por Git, subrepositorios, enlaces simbólicos y actividad/origen no verificable; prioriza la Papelera y no ejecuta scripts del proyecto.
  2. **Limpieza mediante gestores de paquetes (`PackageManagerService`)**: adaptadores independientes para **Homebrew**, **npm**, **pnpm** y **Yarn**; detecta binario y versión instalados, ubicaciones reales de caché, capacidades compatibles, alcance completo vs. selectivo y comandos oficiales documentados con argumentos estructurados y timeouts; conserva paquetes instalados, configuraciones y credenciales.
  3. **Buscador de duplicados exactos (`ExactDuplicateScanner` + `DuplicateCleaner`)**: alcance propio autorizado para lectura de contenido (`DuplicateScopePolicy`), separado del inventario de metadatos; canalización progresiva (tamaño → lectura parcial preliminar → SHA-256 en streaming con progreso y cancelación), exclusión de enlaces simbólicos, elementos solo en la nube y paquetes `.app`, distinción de hardlinks y clones APFS (`clonefile`), conservación garantizada de al menos una copia protegida y revalidación de identidad + SHA-256 antes de mover copias sobrantes a la Papelera.
  4. **Desinstalador de aplicaciones (`AppUninstaller`)**: integrado en la vista de **Aplicaciones**; localiza elementos asociados por Bundle ID, Team/firma y grupos/ubicaciones conocidas con motivo y confianza; separa datos exclusivos, posibles compartidos con otras apps instaladas y coincidencias inciertas; protege apps del sistema y documentos del usuario; bloquea si la app está en ejecución (con botón de revalidación tras cerrarla manualmente) y marca aparte componentes que requieren privilegios sin elevación general.
  5. **Gestor de Docker (`DockerManager`)**: verifica cliente y daemon; muestra por separado contenedores detenidos, imágenes, caché de compilación y volúmenes mediante salida JSON estructurada; detalla dependencias y tamaño vs. espacio compartido; mantiene volúmenes protegidos por defecto hasta desbloqueo y confirmación explícita; no detiene contenedores en ejecución automáticamente ni promete restauración tras eliminaciones irreversibles.

- **Métricas y diagnósticos reales de solo lectura**:
  - CPU por diferencias de ticks Mach (`host_statistics`), RAM activa + cableada + comprimida (`host_statistics64`), capacidad y espacio libre del volumen APFS.
  - **Swap (`sysctlbyname("vm.swapusage")`)**, **nivel de presión de memoria del kernel (`kern.memorystatus_vm_pressure_level`)** separado de la RAM usada, y **recuento de instantáneas APFS locales (`tmutil listlocalsnapshots /`)** distinguiendo Time Machine de actualizaciones del sistema. Ni el swap ni las instantáneas se suman al espacio limpiable ni se borran nunca.
  - GPU y salud física del disco muestran explícitamente `"Sin datos"` / `"No disponible"`.
- **Inventario real en 11 categorías** tanto en el popover de la barra de menús como en la ventana principal:
  1. **VM y contenedores** (`vm_containers`): separa bloques APFS asignados (`st_blocks * 512`), tamaño lógico (`st_size`) y capacidad virtual real (incluyendo lectura de cabecera QCOW2 v2/v3 de 32 bytes sin inferir capacidad virtual desde la longitud de un contenedor). Nunca sustituye `0 B` asignados por el tamaño lógico.
  2. **Cachés de aplicaciones** (`app_caches`)
  3. **Cachés de paquetes** (`package_caches`)
  4. **Cachés de desarrollo** (`developer_caches`)
  5. **Extensiones de editores** (`editor_extensions`)
  6. **Toolchains y SDK** (`toolchains_sdks`)
  7. **Historial de agentes y editores** (`agent_editor_history`)
  8. **Archivos temporales** (`temporary_files`)
  9. **Registros y fallos** (`logs_crashes`)
  10. **Restos de aplicaciones** (`app_leftovers`)
  11. **Descargas e instaladores** (`downloads_installers`)
- **Catálogo unificado con procedencia (`brisa-catalog.json`)**:
  - 399 reglas base revisadas + 10 reglas complementarias de inventario procedentes de Disk Jockey (`f28f7e1914dcc74d7c29b0cebda516fb9394ba20`, licencia MIT, véase [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)) y 65 reglas solapadas enriquecidas con `upstreamProvenance`, integradas en una única canalización de descubrimiento, medición, deduplicación y políticas.
- **Garantías estrictas de inventario y seguridad**:
  - La pasada rápida y las reglas del catálogo comparten la misma evaluación (`SelectionPolicy` + `SafetyPolicy`), respetando `never_touched`, `tier: never`, `listOnly`, `neverTicked` y condiciones no verificadas, y revalidando elegibilidad antes de cualquier acción.
  - La parcialidad por límite de entradas (p. ej. 2.000 entradas por directorio o presupuesto global) se propaga al elemento, a la categoría (`status = .partial`) y al snapshot (`complete = false`) con motivo explícito.
  - Sin recortes silenciosos de inventario (se eliminaron los truncamientos de 80/120 candidatos).
  - Cuando una regla específica reclama una subcarpeta, la regla padre contabiliza los archivos hermanos restantes sin perderlos ni duplicar bytes.
  - Comprobación real de descriptores abiertos (`lsof`) antes de marcar cualquier archivo regular como `idle` y `eligible`.
  - Separación entre **raíces de inventario de solo lectura** (`preferences.inventoryRoots`, que permite inventariar `~/Downloads` o proyectos tras autorización válida) y **raíces de limpieza revisada** (`preferences.roots`, restringidas a `~/Library/Caches` y `~/Library/Logs`).
  - Recálculo automático de agregados (`syncScanAggregates()`) tras mutaciones o cambios de alcance para mantener sincronizados UI, CLI y MCP.
- **Detectores contextuales tipados en modo inventario (`inventoryOnly: true`, `selectionAllowed: false`)**:
  - **Compilaciones huérfanas (`OrphanBuildDetector`)**: analiza `info.plist` (`PropertyListSerialization`) en `DerivedData` y `state/daemon/daemon.json` (`JSONSerialization` + sufijo SHA-256 de 12 hex) en `XcodeBuildMCP` / `MobileBuildMCP`, clasificando `active_project`, `possibly_orphaned`, `missing_metadata`, `invalid_metadata`, `permission_denied` y `unknown_unmounted_volume` (nunca marca como huérfano un error de permisos ni un volumen externo `/Volumes/...` no montado).
  - **Worktrees de Git y artefactos contextuales de proyecto (`WorktreeAndProjectDetector`)**: descubre repositorios y worktrees enlazados dentro de raíces autorizadas usando `git worktree list --porcelain -z`, `git status --porcelain=v1 -z`, `git rev-list --count HEAD --not --remotes`, `git merge-base --is-ancestor` y `git ls-files -z` con timeout, `GIT_OPTIONAL_LOCKS=0` y `GIT_TERMINAL_PROMPT=0` (una consulta fallida se clasifica como `inspection_failed_unknown`, nunca como limpia). Asocia `.build` con `Package.swift`, `target` con `Cargo.toml`/`pom.xml`, artefactos JS con `package.json`, `build`/`.gradle` con Gradle, `Pods` con `Podfile` y `.venv` con Python, bloqueando archivos rastreados por Git, subrepositorios y symlinks.
- **Mapa de espacio (`SpaceMapView` / `SpaceMapBuilder`) y divulgación progresiva**:
  - Mapa proporcional nativo en SwiftUI con navegación por migas de pan, agrupación explícita `"Otros"`, indicador de parcialidad, representación honesta de archivos dispersos de `0 B` asignados y lista equivalente accesible respaldada por el mismo snapshot (`allocatedBytes` e IDs idénticos).
  - Separación cromática accesible: gris para desconocido/pendiente/no instalado, cian para inventario medido, ámbar para parcial/en uso/sin acceso, y **verde reservado exclusivamente para candidatos elegibles verificados**.
  - Divulgación progresiva: título humano, explicación y motivo de bloqueo en primer plano; `ruleID`, `sourceGroup`, procedencia, condiciones e inodo en sección técnica desplegable.
  - Diario de actividad con contabilidad honesta: distingue bytes seleccionados, movidos a la Papelera, retenidos/restaurados, rechazados y delta de espacio libre observado en el volumen APFS.

## CLI

```sh
./dist/brisa help
./dist/brisa status --json
./dist/brisa categories --json
./dist/brisa analyse --json
./dist/brisa findings --category vm_containers --limit 30 --json
./dist/brisa findings --category eligible --limit 30 --json
./dist/brisa orphans --json
./dist/brisa worktrees --json
./dist/brisa diagnostics --json
./dist/brisa spacemap --json
./dist/brisa select '<id-del-índice>' --json
./dist/brisa clean --json       # Abre la confirmación nativa; nunca confirma por ti
./dist/brisa journal --json
./dist/brisa undo '<id-del-diario>' --json
```

Las carpetas protegidas de macOS guardadas en Ajustes pueden requerir **Autorizar carpeta…** en la sesión actual. Guardar una ruta no acredita permiso TCC; mientras falte autorización, el análisis la omite y marca la cobertura pendiente o parcial. No se activa Acceso total al disco.

## Pruebas y verificación

```sh
bash scripts/check.sh
bash scripts/package.sh
```

Documentación: [arquitectura](docs/ARCHITECTURE.md), [amenazas](docs/THREAT_MODEL.md), [funciones](docs/FEATURES.md), [IPC](docs/IPC.md), [verificación](docs/VERIFICATION.md), [avisos de terceros](THIRD_PARTY_NOTICES.md).
