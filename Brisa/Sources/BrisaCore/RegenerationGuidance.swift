import Foundation

/// Normalized regeneration expectation propagated from a catalog rule to an indexed item.
public enum RegenerationBehavior: String, Codable, Sendable, Equatable, CaseIterable {
    case downloads
    case rebuilds
    case gone
    case unknown

    public init(rawBehavior: String?) {
        switch rawBehavior?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "downloads":
            self = .downloads
        case "rebuilds", "rebuilt":
            self = .rebuilds
        case "gone":
            self = .gone
        default:
            self = .unknown
        }
    }
}

/// Concise, family-aware explanation shown when inspecting a single finding in Brisa.
public struct RegenerationDetails: Equatable, Sendable {
    public let familyID: String
    public let behavior: RegenerationBehavior
    public let familyTitleES: String
    public let familyTitleEN: String
    public let whatItIsES: String
    public let whatItIsEN: String
    public let whatIsLostES: String
    public let whatIsLostEN: String
    public let regenerationES: String
    public let regenerationEN: String
}

/// Resolves concise ES/EN guidance explaining what an item is, what deleting it removes,
/// and what regenerating or recovering it costs.
public enum RegenerationGuidance {
    private struct FamilyCopy {
        let id: String
        let titleES: String
        let titleEN: String
        let defaultBehavior: RegenerationBehavior
        let whatItIsES: String
        let whatItIsEN: String
        let whatIsLostES: String
        let whatIsLostEN: String
        let regenerationRebuildsES: String?
        let regenerationRebuildsEN: String?
        let regenerationDownloadsES: String?
        let regenerationDownloadsEN: String?
        let regenerationGoneES: String?
        let regenerationGoneEN: String?
    }

    public static func describe(for file: IndexedFile) -> RegenerationDetails {
        describe(
            sourceGroup: file.sourceGroup,
            regenBehavior: file.regenBehavior,
            category: file.storageCategory,
            tier: file.dataKind
        )
    }

    public static func describe(
        sourceGroup: String?,
        regenBehavior: String?,
        category: StorageCategory?,
        tier: DataTier? = nil
    ) -> RegenerationDetails {
        let normalizedGroup = canonicalGroup(sourceGroup: sourceGroup, category: category)
        let copy = normalizedGroup.flatMap { families[$0] } ?? fallbackCopy(for: category, tier: tier)
        let parsedBehavior = RegenerationBehavior(rawBehavior: regenBehavior)
        let effectiveBehavior = parsedBehavior == .unknown ? copy.defaultBehavior : parsedBehavior
        let (regenES, regenEN) = regenerationText(for: copy, behavior: effectiveBehavior)

        return RegenerationDetails(
            familyID: copy.id,
            behavior: effectiveBehavior,
            familyTitleES: copy.titleES,
            familyTitleEN: copy.titleEN,
            whatItIsES: copy.whatItIsES,
            whatItIsEN: copy.whatItIsEN,
            whatIsLostES: copy.whatIsLostES,
            whatIsLostEN: copy.whatIsLostEN,
            regenerationES: regenES,
            regenerationEN: regenEN
        )
    }

