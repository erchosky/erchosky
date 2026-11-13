# Verificación · Brisa 0.1.0

Fecha de referencia: **13 de noviembre de 2026** (Europe/Madrid). Este documento resume el alcance comprobado en el código entregado, el entorno de compilación empleado y las comprobaciones manuales o de distribución que permanecen fuera del alcance automático.

## Entorno de referencia empleado

| Dato | Valor observado |
| --- | --- |
| Sistema | macOS 27.2.1 (build 26B131) |
| Arquitectura compilada y probada | `arm64` (Apple Silicon) |
| Xcode / Swift | Xcode 27.2 (27B52) · Swift 6.4.2 (`swiftlang-6.4.2.1.9`) |
| Objetivo mínimo declarado | `macOS 14` (`Package.swift` e `Info.plist`; no equivale a haber probado en macOS 14) |
| Motor de compilación usado | SwiftPM `--build-system native` |
| Firma aplicada | Ad hoc local (`codesign`, hardened runtime); **sin Developer ID ni notarización** |

## Comprobación automatizada (`scripts/check.sh`)

`bash scripts/check.sh` ejecuta el snapshot limpio de fuentes (`scripts/prepare-build.sh`), la batería completa `swift test`, la compilación `Release` y las comprobaciones smoke de CLI y servidor MCP (`scripts/smoke.py`):

- **221 XCTest, 0 fallos** (`BrisaCoreTests` y `BrisaAppTests`; Swift Testing informa `0 tests in 0 suites` al no tener casos declarados en ese framework).
- **Compilación Debug y Release**: sin errores ni dependencias de paquetes externos (`Package.swift`).
- **Módulos cubiertos por las pruebas en fixtures temporales aislados**:
  - `SafetyTests`, `OperationTests`, `AuditRegressionTests`, `ComprehensiveAuditTests`, `CurrentAuditTests`, `FinalCheckTests`: clasificación conservadora, exclusión de enlaces simbólicos, identidad POSIX/hardlinks, autorización TCC (`ReadAuthorizationPolicy`), procesos abiertos (`lsof`/`ps`), mutex de lote, diario con cadena SHA-256, restauración sin sobrescribir y límites de presupuesto/cancelación.
  - `InventoryAndCatalogTests`, `DetectorsAndSpaceMapTests`, `ReviewIntegrationTests`: catálogo `brisa-catalog.json` (11 categorías, 399 reglas, carga desde `app_bundle`), imágenes dispersas (`allocatedBytes` vs `logicalBytes`), expansión acotada de patrones y construcción de mapa de espacio compartido con la consulta activa.
  - `ProjectArtifactCleanupTests`, `PackageManagerAdapterTests`, `ExactDuplicateTests`, `AppUninstallerTests`, `DockerManagerTests`: los cinco flujos de limpieza con `OperationPlan` revisable, exclusiones Git/symlinks/actividad, transportes estructurados sin shell, verificación doble SHA-256 + conservación de copia protegida, niveles de asociación en desinstalación y protección por defecto de volúmenes Docker.
  - `ProtocolTests`, `PersistenceAndAgentTests`, `PresentationTests`, `LocalizationRuntimeTests`, `LocalizationAndTelemetryTests`, `OptimizationTests`, `LifecycleAndOptimizationTests`, `ConcurrencyAndCachingRegressionTests`, `StabilityAndPerformanceRegressionTests`, `ToolsWorkflowTests`, `BrandIdentityTests`: protocolo IPC por socket Unix con `getpeereid`, MCP de solo lectura sin herramientas destructivas, cachés/invalidación, ciclo de vida de `LiveMetricsStore` y renders ES/EN + flujos inline del panel de barra de menús y ventana principal.
- **Smoke checks CLI y MCP (`scripts/smoke.py`)**: ayuda/versión JSON, validación de argumentos inválidos, handshake `initialize`, listado cerrado de herramientas MCP y rechazo de herramientas inexistentes o rutas no permitidas, así como verificación de limpieza temporal en `scripts/cleanup-build.py`.