    private static func canonicalGroup(sourceGroup: String?, category: StorageCategory?) -> String? {
        guard let raw = sourceGroup?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return category.map(defaultGroupID(for:))
        }
        switch raw.lowercased() {
        case "xcode", "xcode build data":
            return "xcode_build_data"
        case "build output":
            return "build_output"
        case "project dependencies":
            return "project_dependencies"
        case "packages", "package caches":
            return "package_caches"
        case "simulators and emulators":
            return "simulators_emulators"
        case "device support files":
            return "device_support_files"
        case "toolchains", "toolchains and sdks":
            return "toolchains_sdks"
        case "vms", "virtual machines and containers":
            return "vms_containers"
        case "ai models":
            return "ai_models"
        case "developer tool caches":
            return "developer_tool_caches"
        case "editor extensions":
            return "editor_extensions"
        case "app caches", "apps":
            return "app_caches"
        case "agent and editor history":
            return "agent_editor_history"
        case "agent worktrees":
            return "agent_worktrees"
        case "app leftovers":
            return "app_leftovers"
        case "downloads and installers":
            return "downloads_installers"
        case "logs", "logs and crash reports":
            return "logs_crash_reports"
        case "temp", "temporary files":
            return "temporary_files"
        case "trash":
            return "trash"
        case "backups and archives":
            return "backups_archives"
        case "chat attachments":
            return "chat_attachments"
        case "podcast and media downloads":
            return "podcast_media_downloads"
        case "render and preview files":
            return "render_preview_files"
        case "sound libraries":
            return "sound_libraries"
        case "games":
            return "games"
        case "large media files":
            return "large_media_files"
        case "never touched":
            return "never_touched"
        default:
            return category.map(defaultGroupID(for:))
        }
    }

    private static func defaultGroupID(for category: StorageCategory) -> String {
        switch category {
        case .vmContainers: return "vms_containers"
        case .appCaches: return "app_caches"
        case .packageCaches: return "package_caches"
        case .developerCaches: return "developer_tool_caches"
        case .editorExtensions: return "editor_extensions"
        case .toolchainsAndSDKs: return "toolchains_sdks"
        case .agentAndEditorHistory: return "agent_editor_history"
        case .temporaryFiles: return "temporary_files"
        case .logsAndCrashes: return "logs_crash_reports"
        case .appLeftovers: return "app_leftovers"
        case .downloadsAndInstallers: return "downloads_installers"
        }
    }

    private static func regenerationText(for copy: FamilyCopy, behavior: RegenerationBehavior) -> (String, String) {
        switch behavior {
        case .rebuilds:
            return (
                copy.regenerationRebuildsES ?? genericRegeneration(for: .rebuilds).es,
                copy.regenerationRebuildsEN ?? genericRegeneration(for: .rebuilds).en
            )
        case .downloads:
            return (
                copy.regenerationDownloadsES ?? genericRegeneration(for: .downloads).es,
                copy.regenerationDownloadsEN ?? genericRegeneration(for: .downloads).en
            )
        case .gone:
            return (
                copy.regenerationGoneES ?? genericRegeneration(for: .gone).es,
                copy.regenerationGoneEN ?? genericRegeneration(for: .gone).en
            )
        case .unknown:
            return genericRegeneration(for: copy.defaultBehavior)
        }
    }

    private static func genericRegeneration(for behavior: RegenerationBehavior) -> (es: String, en: String) {
        switch behavior {
        case .rebuilds:
            return (
                "La herramienta o aplicación lo reconstruirá de forma automática cuando lo necesite.",
                "The app or tool rebuilds it automatically when needed."
            )
        case .downloads:
            return (
                "Habrá que descargarlo de nuevo si vuelves a necesitarlo.",
                "It will need to be downloaded again if you need it later."
            )
        case .gone, .unknown:
            return (
                "No se regenera automáticamente una vez eliminado de este volumen.",
                "Does not come back automatically once removed from this volume."
            )
        }
    }

    private static func fallbackCopy(for category: StorageCategory?, tier: DataTier?) -> FamilyCopy {
        let defaultBehavior: RegenerationBehavior = switch tier {
        case .regenerable: .rebuilds
        case .costly: .downloads
        case .userData, .never: .gone
        case nil: .unknown
        }
        return FamilyCopy(
            id: category?.rawValue ?? "general",
            titleES: category?.titleES ?? "Archivo inventariado",
            titleEN: category?.titleEN ?? "Inventoried item",
            defaultBehavior: defaultBehavior,
            whatItIsES: category?.aboutES ?? "Elemento detectado en una ruta analizada por Brisa.",
            whatItIsEN: category?.aboutEN ?? "Item detected in a location inspected by Brisa.",
            whatIsLostES: "Solo este elemento o carpeta en la ruta mostrada; revisa si contiene datos propios antes de actuar.",
            whatIsLostEN: "Only the item or folder at this path; verify whether it holds project or personal files before acting.",
            regenerationRebuildsES: nil,
            regenerationRebuildsEN: nil,
            regenerationDownloadsES: nil,
            regenerationDownloadsEN: nil,
            regenerationGoneES: nil,
            regenerationGoneEN: nil
        )
    }

    private static let families: [String: FamilyCopy] = [
        "xcode_build_data": FamilyCopy(
            id: "xcode_build_data",
            titleES: "Compilación de Xcode",
            titleEN: "Xcode build data",
            defaultBehavior: .rebuilds,
            whatItIsES: "Productos intermedios, índices y resultados locales generados por Xcode al compilar o probar.",
            whatItIsEN: "Intermediate build artifacts, index stores, and test products created locally by Xcode.",
            whatIsLostES: "Únicamente cachés compiladas en local; tu código fuente y la configuración del proyecto permanecen intactos.",
            whatIsLostEN: "Only local compiled caches and index state; source code and project settings remain untouched.",
            regenerationRebuildsES: "Xcode lo recrea al abrir o compilar el proyecto; la primera compilación tras limpiar tardará más.",
            regenerationRebuildsEN: "Xcode recreates this when opening or building the project; the first build afterward takes longer.",
            regenerationDownloadsES: nil,
            regenerationDownloadsEN: nil,
            regenerationGoneES: "Los resultados de prueba antiguos no reaparecen por sí solos; las próximas compilaciones crearán artefactos nuevos.",
            regenerationGoneEN: "Older test results do not return on their own; future builds create fresh artifacts."
        ),
        "build_output": FamilyCopy(
            id: "build_output",
            titleES: "Artefactos de compilación",
            titleEN: "Build output",
            defaultBehavior: .rebuilds,
            whatItIsES: "Directorios de salida generados por compiladores, bundlers o sistemas de build dentro de un proyecto.",
            whatItIsEN: "Output folders written by compilers, bundlers, or build tools inside a project directory.",
            whatIsLostES: "Binarios locales, bundles compilados y estado incremental de compilación.",
            whatIsLostEN: "Local compiled binaries, bundles, and incremental build state.",
            regenerationRebuildsES: "Se vuelve a generar ejecutando el build del proyecto; recompilar desde cero consumirá más tiempo la primera vez.",
            regenerationRebuildsEN: "Rebuilt the next time you run the project build; the first cold rebuild takes longer.",
            regenerationDownloadsES: nil,
            regenerationDownloadsEN: nil,
            regenerationGoneES: nil,
            regenerationGoneEN: nil
        ),
        "project_dependencies": FamilyCopy(
            id: "project_dependencies",
            titleES: "Dependencias de proyecto",
            titleEN: "Project dependencies",
            defaultBehavior: .downloads,
            whatItIsES: "Paquetes o entornos instalados dentro de la carpeta de un repositorio (como node_modules o venv).",
            whatItIsEN: "Packages or virtual environments installed inside a repository folder (such as node_modules or venv).",
            whatIsLostES: "Las librerías instaladas en ese proyecto; el lockfile y tu código fuente se conservan.",
            whatIsLostEN: "Installed packages for that project; lockfiles and source code are preserved.",
            regenerationRebuildsES: "El gestor del proyecto puede reconstruir el entorno si dispone de los paquetes en caché local.",
            regenerationRebuildsEN: "Your package tool can recreate the environment from local caches.",
            regenerationDownloadsES: "Reinstalarlo requiere ejecutar el gestor de dependencias del proyecto con acceso a red o caché local.",
            regenerationDownloadsEN: "Restoring it requires running the project's installer command with network or local cache access.",
            regenerationGoneES: nil,
            regenerationGoneEN: nil
        ),
        "package_caches": FamilyCopy(
            id: "package_caches",
            titleES: "Cachés de paquetes",
            titleEN: "Package caches",
            defaultBehavior: .downloads,
            whatItIsES: "Copias locales de archivos descargados e índices globales usados por gestores de paquetes.",
            whatItIsEN: "Cached download archives and global metadata indexes kept by package managers.",
            whatIsLostES: "Copias cacheadas para instalaciones futuras; las dependencias ya instaladas en tus proyectos siguen funcionando.",
            whatIsLostEN: "Cached archives used to speed up future installs; packages already installed in projects keep working.",
            regenerationRebuildsES: "El gestor reconstruye el índice automáticamente la próxima vez que instales o actualices paquetes.",
            regenerationRebuildsEN: "The package manager rebuilds the index automatically the next time you install or update packages.",
            regenerationDownloadsES: "Solo se volverán a descargar los paquetes concretos que instales en el futuro.",
            regenerationDownloadsEN: "Only the specific packages needed for future installations will be downloaded again.",
            regenerationGoneES: nil,
            regenerationGoneEN: nil
        ),
        "simulators_emulators": FamilyCopy(
            id: "simulators_emulators",
            titleES: "Simuladores y emuladores",
            titleEN: "Simulators and emulators",
            defaultBehavior: .rebuilds,
            whatItIsES: "Dispositivos virtuales, runtimes o cachés de simuladores iOS/Android creados para pruebas.",
            whatItIsEN: "Virtual devices, simulator runtimes, or emulator data used for testing.",
            whatIsLostES: "Apps instaladas de prueba, sesiones guardadas y datos dentro de ese dispositivo o runtime virtual.",
            whatIsLostEN: "Test apps, login state, and local data stored inside that virtual device or runtime.",
            regenerationRebuildsES: "El entorno recrea los archivos temporales al arrancar de nuevo el simulador o emulador.",
            regenerationRebuildsEN: "Temporary files are recreated automatically when launching the simulator or emulator again.",
            regenerationDownloadsES: "Volver a contar con esa versión requiere descargar de nuevo varios gigabytes del runtime desde Xcode o el SDK.",
            regenerationDownloadsEN: "Restoring this OS image requires re-downloading several gigabytes from Xcode or the SDK manager.",
            regenerationGoneES: "Un dispositivo virtual borrado no vuelve por sí solo; habría que crearlo y configurarlo otra vez.",
            regenerationGoneEN: "A removed virtual device does not return automatically; a fresh device would need to be provisioned."
        ),
        "device_support_files": FamilyCopy(
            id: "device_support_files",
            titleES: "Soporte de dispositivos",
            titleEN: "Device support files",
            defaultBehavior: .rebuilds,
            whatItIsES: "Símbolos e imágenes de depuración que Xcode guarda por versión de iOS, watchOS o tvOS conectada.",
            whatItIsEN: "Debug symbols and OS support files cached by Xcode for specific connected Apple devices.",
            whatIsLostES: "Símbolos locales para esa versión de sistema; conviene conservar los de dispositivos que aún depuras.",
            whatIsLostEN: "Cached symbols for that OS release; keep entries for devices you actively debug.",
            regenerationRebuildsES: "Xcode vuelve a extraer los símbolos automáticamente la próxima vez que conectes un dispositivo con esa versión.",
            regenerationRebuildsEN: "Xcode re-extracts these symbols automatically the next time you plug in a device on that OS version.",
            regenerationDownloadsES: "Si hace falta de nuevo, Xcode descargará los archivos de soporte correspondientes a esa versión.",
            regenerationDownloadsEN: "If needed later, Xcode downloads the corresponding support files for that OS release.",
            regenerationGoneES: nil,
            regenerationGoneEN: nil
        ),
        "toolchains_sdks": FamilyCopy(
            id: "toolchains_sdks",
            titleES: "Toolchains y SDKs",
            titleEN: "Toolchains and SDKs",
            defaultBehavior: .downloads,
            whatItIsES: "Compiladores, versiones instaladas de lenguajes, SDKs móviles o copias completas de Xcode.",
            whatItIsEN: "Installed compiler toolchains, language versions, mobile SDKs, or Xcode platform packages.",
            whatIsLostES: "Esa versión concreta del compilador o SDK; los proyectos fijados a ella dejarán de compilar hasta reinstalarla.",
            whatIsLostEN: "That specific compiler or SDK installation; projects pinned to it will fail to build until reinstalled.",
            regenerationRebuildsES: nil,
            regenerationRebuildsEN: nil,
            regenerationDownloadsES: "No vuelve por sí solo: tendrás que reinstalar y descargar esa versión desde su gestor oficial.",
            regenerationDownloadsEN: "Not recreated automatically: you would need to re-download and install that version via its manager.",
            regenerationGoneES: "Eliminación permanente de esa versión hasta que la instales de nuevo manualmente.",
            regenerationGoneEN: "Permanent removal of that version until manually installed again."
        ),
        "vms_containers": FamilyCopy(
            id: "vms_containers",
            titleES: "Máquinas virtuales y contenedores",
            titleEN: "Virtual machines and containers",
            defaultBehavior: .gone,
            whatItIsES: "Almacenamiento de contenedores, imágenes Docker/Colima, capas o discos de máquinas virtuales.",
            whatItIsEN: "Container image stores, Docker/Colima layers, or virtual machine disk images.",
            whatIsLostES: "Imágenes locales, estado detenido y volúmenes no respaldados dentro de esa máquina virtual o contenedor.",
            whatIsLostEN: "Local images, stopped container state, and unbacked volumes stored inside that VM or container store.",
            regenerationRebuildsES: "El motor recrea la caché operativa al iniciar de nuevo el servicio, sin datos propios previos.",
            regenerationRebuildsEN: "The runtime recreates working cache directories on next startup without previous local state.",
            regenerationDownloadsES: "Las imágenes base se pueden volver a descargar del registro; los volúmenes y cambios locales sin copia se pierden.",
            regenerationDownloadsEN: "Base images can be pulled again from registries, while unbacked local volumes and state are lost.",
            regenerationGoneES: "Los discos virtuales o volúmenes propios no se regeneran; sin copia externa no se pueden recuperar.",
            regenerationGoneEN: "Virtual disks and local volumes are not regenerated automatically; without backups they cannot be recovered."
        ),
        "ai_models": FamilyCopy(
            id: "ai_models",
            titleES: "Modelos locales de IA",
            titleEN: "Local AI models",
            defaultBehavior: .downloads,
            whatItIsES: "Pesos, cuantizaciones y blobs descargados para ejecutar modelos locales (como Ollama, LM Studio o Hugging Face).",
            whatItIsEN: "Model weights, quantizations, and cached blobs downloaded for local inference (Ollama, LM Studio, Hugging Face).",
            whatIsLostES: "La copia descargada del modelo en disco; tus prompts o ajustes fuera de esta carpeta se conservan.",
            whatIsLostEN: "The downloaded local model weights; prompts and settings saved outside this folder stay intact.",
            regenerationRebuildsES: nil,
            regenerationRebuildsEN: nil,
            regenerationDownloadsES: "No se recrea solo: volver a usar ese modelo en local implicará descargar varios gigabytes de nuevo.",
            regenerationDownloadsEN: "Not rebuilt locally: running that model offline again requires re-downloading several gigabytes.",
            regenerationGoneES: nil,
            regenerationGoneEN: nil
        ),
        "developer_tool_caches": FamilyCopy(
            id: "developer_tool_caches",
            titleES: "Cachés de herramientas de desarrollo",
            titleEN: "Developer tool caches",
            defaultBehavior: .rebuilds,
            whatItIsES: "Cachés internas de IDEs, servidores de lenguaje, linters, compiladores y SDKs.",
            whatItIsEN: "Internal caches created by IDEs, language servers, linters, compilers, and dev tools.",
            whatIsLostES: "Índices y cálculos intermedios en caché; no contiene código fuente propio.",
            whatIsLostEN: "Precomputed indexes and intermediate cached state; contains no user source code.",
            regenerationRebuildsES: "La herramienta los reconstruye automáticamente en la siguiente apertura o ejecución.",
            regenerationRebuildsEN: "Rebuilt automatically the next time you open the editor or run the tool.",
            regenerationDownloadsES: "La herramienta descargará de nuevo los componentes auxiliares necesarios si vuelven a usarse.",
            regenerationDownloadsEN: "The tool downloads needed helper artifacts again when next requested.",
            regenerationGoneES: nil,
            regenerationGoneEN: nil
        ),
        "editor_extensions": FamilyCopy(
            id: "editor_extensions",
            titleES: "Extensiones de editores",
            titleEN: "Editor extensions",
            defaultBehavior: .downloads,
            whatItIsES: "Paquetes de plugins, servidores de lenguaje o versiones antiguas de extensiones instaladas.",
            whatItIsEN: "Installed editor plugin bundles, language servers, or older extension versions.",
            whatIsLostES: "Si quitas la versión activa perderás esa extensión en el editor; las versiones ya sustituidas solo ocupan sitio.",
            whatIsLostEN: "Removing the active version disables that extension; superseded older versions only occupy disk space.",
            regenerationRebuildsES: "El editor reinstala los archivos auxiliares necesarios al abrirse si siguen configurados.",
            regenerationRebuildsEN: "The editor recreates helper files on startup if the extension stays enabled.",
            regenerationDownloadsES: "Se puede reinstalar descargando la extensión desde el catálogo del editor cuando la necesites.",
            regenerationDownloadsEN: "Reinstalling downloads the extension again from the editor's marketplace.",
            regenerationGoneES: nil,
            regenerationGoneEN: nil
        ),
        "app_caches": FamilyCopy(
            id: "app_caches",
            titleES: "Cachés de aplicaciones",
            titleEN: "App caches",
            defaultBehavior: .rebuilds,
            whatItIsES: "Cachés temporales de aplicaciones (miniaturas, datos web, shaders o recursos precargados).",
            whatItIsEN: "Temporary app caches (thumbnails, network cache, shaders, or preloaded resources).",
            whatIsLostES: "Datos temporales de aceleración; normalmente no incluye documentos ni preferencias principales.",
            whatIsLostEN: "Speed-up cache entries only; normally excludes personal documents and core preferences.",
            regenerationRebuildsES: "La aplicación los regenera automáticamente al volver a abrirse; las primeras cargas pueden ser algo más lentas.",
            regenerationRebuildsEN: "The application regenerates these caches automatically on next launch; initial loads may feel slightly slower.",
            regenerationDownloadsES: "La aplicación volverá a descargar estos recursos desde Internet según los necesite.",
            regenerationDownloadsEN: "The app will re-download cached remote assets on demand when needed again.",
            regenerationGoneES: "Los datos cacheados ya antiguos no vuelven; la app solo escribirá caché nueva en sesiones futuras.",
            regenerationGoneEN: "Older cache files do not come back; the app only writes fresh cache during future use."
        ),
        "agent_editor_history": FamilyCopy(
            id: "agent_editor_history",
            titleES: "Historial de agentes y editores",
            titleEN: "Agent and editor history",
            defaultBehavior: .gone,
            whatItIsES: "Transcripciones locales, sesiones de trabajo o historiales almacenados por editores y asistentes.",
            whatItIsEN: "Local session transcripts, workspaces, or history retained by editors and coding agents.",
            whatIsLostES: "Conversaciones, trazas y contexto local previo de esas sesiones.",
            whatIsLostEN: "Past conversation transcripts, traces, and local context from those sessions.",
            regenerationRebuildsES: nil,
            regenerationRebuildsEN: nil,
            regenerationDownloadsES: nil,
            regenerationDownloadsEN: nil,
            regenerationGoneES: "No se regenera automáticamente; el historial local eliminado desaparece de forma permanente.",
            regenerationGoneEN: "Does not come back automatically; deleted local session history is gone permanently."
        ),
        "agent_worktrees": FamilyCopy(
            id: "agent_worktrees",
            titleES: "Worktrees y entornos de agentes",
            titleEN: "Agent worktrees",
            defaultBehavior: .gone,
            whatItIsES: "Árboles de trabajo aislados o cachés de entorno creadas para tareas de agentes de código.",
            whatItIsEN: "Isolated working trees or environment caches created by coding agents.",
            whatIsLostES: "Cambios locales no confirmados o el estado temporal de ese entorno aislado.",
            whatIsLostEN: "Uncommitted local edits or the temporary environment state kept inside that folder.",
            regenerationRebuildsES: "El agente puede recrear el entorno limpio al iniciar una nueva tarea, sin cambios locales no guardados.",
            regenerationRebuildsEN: "The agent recreates a clean workspace when starting a task, without prior uncommitted edits.",
            regenerationDownloadsES: "Los paquetes base pueden volver a descargarse, pero los cambios locales sin guardar no regresan.",
            regenerationDownloadsEN: "Base environment files can be fetched again, though uncommitted local work will not return.",
            regenerationGoneES: "No vuelve automáticamente; cualquier cambio o rama temporal sin guardar en ese worktree se pierde.",
            regenerationGoneEN: "Does not return automatically; uncommitted work or temporary branches in that tree are permanently lost."
        ),
        "app_leftovers": FamilyCopy(
            id: "app_leftovers",
            titleES: "Restos de aplicaciones",
            titleEN: "App leftovers",
            defaultBehavior: .gone,
            whatItIsES: "Carpetas en Library asociadas por nombre o identificador a aplicaciones que pueden seguir instaladas o haberse retirado.",
            whatItIsEN: "Folders in Library linked by name or bundle ID to apps that may still be installed or already removed.",
            whatIsLostES: "Preferencias, soporte local o estado guardado de esa aplicación si aún la utilizas.",
            whatIsLostEN: "Local settings, saved state, or app support data if the application is still used or reinstalled.",
            regenerationRebuildsES: "Si la aplicación sigue instalada y se abre, creará archivos nuevos con valores predeterminados.",
            regenerationRebuildsEN: "If the app still runs later, it will create fresh files with default settings.",
            regenerationDownloadsES: nil,
            regenerationDownloadsEN: nil,
            regenerationGoneES: "No regresa si la app ya no existe; si vuelves a instalarla empezará sin estos ajustes locales.",
            regenerationGoneEN: "Does not return if the app is gone; reinstalling the app later starts without these local settings."
        ),
        "downloads_installers": FamilyCopy(
            id: "downloads_installers",
            titleES: "Descargas e instaladores",
            titleEN: "Downloads and installers",
            defaultBehavior: .gone,
            whatItIsES: "Instaladores (.dmg, .pkg, imágenes ISO) o descargas guardadas en disco tras instalarse o revisarse.",
            whatItIsEN: "Downloaded installers (.dmg, .pkg, ISO images) or files stored locally awaiting review.",
            whatIsLostES: "Ese archivo concreto en tu carpeta de usuario; las apps ya copiadas a Aplicaciones no se ven afectadas.",
            whatIsLostEN: "This local file only; apps already copied into Applications continue working normally.",
            regenerationRebuildsES: nil,
            regenerationRebuildsEN: nil,
            regenerationDownloadsES: "No vuelve solo: si lo necesitas en el futuro tendrás que descargarlo otra vez desde su origen.",
            regenerationDownloadsEN: "Does not return on its own: if needed later, you will have to download it again from its source.",
            regenerationGoneES: "Es un archivo único en este volumen y no se regenera automáticamente si lo eliminas.",
            regenerationGoneEN: "Unique local file on this disk; it is permanently removed unless backed up elsewhere."
        ),
        "logs_crash_reports": FamilyCopy(
            id: "logs_crash_reports",
            titleES: "Registros e informes de fallo",
            titleEN: "Logs and crash reports",
            defaultBehavior: .gone,
            whatItIsES: "Trazas históricas, logs rotados e informes de fallo guardados por macOS o por aplicaciones.",
            whatItIsEN: "Diagnostic logs, rotated traces, and crash reports stored by macOS or apps.",
            whatIsLostES: "Evidencia de errores pasados útil solo si estás diagnosticando un fallo reciente.",
            whatIsLostEN: "Historical error traces useful mainly if you are troubleshooting a recent failure.",
            regenerationRebuildsES: "Los registros anteriores no reaparecen; las aplicaciones solo escribirán registros nuevos ante futuros eventos.",
            regenerationRebuildsEN: "Older log entries do not come back; apps only write fresh logs for future events.",
            regenerationDownloadsES: nil,
            regenerationDownloadsEN: nil,
            regenerationGoneES: "Los registros históricos eliminados no se recuperan; en adelante solo se crearán archivos para eventos nuevos.",
            regenerationGoneEN: "Removed historical logs are permanently gone; only future activity creates new log entries."
        ),
        "temporary_files": FamilyCopy(
            id: "temporary_files",
            titleES: "Archivos temporales",
            titleEN: "Temporary files",
            defaultBehavior: .rebuilds,
            whatItIsES: "Directorios de intercambio, copias temporales o archivos transitorios de procesos.",
            whatItIsEN: "Scratch folders, transient staging directories, or temporary process files.",
            whatIsLostES: "Datos temporales de ejecución; evita retirar elementos que un proceso activo esté usando ahora.",
            whatIsLostEN: "Transient working state; avoid removing items currently held by a running process.",
            regenerationRebuildsES: "Cualquier proceso que necesite espacio temporal creará nuevos archivos al volver a ejecutarse.",
            regenerationRebuildsEN: "Any tool that needs temporary space creates fresh scratch files automatically on its next run.",
            regenerationDownloadsES: nil,
            regenerationDownloadsEN: nil,
            regenerationGoneES: "El contenido antiguo no regresa; las ejecuciones futuras crearán archivos temporales nuevos si les hacen falta.",
            regenerationGoneEN: "Old scratch contents do not return; future runs allocate fresh temporary files if needed."
        ),
        "trash": FamilyCopy(
            id: "trash",
            titleES: "Papelera",
            titleEN: "Trash",
            defaultBehavior: .gone,
            whatItIsES: "Elementos movidos previamente a la Papelera que todavía ocupan espacio en este volumen.",
            whatItIsEN: "Items already moved to Trash that still occupy space on disk.",
            whatIsLostES: "La opción de restaurar directamente esos archivos desde la Papelera.",
            whatIsLostEN: "The ability to restore those discarded items back out of Trash.",
            regenerationRebuildsES: nil,
            regenerationRebuildsEN: nil,
            regenerationDownloadsES: nil,
            regenerationDownloadsEN: nil,
            regenerationGoneES: "Vaciarlo los elimina de forma definitiva y no vuelven automáticamente.",
            regenerationGoneEN: "Once emptied, items are permanently erased and cannot be regenerated."
        ),
        "backups_archives": FamilyCopy(
            id: "backups_archives",
            titleES: "Copias y archivos comprimidos",
            titleEN: "Backups and archives",
            defaultBehavior: .gone,
            whatItIsES: "Respaldos locales de dispositivos, paquetes comprimidos o instantáneas guardadas en disco.",
            whatItIsEN: "Local device backups, compressed archives, or packaged snapshots kept on this Mac.",
            whatIsLostES: "Ese respaldo completo o archivo histórico si no dispones de otra copia externa o en la nube.",
            whatIsLostEN: "That backup snapshot or archive unless another copy exists externally or in cloud storage.",
            regenerationRebuildsES: nil,
            regenerationRebuildsEN: nil,
            regenerationDownloadsES: nil,
            regenerationDownloadsEN: nil,
            regenerationGoneES: "No se regenera; recuperar esa copia exige haberla respaldado antes o crear una nueva desde cero.",
            regenerationGoneEN: "Does not regenerate; only creating a brand-new backup later produces fresh state without old snapshots."
        ),
        "chat_attachments": FamilyCopy(
            id: "chat_attachments",
            titleES: "Adjuntos de mensajería",
            titleEN: "Chat attachments",
            defaultBehavior: .gone,
            whatItIsES: "Copias locales de fotos, vídeos y documentos descargados dentro de clientes de mensajería.",
            whatItIsEN: "Local copies of images, videos, and documents cached by messaging clients.",
            whatIsLostES: "La copia descargada en este Mac; su disponibilidad posterior depende de si el servidor del chat aún la conserva.",
            whatIsLostEN: "The local copy on this Mac; whether it stays available depends on the chat server retaining older media.",
            regenerationRebuildsES: nil,
            regenerationRebuildsEN: nil,
            regenerationDownloadsES: "Solo podrá descargarse de nuevo desde la conversación si el servicio remoto sigue alojando ese adjunto.",
            regenerationDownloadsEN: "Can only be re-downloaded from the chat if the remote messaging server still retains the file.",
            regenerationGoneES: "No se regenera en local; si no está en la nube del servicio o en una copia, no se recuperará.",
            regenerationGoneEN: "Does not regenerate locally; without server retention or a backup, the attachment is permanently lost."
        ),
        "podcast_media_downloads": FamilyCopy(
            id: "podcast_media_downloads",
            titleES: "Descargas de audio y vídeo",
            titleEN: "Podcast and media downloads",
            defaultBehavior: .downloads,
            whatItIsES: "Episodios o contenido multimedia descargado para escuchar o ver sin conexión.",
            whatItIsEN: "Offline podcast episodes or media files downloaded for local playback.",
            whatIsLostES: "La reproducción offline de esos archivos en este equipo; tus suscripciones o biblioteca siguen igual.",
            whatIsLostEN: "Offline playback copies on this Mac; your subscriptions and cloud library remain unchanged.",
            regenerationRebuildsES: nil,
            regenerationRebuildsEN: nil,
            regenerationDownloadsES: "Se puede descargar de nuevo en cualquier momento mientras siga publicado en su feed o servicio.",
            regenerationDownloadsEN: "Can be downloaded again anytime while the episode or item stays published on the service.",
            regenerationGoneES: nil,
            regenerationGoneEN: nil
        ),
        "render_preview_files": FamilyCopy(
            id: "render_preview_files",
            titleES: "Renders y previsualizaciones",
            titleEN: "Render and preview files",
            defaultBehavior: .rebuilds,
            whatItIsES: "Cachés de renderizado, líneas de tiempo, proxies y miniaturas generados por suites creativas.",
            whatItIsEN: "Render caches, timeline previews, proxy media, and thumbnails built by creative apps.",
            whatIsLostES: "Previsualizaciones ya procesadas; los proyectos de edición y ficheros originales permanecen intactos.",
            whatIsLostEN: "Pre-rendered cache files only; original media assets and project files remain intact.",
            regenerationRebuildsES: "El editor vuelve a generar estos renders al abrir el proyecto, consumiendo tiempo de CPU/GPU.",
            regenerationRebuildsEN: "The creative app re-renders these previews on project open or playback, using CPU/GPU time.",
            regenerationDownloadsES: nil,
            regenerationDownloadsEN: nil,
            regenerationGoneES: nil,
            regenerationGoneEN: nil
        ),
        "sound_libraries": FamilyCopy(
            id: "sound_libraries",
            titleES: "Bibliotecas de sonido",
            titleEN: "Sound libraries",
            defaultBehavior: .downloads,
            whatItIsES: "Paquetes de muestras, bucles e instrumentos para apps de audio y producción musical.",
            whatItIsEN: "Large instrument packs, loops, and audio sample libraries for music and sound software.",
            whatIsLostES: "Los instrumentos y sonidos descargados en local hasta que vuelvas a instalarlos.",
            whatIsLostEN: "Those downloaded instruments and sound packs until reinstalled locally.",
            regenerationRebuildsES: nil,
            regenerationRebuildsEN: nil,
            regenerationDownloadsES: "Pueden descargarse de nuevo desde el gestor de contenido de la aplicación, aunque su tamaño es grande.",
            regenerationDownloadsEN: "Can be re-downloaded from the app's content manager, though restoring full packs takes significant bandwidth.",
            regenerationGoneES: nil,
            regenerationGoneEN: nil
        ),
        "games": FamilyCopy(
            id: "games",
            titleES: "Juegos y sus recursos",
            titleEN: "Games",
            defaultBehavior: .downloads,
            whatItIsES: "Instalaciones completas de juegos o bibliotecas de recursos gestionadas por launchers.",
            whatItIsEN: "Installed game packages and asset stores managed by game launchers.",
            whatIsLostES: "Archivos del juego en disco; comprueba si tus partidas están sincronizadas en la nube antes de retirar nada.",
            whatIsLostEN: "Local game assets; confirm whether save games sync to the cloud before removing local files.",
            regenerationRebuildsES: nil,
            regenerationRebuildsEN: nil,
            regenerationDownloadsES: "Volver a jugar requerirá descargar de nuevo decenas de gigabytes desde su plataforma.",
            regenerationDownloadsEN: "Playing again requires re-downloading the full game package from its launcher.",
            regenerationGoneES: nil,
            regenerationGoneEN: nil
        ),
        "large_media_files": FamilyCopy(
            id: "large_media_files",
            titleES: "Archivos multimedia grandes",
            titleEN: "Large media files",
            defaultBehavior: .gone,
            whatItIsES: "Grabaciones, exportaciones de vídeo o archivos multimedia personales de gran tamaño.",
            whatItIsEN: "Recordings, video exports, or large personal media assets stored in user folders.",
            whatIsLostES: "El archivo original en sí mismo si no dispones de otra copia de seguridad.",
            whatIsLostEN: "The original media file itself unless a secondary backup exists.",
            regenerationRebuildsES: nil,
            regenerationRebuildsEN: nil,
            regenerationDownloadsES: nil,
            regenerationDownloadsEN: nil,
            regenerationGoneES: "No se regenera automáticamente; trátalo como contenido personal único.",
            regenerationGoneEN: "Does not regenerate automatically; treat this as unique personal media."
        ),
        "never_touched": FamilyCopy(
            id: "never_touched",
            titleES: "Elemento protegido",
            titleEN: "Protected item",
            defaultBehavior: .gone,
            whatItIsES: "Datos críticos del usuario o de macOS que Brisa inspecciona únicamente para mostrar uso de disco.",
            whatItIsEN: "Critical user or macOS directories inspected strictly for read-only storage reporting.",
            whatIsLostES: "Retirarlos podría romper sesiones, credenciales o la estabilidad del sistema.",
            whatIsLostEN: "Removing these could break user accounts, credentials, or macOS stability.",
            regenerationRebuildsES: nil,
            regenerationRebuildsEN: nil,
            regenerationDownloadsES: nil,
            regenerationDownloadsEN: nil,
            regenerationGoneES: "Brisa bloquea su selección para impedir borrados irreversibles o inseguros.",
            regenerationGoneEN: "Brisa keeps selection locked to prevent irreversible or unsafe removal."
        )
    ]
}