## Empaquetado y comprobaciones no destructivas sobre la app

`bash scripts/package.sh` compila en modo `Release`, ensambla `Brisa.app` con `packaging/Info.plist`, recursos de SwiftPM, `Brisa.icns` y `brisa-catalog.json`, firma ad hoc de forma profunda sin atributos extendidos de FileProvider y genera `dist/Brisa.zip`, `dist/brisa` y `dist/brisa-mcp` (enlazando `dist/Brisa.app` al bundle local compilado).

En ejecución viva no destructiva sobre el bundle `Release` se comprobó:

- **Firma y enlaces**: `codesign --verify --deep --strict --verbose=2` válido en disco y `otool -L` únicamente contra librerías del sistema macOS (`/usr/lib/...`, `/usr/lib/swift/...` y `/System/Library/Frameworks/...`).
- **Primer uso y barra de menús (`MenuBarExtra`)**: pantalla de bienvenida inicial sin iniciar análisis automático; flujo dentro del panel (`Analizar` → `Revisar N archivos` → selección individual/categoría → revisión previa del plan con `Qué cambiará`, `Cuánto ocupa` y `Cómo se recupera` → cancelación segura sin mutar archivos); persistencia de ruta y selección en sesión; y apertura de ventana principal exclusivamente mediante acción explícita.
- **Ventana principal y accesibilidad de navegación**: tarjetas orientadas a tareas en `Inicio`, separación entre `Limpiar > Candidatos` y `Explorar espacio`, `Duplicados`, sección `Avanzado` (`Proyectos`, `Paquetes` y `Docker`), `Aplicaciones`, `Historial`, `Ajustes` (idioma ES/EN/Sistema y apariencia Automático/Claro/Oscuro) y paleta `⌘K`.
- **IPC y MCP**: lectura de estado desde `brisa` (`status`, `categories`, `findings`, `journal`, `protected`, `agents`) confirmando `"catalogSource": "app_bundle"` y protocolo MCP stdio con las 9 herramientas de solo lectura.

## Alcance simulado frente a límites pendientes

- **Operaciones destructivas reales**: las pruebas unitarias y de integración sobre Papelera, artefactos de proyecto, duplicados, gestores de paquetes (`brew`, `npm`, `pnpm`, `yarn`), desinstalación de aplicaciones y `docker` utilizan directorios temporales aislados, `MockWorkflowTrashMover` y transportes simulados para proteger los datos personales del equipo durante la verificación.
- **Papelera real y confirmaciones del sistema**: falta prueba manual guiada sobre archivos desechables reales en `~/.Trash`, restauración ante colisiones y entrega real de notificaciones tras otorgar permisos TCC del usuario.
- **Observación con personas nuevas y VoiceOver**: la legibilidad de las cinco tareas cotidianas y la navegación por teclado (`Tab`/`Esc`/`⌘K`) se revisaron de forma guiada por el agente; no se ha observado a usuarios externos nuevos completar las tareas sin ayuda ni se ha realizado una auditoría auditiva completa con VoiceOver.
- **Distribución y compatibilidad ampliada**: el binario incluido está compilado para `arm64` con firma ad hoc local; no cuenta con certificado Developer ID, notarización de Apple ni pruebas en equipos Intel ni en versiones anteriores de macOS (como macOS 14 o 15).
- **Funciones no implementadas**: ejecución aislada de agentes CLI, autenticación con proveedores externos, Apple Intelligence y eliminación automática de `git worktree` permanecen desactivadas y se declaran explícitamente como no disponibles.

## Reproducción desde este código

```sh
bash scripts/check.sh
bash scripts/package.sh
open dist/Brisa.app
./dist/brisa status --json
```

Durante `scripts/check.sh` se crean registros temporales locales en `test-results/` (ignorados por Git). `scripts/demo.sh` prepara un entorno temporal y abre `Brisa.app` con una consulta de solo lectura.
