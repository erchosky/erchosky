import Foundation

public enum DockerAvailabilityStatus: String, Codable, Sendable, Equatable {
    case cliUnavailable = "cli_unavailable"
    case daemonUnavailable = "daemon_unavailable"
    case permissionDenied = "permission_denied"
    case ready = "ready"

    public func localizedLabel(_ language: AppLanguage) -> String {
        let resolved = AppLanguage.resolve(preference: language.rawValue)
        switch (self, resolved) {
        case (.cliUnavailable, .es): return "CLI de Docker no instalado"
        case (.cliUnavailable, _): return "Docker CLI not installed"
        case (.daemonUnavailable, .es): return "Motor de Docker detenido o inaccesible"
        case (.daemonUnavailable, _): return "Docker engine stopped or unreachable"
        case (.permissionDenied, .es): return "Permiso denegado al socket de Docker"
        case (.permissionDenied, _): return "Permission denied on Docker socket"
        case (.ready, .es): return "Cliente y motor disponibles"
        case (.ready, _): return "Client and engine available"
        }
    }
}

public enum DockerResourceKind: String, Codable, Sendable, Equatable {
    case image = "image"
    case stoppedContainer = "stopped_container"
    case runningContainer = "running_container"
    case buildCache = "build_cache"
    case volume = "volume"
}

public enum DockerBuildCachePruneScope: String, Codable, Sendable, Equatable, CaseIterable {
    case reclaimableOnly = "reclaimable_only"
    case all = "all"

    public func localizedTitle(_ language: AppLanguage) -> String {
        let resolved = AppLanguage.resolve(preference: language.rawValue)
        switch (self, resolved) {
        case (.reclaimableOnly, .es): return "Caché de compilación recuperable"
        case (.reclaimableOnly, _): return "Reclaimable build cache"
        case (.all, .es): return "Toda la caché de compilación (--all)"
        case (.all, _): return "All build cache (--all)"
        }
    }

    public func localizedScopeDescription(_ language: AppLanguage) -> String {
        let resolved = AppLanguage.resolve(preference: language.rawValue)
        switch (self, resolved) {
        case (.reclaimableOnly, .es):
            return "Elimina únicamente entradas de caché BuildKit recuperables (docker builder prune --force); conserva capas compartidas en uso."
        case (.reclaimableOnly, _):
            return "Removes only reclaimable BuildKit cache entries (docker builder prune --force); preserves shared layers in use."
        case (.all, .es):
            return "Elimina toda la caché de compilación, incluidas capas e imágenes internas del builder (docker builder prune --all --force)."
        case (.all, _):
            return "Removes all build cache including internal builder layers and frontend images (docker builder prune --all --force)."
        }
    }
}

public struct DockerCategorySummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String { typeName }
    public let typeName: String
    public let totalCount: Int
    public let activeCount: Int
    public let sizeBytes: Int64
    public let reclaimableBytes: Int64
    public let reclaimablePercent: Double?
    public let rawSizeText: String
    public let rawReclaimableText: String

    public init(
        typeName: String,
        totalCount: Int,
        activeCount: Int,
        sizeBytes: Int64,
        reclaimableBytes: Int64,
        reclaimablePercent: Double?,
        rawSizeText: String,
        rawReclaimableText: String
    ) {
        self.typeName = typeName
        self.totalCount = totalCount
        self.activeCount = activeCount
        self.sizeBytes = sizeBytes
        self.reclaimableBytes = reclaimableBytes
        self.reclaimablePercent = reclaimablePercent
        self.rawSizeText = rawSizeText
        self.rawReclaimableText = rawReclaimableText
    }
}

public struct DockerImageResource: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let shortID: String
    public let repository: String
    public let tag: String
    public let digest: String
    public let createdAt: String
    public let createdSince: String
    public let virtualSizeBytes: Int64
    public let sharedBytes: Int64
    public let uniqueBytes: Int64
    public let containerCount: Int
    public let referencingContainerIDs: [String]
    public let referencingContainerNames: [String]
    public let isUsedByRunningContainer: Bool

    public var displayName: String {
        let repo = repository.isEmpty || repository == "<none>" ? shortID : repository
        if !tag.isEmpty && tag != "<none>" {
            return "\(repo):\(tag)"
        }
        return repo
    }

    public init(
        id: String,
        shortID: String,
        repository: String,
        tag: String,
        digest: String,
        createdAt: String,
        createdSince: String,
        virtualSizeBytes: Int64,
        sharedBytes: Int64,
        uniqueBytes: Int64,
        containerCount: Int,
        referencingContainerIDs: [String],
        referencingContainerNames: [String],
        isUsedByRunningContainer: Bool
    ) {
        self.id = id
        self.shortID = shortID
        self.repository = repository
        self.tag = tag
        self.digest = digest
        self.createdAt = createdAt
        self.createdSince = createdSince
        self.virtualSizeBytes = virtualSizeBytes
        self.sharedBytes = sharedBytes
        self.uniqueBytes = uniqueBytes
        self.containerCount = containerCount
        self.referencingContainerIDs = referencingContainerIDs
        self.referencingContainerNames = referencingContainerNames
        self.isUsedByRunningContainer = isUsedByRunningContainer
    }
}

public struct DockerContainerResource: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let shortID: String
    public let name: String
    public let imageName: String
    public let imageID: String
    public let state: String
    public let statusText: String
    public let createdAt: String
    public let writableSizeBytes: Int64
    public let virtualSizeBytes: Int64
    public let mountedVolumeNames: [String]
    public let isRunning: Bool

    public init(
        id: String,
        shortID: String,
        name: String,
        imageName: String,
        imageID: String,
        state: String,
        statusText: String,
        createdAt: String,
        writableSizeBytes: Int64,
        virtualSizeBytes: Int64,
        mountedVolumeNames: [String],
        isRunning: Bool
    ) {
        self.id = id
        self.shortID = shortID
        self.name = name
        self.imageName = imageName
        self.imageID = imageID
        self.state = state
        self.statusText = statusText
        self.createdAt = createdAt
        self.writableSizeBytes = writableSizeBytes
        self.virtualSizeBytes = virtualSizeBytes
        self.mountedVolumeNames = mountedVolumeNames
        self.isRunning = isRunning
    }
}

public struct DockerBuildCacheRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let recordType: String
    public let description: String
    public let sizeBytes: Int64
    public let shared: Bool
    public let reclaimable: Bool
    public let mutable: Bool
    public let usageCount: Int
    public let createdAt: String
    public let lastUsedAt: String
    public let parents: [String]

    public init(
        id: String,
        recordType: String,
        description: String,
        sizeBytes: Int64,
        shared: Bool,
        reclaimable: Bool,
        mutable: Bool,
        usageCount: Int,
        createdAt: String,
        lastUsedAt: String,
        parents: [String]
    ) {
        self.id = id
        self.recordType = recordType
        self.description = description
        self.sizeBytes = sizeBytes
        self.shared = shared
        self.reclaimable = reclaimable
        self.mutable = mutable
        self.usageCount = usageCount
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.parents = parents
    }
}

public struct DockerVolumeResource: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let driver: String
    public let scope: String
    public let mountpoint: String
    public let labels: String
    public let sizeBytes: Int64
    public let linkCount: Int
    public let mountedByContainerIDs: [String]
    public let mountedByContainerNames: [String]
    public let isMountedByRunningContainer: Bool
    public let protectedByDefault: Bool

    public init(
        name: String,
        driver: String,
        scope: String,
        mountpoint: String,
        labels: String,
        sizeBytes: Int64,
        linkCount: Int,
        mountedByContainerIDs: [String],
        mountedByContainerNames: [String],
        isMountedByRunningContainer: Bool,
        protectedByDefault: Bool = true
    ) {
        self.name = name
        self.driver = driver
        self.scope = scope
        self.mountpoint = mountpoint
        self.labels = labels
        self.sizeBytes = sizeBytes
        self.linkCount = linkCount
        self.mountedByContainerIDs = mountedByContainerIDs
        self.mountedByContainerNames = mountedByContainerNames
        self.isMountedByRunningContainer = isMountedByRunningContainer
        self.protectedByDefault = protectedByDefault
    }
}

public struct DockerInspectionSnapshot: Codable, Sendable, Equatable {
    public let status: DockerAvailabilityStatus
    public let executablePath: String?
    public let clientVersion: String?
    public let serverVersion: String?
    public let builderName: String?
    public let statusDetailES: String
    public let statusDetailEN: String
    public let summaries: [DockerCategorySummary]
    public let images: [DockerImageResource]
    public let containers: [DockerContainerResource]
    public let buildCacheRecords: [DockerBuildCacheRecord]
    public let volumes: [DockerVolumeResource]
    public let inspectedAt: Date

    public var stoppedContainers: [DockerContainerResource] {
        containers.filter { !$0.isRunning }
    }

    public var runningContainers: [DockerContainerResource] {
        containers.filter(\.isRunning)
    }

    public var totalReclaimableEstimateBytes: Int64 {
        let summaryReclaimable = summaries.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        if summaryReclaimable > 0 {
            return summaryReclaimable
        }
        let buildCache = buildCacheRecords.filter(\.reclaimable).reduce(Int64(0)) { $0 + $1.sizeBytes }
        let stopped = stoppedContainers.reduce(Int64(0)) { $0 + $1.writableSizeBytes }
        let unusedImages = images.filter { $0.referencingContainerIDs.isEmpty }.reduce(Int64(0)) {
            $0 + ($1.uniqueBytes > 0 ? $1.uniqueBytes : $1.virtualSizeBytes)
        }
        return buildCache + stopped + unusedImages
    }

    public init(
        status: DockerAvailabilityStatus,
        executablePath: String?,
        clientVersion: String?,
        serverVersion: String?,
        builderName: String?,
        statusDetailES: String,
        statusDetailEN: String,
        summaries: [DockerCategorySummary],
        images: [DockerImageResource],
        containers: [DockerContainerResource],
        buildCacheRecords: [DockerBuildCacheRecord],
        volumes: [DockerVolumeResource],
        inspectedAt: Date = Date()
    ) {
        self.status = status
        self.executablePath = executablePath
        self.clientVersion = clientVersion
        self.serverVersion = serverVersion
        self.builderName = builderName
        self.statusDetailES = statusDetailES
        self.statusDetailEN = statusDetailEN
        self.summaries = summaries
        self.images = images
        self.containers = containers
        self.buildCacheRecords = buildCacheRecords
        self.volumes = volumes
        self.inspectedAt = inspectedAt
    }
}

public struct DockerCleanupSelection: Codable, Sendable, Equatable {
    public var containerIDs: [String]
    public var imageIDs: [String]
    public var volumeNames: [String]
    public var unlockedVolumeNames: Set<String>
    public var buildCacheScope: DockerBuildCachePruneScope?

    public var isEmpty: Bool {
        containerIDs.isEmpty && imageIDs.isEmpty && volumeNames.isEmpty && buildCacheScope == nil
    }

    public init(
        containerIDs: [String] = [],
        imageIDs: [String] = [],
        volumeNames: [String] = [],
        unlockedVolumeNames: Set<String> = [],
        buildCacheScope: DockerBuildCachePruneScope? = nil
    ) {
        self.containerIDs = containerIDs
        self.imageIDs = imageIDs
        self.volumeNames = volumeNames
        self.unlockedVolumeNames = unlockedVolumeNames
        self.buildCacheScope = buildCacheScope
    }
}

public struct DockerCleanupExecutionResult: Sendable, Equatable {
    public let plan: OperationPlan
    public let report: OperationExecutionReport
    public let removedContainerIDs: [String]
    public let removedImageIDs: [String]
    public let removedVolumeNames: [String]
    public let prunedBuildCacheScope: DockerBuildCachePruneScope?
    public let skippedReasons: [String]

    public init(
        plan: OperationPlan,
        report: OperationExecutionReport,
        removedContainerIDs: [String],
        removedImageIDs: [String],
        removedVolumeNames: [String],
        prunedBuildCacheScope: DockerBuildCachePruneScope?,
        skippedReasons: [String]
    ) {
        self.plan = plan
        self.report = report
        self.removedContainerIDs = removedContainerIDs
        self.removedImageIDs = removedImageIDs
        self.removedVolumeNames = removedVolumeNames
        self.prunedBuildCacheScope = prunedBuildCacheScope
        self.skippedReasons = skippedReasons
    }
}

public struct DockerManager: Sendable {
    private let executor: any CommandExecuting
    private let home: String
    private let journal: Journal?
    private let executableOverride: String?
    private let timeoutSeconds: TimeInterval

    public init(
        executor: any CommandExecuting = LiveCommandExecutor(),
        home: String = NSHomeDirectory(),
        journal: Journal? = nil,
        executableOverride: String? = nil,
        timeoutSeconds: TimeInterval = 20
    ) {
        self.executor = executor
        self.home = Paths.normalized(home)
        self.journal = journal
        self.executableOverride = executableOverride
        self.timeoutSeconds = timeoutSeconds
    }

    // MARK: - Inspection

    public func inspect(control: ScanControl? = nil) -> DockerInspectionSnapshot {
        guard let dockerPath = resolveDockerExecutable() else {
            return DockerInspectionSnapshot(
                status: .cliUnavailable,
                executablePath: nil,
                clientVersion: nil,
                serverVersion: nil,
                builderName: nil,
                statusDetailES: "No se encontró el binario docker en las rutas habituales.",
                statusDetailEN: "The docker binary was not found in standard locations.",
                summaries: [],
                images: [],
                containers: [],
                buildCacheRecords: [],
                volumes: []
            )
        }

        let clientVersionBox = LockedBox<CommandResult?>(nil)
        let infoOutcomeBox = LockedBox<Result<CommandResult, Error>>(.failure(BrisaError.unavailable("Docker engine unreachable")))
        let probeGroup = DispatchGroup()
        let probeQueue = DispatchQueue.global(qos: .userInitiated)

        probeGroup.enter()
        probeQueue.async {
            clientVersionBox.set(try? self.runDocker(
                executable: dockerPath,
                arguments: ["version", "--format", "{{.Client.Version}}"],
                control: control
            ))
            probeGroup.leave()
        }

        probeGroup.enter()
        probeQueue.async {
            let outcome: Result<CommandResult, Error>
            do {
                outcome = .success(try self.runDocker(
                    executable: dockerPath,
                    arguments: ["info", "--format", "{{json .ServerVersion}}"],
                    control: control
                ))
            } catch {
                outcome = .failure(error)
            }
            infoOutcomeBox.set(outcome)
            probeGroup.leave()
        }
        probeGroup.wait()

        let clientVersion = normalizedTrimmed(clientVersionBox.get()?.output)

        let infoResult: CommandResult
        switch infoOutcomeBox.get() {
        case let .success(result):
            infoResult = result
        case let .failure(error):
            return DockerInspectionSnapshot(
                status: .daemonUnavailable,
                executablePath: dockerPath,
                clientVersion: clientVersion,
                serverVersion: nil,
                builderName: nil,
                statusDetailES: "No se pudo consultar el motor de Docker: \(error.localizedDescription)",
                statusDetailEN: "Unable to query Docker engine: \(error.localizedDescription)",
                summaries: [],
                images: [],
                containers: [],
                buildCacheRecords: [],
                volumes: []
            )
        }

        if infoResult.timedOut {
            return DockerInspectionSnapshot(
                status: .daemonUnavailable,
                executablePath: dockerPath,
                clientVersion: clientVersion,
                serverVersion: nil,
                builderName: nil,
                statusDetailES: "El motor de Docker no respondió antes del tiempo límite.",
                statusDetailEN: "Docker engine did not respond before the timeout.",
                summaries: [],
                images: [],
                containers: [],
                buildCacheRecords: [],
                volumes: []
            )
        }

        if infoResult.status != 0 {
            let errText = infoResult.error.isEmpty ? infoResult.output : infoResult.error
            let lowered = errText.lowercased()
            let status: DockerAvailabilityStatus = lowered.contains("permission denied")
                ? .permissionDenied
                : .daemonUnavailable
            let detailES = status == .permissionDenied
                ? "El usuario actual no tiene permiso para acceder al socket de Docker."
                : "El cliente Docker está instalado, pero el motor está detenido o inaccesible."
            let detailEN = status == .permissionDenied
                ? "The current user does not have permission to access the Docker socket."
                : "Docker CLI is installed, but the engine is stopped or unreachable."
            let trimmedErr = errText.trimmingCharacters(in: .whitespacesAndNewlines)
            return DockerInspectionSnapshot(
                status: status,
                executablePath: dockerPath,
                clientVersion: clientVersion,
                serverVersion: nil,
                builderName: nil,
                statusDetailES: trimmedErr.isEmpty ? detailES : "\(detailES) \(trimmedErr)",
                statusDetailEN: trimmedErr.isEmpty ? detailEN : "\(detailEN) \(trimmedErr)",
                summaries: [],
                images: [],
                containers: [],
                buildCacheRecords: [],
                volumes: []
            )
        }

        let serverVersion = decodeJSONString(infoResult.output) ?? normalizedTrimmed(infoResult.output)

        let summaryBox = LockedBox<CommandResult?>(nil)
        let verboseDFBox = LockedBox<CommandResult?>(nil)
        let psBox = LockedBox<CommandResult?>(nil)
        let inspectBox = LockedBox<CommandResult?>(nil)
        let imagesBox = LockedBox<CommandResult?>(nil)
        let volumesBox = LockedBox<CommandResult?>(nil)
        let builderBox = LockedBox<CommandResult?>(nil)

        let queryGroup = DispatchGroup()
        let queryQueue = DispatchQueue.global(qos: .userInitiated)
        let semaphore = DispatchSemaphore(value: 4)

        func enqueueQuery(_ work: @escaping @Sendable () -> Void) {
            queryGroup.enter()
            queryQueue.async {
                semaphore.wait()
                defer { semaphore.signal(); queryGroup.leave() }
                guard control?.shouldStop != true else { return }
                work()
            }
        }

        enqueueQuery {
            summaryBox.set(try? self.runDocker(executable: dockerPath, arguments: ["system", "df", "--format", "json"], control: control))
        }
        enqueueQuery {
            verboseDFBox.set(try? self.runDocker(executable: dockerPath, arguments: ["system", "df", "-v", "--format", "json"], control: control))
        }
        enqueueQuery {
            let psRes = try? self.runDocker(executable: dockerPath, arguments: ["ps", "-a", "--format", "json", "--no-trunc"], control: control)
            psBox.set(psRes)
            let rawIDs = self.parseContainersNDJSON(psRes?.output ?? "").compactMap(\.id)
            if !rawIDs.isEmpty, control?.shouldStop != true {
                inspectBox.set(try? self.runDocker(
                    executable: dockerPath,
                    arguments: ["inspect", "--format", "json"] + rawIDs,
                    control: control
                ))
            }
        }
        enqueueQuery {
            imagesBox.set(try? self.runDocker(executable: dockerPath, arguments: ["image", "ls", "--format", "json", "--no-trunc"], control: control))
        }
        enqueueQuery {
            volumesBox.set(try? self.runDocker(executable: dockerPath, arguments: ["volume", "ls", "--format", "json"], control: control))
        }
        enqueueQuery {
            builderBox.set(try? self.runDocker(executable: dockerPath, arguments: ["builder", "du", "--format", "json"], control: control))
        }
        queryGroup.wait()

        let summaries = parseSystemDFSummary(summaryBox.get()?.output ?? "")
        let verboseDetails = parseVerboseSystemDF(verboseDFBox.get()?.output ?? "")
        let rawContainers = parseContainersNDJSON(psBox.get()?.output ?? "")
        var inspectMap: [String: DockerContainerInspectInfo] = [:]
        if let inspectResult = inspectBox.get(), inspectResult.status == 0 {
            inspectMap = parseContainerInspect(inspectResult.output)
        }

        let containers = buildContainers(
            rawContainers: rawContainers,
            inspectMap: inspectMap,
            verboseDetails: verboseDetails
        )

        let rawImages = parseImagesNDJSON(imagesBox.get()?.output ?? "")
        let images = buildImages(
            rawImages: rawImages,
            verboseDetails: verboseDetails,
            containers: containers
        )

        let rawVolumes = parseVolumesNDJSON(volumesBox.get()?.output ?? "")
        let volumes = buildVolumes(
            rawVolumes: rawVolumes,
            verboseDetails: verboseDetails,
            containers: containers
        )

        let buildCacheRecords = parseBuildCacheNDJSON(builderBox.get()?.output ?? "")

        return DockerInspectionSnapshot(
            status: .ready,
            executablePath: dockerPath,
            clientVersion: clientVersion,
            serverVersion: serverVersion,
            builderName: nil,
            statusDetailES: "Docker listo (cliente \(clientVersion ?? "—"), motor \(serverVersion ?? "—")).",
            statusDetailEN: "Docker ready (client \(clientVersion ?? "—"), engine \(serverVersion ?? "—")).",
            summaries: summaries,
            images: images,
            containers: containers,
            buildCacheRecords: buildCacheRecords,
            volumes: volumes
        )
    }

    // MARK: - Planning

    public func buildPlan(
        snapshot: DockerInspectionSnapshot,
        selection: DockerCleanupSelection
    ) -> OperationPlan {
        var resources: [OperationAffectedResource] = []
        var blockers: [OperationBlocker] = []

        if snapshot.status != .ready {
            blockers.append(OperationBlocker(
                id: "docker_\(snapshot.status.rawValue)",
                resourceID: nil,
                reasonES: snapshot.statusDetailES,
                reasonEN: snapshot.statusDetailEN,
                canRecheck: true
            ))
        }

        let selectedContainerSet = Set(selection.containerIDs)
        let selectedVolumeSet = Set(selection.volumeNames)

        let containerByID = Dictionary(uniqueKeysWithValues: snapshot.containers.map { ($0.id, $0) })
        let imageByID = Dictionary(uniqueKeysWithValues: snapshot.images.map { ($0.id, $0) })
        let volumeByName = Dictionary(uniqueKeysWithValues: snapshot.volumes.map { ($0.name, $0) })

        var totalNominalBytes: Int64 = 0
        var totalEstimatedReclaimableBytes: Int64 = 0

        // 1. Containers
        for containerID in selection.containerIDs {
            guard let container = containerByID[containerID] else {
                blockers.append(OperationBlocker(
                    id: "missing_container:\(containerID)",
                    resourceID: containerID,
                    reasonES: "El contenedor \(containerID) ya no existe en el último estado inspeccionado.",
                    reasonEN: "Container \(containerID) no longer exists in the latest inspected state.",
                    canRecheck: true
                ))
                continue
            }
            var blockedES: String?
            var blockedEN: String?
            if container.isRunning {
                blockedES = "El contenedor «\(container.name)» está en ejecución (\(container.state)); Brisa no detiene contenedores activos automáticamente."
                blockedEN = "Container “\(container.name)” is running (\(container.state)); Brisa never stops active containers automatically."
                blockers.append(OperationBlocker(
                    id: "running_container:\(container.id)",
                    resourceID: "container:\(container.id)",
                    reasonES: blockedES!,
                    reasonEN: blockedEN!,
                    canRecheck: true
                ))
            }
            totalNominalBytes += container.writableSizeBytes
            totalEstimatedReclaimableBytes += container.writableSizeBytes
            resources.append(OperationAffectedResource(
                id: "container:\(container.id)",
                labelES: "\(container.name) (\(container.state))",
                labelEN: "\(container.name) (\(container.state))",
                pathOrIdentifier: container.shortID,
                sizeBytes: container.writableSizeBytes,
                logicalBytes: container.writableSizeBytes,
                sizeBasis: .estimated,
                mechanism: .toolCommand,
                blockedReasonES: blockedES,
                blockedReasonEN: blockedEN
            ))
        }

        // 2. Images
        for imageID in selection.imageIDs {
            guard let image = imageByID[imageID] else {
                blockers.append(OperationBlocker(
                    id: "missing_image:\(imageID)",
                    resourceID: imageID,
                    reasonES: "La imagen \(imageID) ya no está disponible en Docker.",
                    reasonEN: "Image \(imageID) is no longer available in Docker.",
                    canRecheck: true
                ))
                continue
            }

            let referencingContainers = image.referencingContainerIDs.compactMap { containerByID[$0] }
            let runningRefs = referencingContainers.filter(\.isRunning)
            let unselectedStoppedRefs = referencingContainers.filter { !$0.isRunning && !selectedContainerSet.contains($0.id) }

            var blockedES: String?
            var blockedEN: String?
            if !runningRefs.isEmpty {
                let names = runningRefs.map(\.name).joined(separator: ", ")
                blockedES = "La imagen «\(image.displayName)» está en uso por contenedores en ejecución (\(names))."
                blockedEN = "Image “\(image.displayName)” is used by running containers (\(names))."
                blockers.append(OperationBlocker(
                    id: "image_used_by_running_container:\(image.id)",
                    resourceID: "image:\(image.id)",
                    reasonES: blockedES!,
                    reasonEN: blockedEN!,
                    canRecheck: true
                ))
            } else if !unselectedStoppedRefs.isEmpty {
                let names = unselectedStoppedRefs.map(\.name).joined(separator: ", ")
                blockedES = "La imagen «\(image.displayName)» sigue referenciada por contenedores detenidos no seleccionados (\(names))."
                blockedEN = "Image “\(image.displayName)” is still referenced by unselected stopped containers (\(names))."
                blockers.append(OperationBlocker(
                    id: "image_used_by_stopped_container:\(image.id)",
                    resourceID: "image:\(image.id)",
                    reasonES: blockedES!,
                    reasonEN: blockedEN!,
                    canRecheck: false
                ))
            }

            let reclaimable = image.uniqueBytes > 0 ? image.uniqueBytes : image.virtualSizeBytes
            totalNominalBytes += image.virtualSizeBytes
            totalEstimatedReclaimableBytes += reclaimable
            let sharedSuffix = image.sharedBytes > 0 ? " [compartido \(Formatting.bytes(image.sharedBytes))]" : ""
            resources.append(OperationAffectedResource(
                id: "image:\(image.id)",
                labelES: image.displayName + sharedSuffix,
                labelEN: image.displayName + (image.sharedBytes > 0 ? " [shared \(Formatting.bytes(image.sharedBytes))]" : ""),
                pathOrIdentifier: image.shortID,
                sizeBytes: reclaimable,
                logicalBytes: image.virtualSizeBytes,
                sizeBasis: .estimated,
                mechanism: .toolCommand,
                blockedReasonES: blockedES,
                blockedReasonEN: blockedEN
            ))
        }

        // 3. Volumes (protected by default)
        let requiresVolumeUnlock = !selection.volumeNames.isEmpty
        for volumeName in selection.volumeNames {
            guard let volume = volumeByName[volumeName] else {
                blockers.append(OperationBlocker(
                    id: "missing_volume:\(volumeName)",
                    resourceID: volumeName,
                    reasonES: "El volumen «\(volumeName)» ya no existe en Docker.",
                    reasonEN: "Volume “\(volumeName)” no longer exists in Docker.",
                    canRecheck: true
                ))
                continue
            }

            var blockedReasonsES: [String] = []
            var blockedReasonsEN: [String] = []

            if !selection.unlockedVolumeNames.contains(volumeName) {
                let msgES = "El volumen «\(volumeName)» está protegido por defecto porque puede contener bases de datos o datos persistentes; requiere desbloqueo y confirmación explícita."
                let msgEN = "Volume “\(volumeName)” is protected by default because it may contain databases or persistent data; explicit unlock and confirmation are required."
                blockedReasonsES.append(msgES)
                blockedReasonsEN.append(msgEN)
                blockers.append(OperationBlocker(
                    id: "volume_locked_by_default:\(volumeName)",
                    resourceID: "volume:\(volumeName)",
                    reasonES: msgES,
                    reasonEN: msgEN,
                    canRecheck: false
                ))
            }

            let mountedContainers = volume.mountedByContainerIDs.compactMap { containerByID[$0] }
            let runningMounts = mountedContainers.filter(\.isRunning)
            let unselectedStoppedMounts = mountedContainers.filter { !$0.isRunning && !selectedContainerSet.contains($0.id) }

            if !runningMounts.isEmpty {
                let names = runningMounts.map(\.name).joined(separator: ", ")
                let msgES = "El volumen «\(volumeName)» está montado por contenedores en ejecución (\(names))."
                let msgEN = "Volume “\(volumeName)” is mounted by running containers (\(names))."
                blockedReasonsES.append(msgES)
                blockedReasonsEN.append(msgEN)
                blockers.append(OperationBlocker(
                    id: "volume_mounted_by_running_container:\(volumeName)",
                    resourceID: "volume:\(volumeName)",
                    reasonES: msgES,
                    reasonEN: msgEN,
                    canRecheck: true
                ))
            } else if !unselectedStoppedMounts.isEmpty {
                let names = unselectedStoppedMounts.map(\.name).joined(separator: ", ")
                let msgES = "El volumen «\(volumeName)» está asociado a contenedores detenidos no seleccionados (\(names))."
                let msgEN = "Volume “\(volumeName)” is attached to unselected stopped containers (\(names))."
                blockedReasonsES.append(msgES)
                blockedReasonsEN.append(msgEN)
                blockers.append(OperationBlocker(
                    id: "volume_mounted_by_stopped_container:\(volumeName)",
                    resourceID: "volume:\(volumeName)",
                    reasonES: msgES,
                    reasonEN: msgEN,
                    canRecheck: false
                ))
            }

            totalNominalBytes += volume.sizeBytes
            totalEstimatedReclaimableBytes += volume.sizeBytes
            resources.append(OperationAffectedResource(
                id: "volume:\(volume.name)",
                labelES: "Volumen \(volume.name) (\(volume.driver))",
                labelEN: "Volume \(volume.name) (\(volume.driver))",
                pathOrIdentifier: volume.mountpoint.isEmpty ? volume.name : volume.mountpoint,
                sizeBytes: volume.sizeBytes,
                logicalBytes: volume.sizeBytes,
                sizeBasis: .estimated,
                mechanism: .toolCommand,
                blockedReasonES: blockedReasonsES.isEmpty ? nil : blockedReasonsES.joined(separator: " "),
                blockedReasonEN: blockedReasonsEN.isEmpty ? nil : blockedReasonsEN.joined(separator: " ")
            ))
        }

        // 4. Build cache
        if let buildScope = selection.buildCacheScope {
            let matchingRecords = buildScope == .all
                ? snapshot.buildCacheRecords
                : snapshot.buildCacheRecords.filter(\.reclaimable)
            let buildBytes: Int64
            if !matchingRecords.isEmpty {
                buildBytes = matchingRecords.reduce(Int64(0)) { $0 + $1.sizeBytes }
            } else if let buildSummary = snapshot.summaries.first(where: { $0.typeName.lowercased().contains("build") }) {
                buildBytes = buildScope == .all ? buildSummary.sizeBytes : buildSummary.reclaimableBytes
            } else {
                buildBytes = 0
            }
            totalNominalBytes += buildBytes
            totalEstimatedReclaimableBytes += buildBytes
            let cmd = buildScope == .all ? "docker builder prune --all --force" : "docker builder prune --force"
            resources.append(OperationAffectedResource(
                id: "buildcache:\(buildScope.rawValue)",
                labelES: buildScope.localizedTitle(.es),
                labelEN: buildScope.localizedTitle(.en),
                pathOrIdentifier: cmd,
                sizeBytes: buildBytes,
                logicalBytes: buildBytes,
                sizeBasis: .estimated,
                mechanism: .toolCommand
            ))
        }

        if resources.isEmpty && blockers.isEmpty {
            blockers.append(OperationBlocker(
                id: "empty_selection",
                resourceID: nil,
                reasonES: "Selecciona al menos un contenedor detenido, imagen, volumen desbloqueado o alcance de caché de compilación.",
                reasonEN: "Select at least one stopped container, image, unlocked volume, or build cache scope.",
                canRecheck: false
            ))
        }

        let summaryScopeES: String
        let summaryScopeEN: String
        if let buildScope = selection.buildCacheScope, selectedContainerSet.isEmpty, selection.imageIDs.isEmpty, selectedVolumeSet.isEmpty {
            summaryScopeES = buildScope.localizedScopeDescription(.es)
            summaryScopeEN = buildScope.localizedScopeDescription(.en)
        } else {
            summaryScopeES = "Ejecución selectiva por identificador de recurso (\(resources.count) elemento(s)). No ejecuta una limpieza global indiscriminada."
            summaryScopeEN = "Per-resource selective execution (\(resources.count) item(s)). Never runs an indiscriminate global prune."
        }

        return OperationPlan(
            domain: .docker,
            titleES: "Limpieza selectiva de Docker",
            titleEN: "Selective Docker cleanup",
            scopeDescriptionES: summaryScopeES,
            scopeDescriptionEN: summaryScopeEN,
            affectedResources: resources,
            preservedSummaryES: "Se conservan los contenedores en ejecución, las imágenes o volúmenes no seleccionados, tus archivos locales del proyecto y los volúmenes bloqueados.",
            preservedSummaryEN: "Preserves running containers, unselected images or volumes, local project source files, and locked volumes.",
            totalBytes: totalEstimatedReclaimableBytes,
            logicalBytes: totalNominalBytes,
            sizeBasis: .estimated,
            sizeNoteES: "Estimación basada en docker system df y tamaño único de capas; el espacio final recuperado depende de capas compartidas en Docker/BuildKit.",
            sizeNoteEN: "Estimate based on docker system df and unique layer sizes; actual reclaimed space depends on shared layers in Docker/BuildKit.",
            regenerationES: "Las imágenes pueden volver a descargarse (docker pull) o reconstruirse (docker build). Los contenedores eliminados deben recrearse. Los volúmenes y datos no respaldados NO se regeneran.",
            regenerationEN: "Images can be pulled again (docker pull) or rebuilt (docker build). Removed containers must be recreated. Unbacked volumes and database contents are NOT regenerated.",
            mechanism: .toolCommand,
            restorability: .irreversible,
            restorabilityNoteES: "Irreversible: Docker elimina capas, metadatos o datos de volúmenes directamente sin pasar por la Papelera.",
            restorabilityNoteEN: "Irreversible: Docker deletes layers, metadata, or volume contents directly without using Trash.",
            blockers: blockers,
            requiresExplicitVolumeUnlock: requiresVolumeUnlock,
            canExecute: blockers.isEmpty && !resources.isEmpty
        )
    }

    // MARK: - Execution

    public func execute(
        plan: OperationPlan,
        selection: DockerCleanupSelection,
        control: ScanControl? = nil
    ) throws -> DockerCleanupExecutionResult {
        let activeJournal = try resolvedJournal()
        let planEntry = try OperationJournalRecorder.recordPlan(plan, journal: activeJournal, home: home)

        guard let dockerPath = resolveDockerExecutable() else {
            let err = "Docker CLI not found during execution."
            let finalEntry = try OperationJournalRecorder.finalizePlan(
                plan,
                planEntry: planEntry,
                outcome: .failed,
                completedCount: 0,
                skippedOrFailedCount: plan.affectedResources.count,
                errorText: err,
                detailNote: "docker_cli_unavailable",
                detailNoteES: "No se pudo ejecutar porque falta el CLI de Docker.",
                restorable: false,
                journal: activeJournal,
                home: home
            )
            let report = OperationExecutionReport(
                planID: plan.id,
                domain: .docker,
                outcome: .failed,
                mechanism: .toolCommand,
                restorable: false,
                failedItems: plan.affectedResources.map(\.pathOrIdentifier),
                summaryES: "No se pudo ejecutar porque falta el CLI de Docker.",
                summaryEN: "Unable to execute because Docker CLI is unavailable.",
                commandOutput: err,
                journalEntries: [finalEntry]
            )
            return DockerCleanupExecutionResult(
                plan: plan,
                report: report,
                removedContainerIDs: [],
                removedImageIDs: [],
                removedVolumeNames: [],
                prunedBuildCacheScope: nil,
                skippedReasons: [err]
            )
        }

        // Revalidate fresh Docker state immediately before execution.
        let freshSnapshot = inspect(control: control)
        guard freshSnapshot.status == .ready else {
            let err = freshSnapshot.statusDetailEN
            let finalEntry = try OperationJournalRecorder.finalizePlan(
                plan,
                planEntry: planEntry,
                outcome: .failed,
                completedCount: 0,
                skippedOrFailedCount: plan.affectedResources.count,
                errorText: err,
                detailNote: "docker_daemon_unavailable_on_recheck",
                detailNoteES: freshSnapshot.statusDetailES,
                restorable: false,
                journal: activeJournal,
                home: home
            )
            let report = OperationExecutionReport(
                planID: plan.id,
                domain: .docker,
                outcome: .failed,
                mechanism: .toolCommand,
                restorable: false,
                failedItems: plan.affectedResources.map(\.pathOrIdentifier),
                summaryES: freshSnapshot.statusDetailES,
                summaryEN: freshSnapshot.statusDetailEN,
                commandOutput: err,
                journalEntries: [finalEntry]
            )
            return DockerCleanupExecutionResult(
                plan: plan,
                report: report,
                removedContainerIDs: [],
                removedImageIDs: [],
                removedVolumeNames: [],
                prunedBuildCacheScope: nil,
                skippedReasons: [err]
            )
        }

        let refreshedPlan = buildPlan(snapshot: freshSnapshot, selection: selection)
        if !refreshedPlan.canExecute {
            let reasonEN = refreshedPlan.blockers.map(\.reasonEN).joined(separator: "; ")
            let reasonES = refreshedPlan.blockers.map(\.reasonES).joined(separator: "; ")
            let finalEntry = try OperationJournalRecorder.finalizePlan(
                plan,
                planEntry: planEntry,
                outcome: .rejected,
                completedCount: 0,
                skippedOrFailedCount: plan.affectedResources.count,
                errorText: reasonEN,
                detailNote: "revalidation_blocked",
                detailNoteES: reasonES,
                restorable: false,
                journal: activeJournal,
                home: home
            )
            let report = OperationExecutionReport(
                planID: plan.id,
                domain: .docker,
                outcome: .rejected,
                mechanism: .toolCommand,
                restorable: false,
                rejectedItems: refreshedPlan.affectedResources.map(\.pathOrIdentifier),
                summaryES: "Operación rechazada durante la revalidación: \(reasonES)",
                summaryEN: "Operation rejected during revalidation: \(reasonEN)",
                commandOutput: reasonEN,
                journalEntries: [finalEntry]
            )
            return DockerCleanupExecutionResult(
                plan: refreshedPlan,
                report: report,
                removedContainerIDs: [],
                removedImageIDs: [],
                removedVolumeNames: [],
                prunedBuildCacheScope: nil,
                skippedReasons: refreshedPlan.blockers.map(\.reasonEN)
            )
        }

        var removedContainers: [String] = []
        var removedImages: [String] = []
        var removedVolumes: [String] = []
        var prunedBuildScope: DockerBuildCachePruneScope?
        var completedItems: [String] = []
        var rejectedItems: [String] = []
        var failedItems: [String] = []
        var skippedOnCancellation: [String] = []
        var skippedReasons: [String] = []
        var outputs: [String] = []
        var wasCancelled = false

        // Step 1: Remove stopped containers first so image/volume dependencies clear cleanly.
        for containerID in selection.containerIDs {
            if control?.cancellation.isCancelled == true {
                wasCancelled = true
                skippedOnCancellation.append("container:\(containerID)")
                continue
            }
            if !revalidateContainerStillStopped(executable: dockerPath, id: containerID, control: control) {
                rejectedItems.append("container:\(containerID)")
                skippedReasons.append("Container \(containerID) changed state (now running or missing).")
                continue
            }
            do {
                let res = try runDocker(executable: dockerPath, arguments: ["rm", containerID], control: control)
                if res.status == 0 && !res.timedOut {
                    removedContainers.append(containerID)
                    completedItems.append("container:\(containerID)")
                    if !res.output.isEmpty { outputs.append(res.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
                } else {
                    failedItems.append("container:\(containerID)")
                    skippedReasons.append("docker rm \(containerID): \(cleanErrorOutput(res))")
                }
            } catch {
                failedItems.append("container:\(containerID)")
                skippedReasons.append("docker rm \(containerID): \(error.localizedDescription)")
            }
        }

        // Step 2: Remove selected images after dependent stopped containers.
        for imageID in selection.imageIDs {
            if wasCancelled || control?.cancellation.isCancelled == true {
                wasCancelled = true
                skippedOnCancellation.append("image:\(imageID)")
                continue
            }
            if !revalidateImageSafeToRemove(executable: dockerPath, id: imageID, control: control) {
                rejectedItems.append("image:\(imageID)")
                skippedReasons.append("Image \(imageID) is now referenced by an active or remaining container.")
                continue
            }
            do {
                let res = try runDocker(executable: dockerPath, arguments: ["rmi", imageID], control: control)
                if res.status == 0 && !res.timedOut {
                    removedImages.append(imageID)
                    completedItems.append("image:\(imageID)")
                    if !res.output.isEmpty { outputs.append(res.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
                } else {
                    failedItems.append("image:\(imageID)")
                    skippedReasons.append("docker rmi \(imageID): \(cleanErrorOutput(res))")
                }
            } catch {
                failedItems.append("image:\(imageID)")
                skippedReasons.append("docker rmi \(imageID): \(error.localizedDescription)")
            }
        }

        // Step 3: Remove unlocked & unmounted volumes only.
        for volumeName in selection.volumeNames {
            if wasCancelled || control?.cancellation.isCancelled == true {
                wasCancelled = true
                skippedOnCancellation.append("volume:\(volumeName)")
                continue
            }
            guard selection.unlockedVolumeNames.contains(volumeName) else {
                rejectedItems.append("volume:\(volumeName)")
                skippedReasons.append("Volume \(volumeName) lacked explicit unlock confirmation.")
                continue
            }
            if !revalidateVolumeUnmounted(executable: dockerPath, name: volumeName, control: control) {
                rejectedItems.append("volume:\(volumeName)")
                skippedReasons.append("Volume \(volumeName) is still attached to a container or missing.")
                continue
            }
            do {
                let res = try runDocker(executable: dockerPath, arguments: ["volume", "rm", volumeName], control: control)
                if res.status == 0 && !res.timedOut {
                    removedVolumes.append(volumeName)
                    completedItems.append("volume:\(volumeName)")
                    if !res.output.isEmpty { outputs.append(res.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
                } else {
                    failedItems.append("volume:\(volumeName)")
                    skippedReasons.append("docker volume rm \(volumeName): \(cleanErrorOutput(res))")
                }
            } catch {
                failedItems.append("volume:\(volumeName)")
                skippedReasons.append("docker volume rm \(volumeName): \(error.localizedDescription)")
            }
        }

        // Step 4: Prune build cache scope if requested.
        if let scope = selection.buildCacheScope {
            if wasCancelled || control?.cancellation.isCancelled == true {
                wasCancelled = true
                skippedOnCancellation.append("buildcache:\(scope.rawValue)")
            } else {
                let args: [String] = scope == .all
                    ? ["builder", "prune", "--all", "--force"]
                    : ["builder", "prune", "--force"]
                do {
                    let res = try runDocker(executable: dockerPath, arguments: args, control: control)
                    if res.status == 0 && !res.timedOut {
                        prunedBuildScope = scope
                        completedItems.append("buildcache:\(scope.rawValue)")
                        if !res.output.isEmpty { outputs.append(res.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    } else {
                        failedItems.append("buildcache:\(scope.rawValue)")
                        skippedReasons.append("docker \(args.joined(separator: " ")): \(cleanErrorOutput(res))")
                    }
                } catch {
                    failedItems.append("buildcache:\(scope.rawValue)")
                    skippedReasons.append("docker builder prune: \(error.localizedDescription)")
                }
            }
        }

        let completedCount = completedItems.count
        let skippedOrFailed = rejectedItems.count + failedItems.count + skippedOnCancellation.count
        let outcome: OperationOutcomeStatus
        if wasCancelled {
            outcome = .cancelled
        } else {
            outcome = OperationJournalRecorder.resolveBatchOutcome(
                completed: completedCount,
                rejected: rejectedItems.count,
                failed: failedItems.count,
                cancelled: false
            )
        }

        let noteParts = [
            "containers=\(removedContainers.count)",
            "images=\(removedImages.count)",
            "volumes=\(removedVolumes.count)",
            prunedBuildScope.map { "build_cache=\($0.rawValue)" } ?? "build_cache=none",
            wasCancelled ? "cancelled_no_rollback" : nil
        ].compactMap { $0 }

        let summaryES: String
        let summaryEN: String
        if wasCancelled {
            summaryES = "Ejecución cancelada tras completar \(completedCount) elemento(s); \(skippedOnCancellation.count) elemento(s) restante(s) omitido(s) sin revertir los cambios ya aplicados."
            summaryEN = "Execution cancelled after completing \(completedCount) item(s); \(skippedOnCancellation.count) remaining item(s) skipped without rolling back completed removals."
        } else {
            summaryES = "Completados \(completedCount) elemento(s); omitidos o fallidos: \(skippedOrFailed)."
            summaryEN = "Completed \(completedCount) item(s); skipped or failed: \(skippedOrFailed)."
        }

        let finalEntry = try OperationJournalRecorder.finalizePlan(
            plan,
            planEntry: planEntry,
            outcome: outcome,
            completedCount: completedCount,
            skippedOrFailedCount: skippedOrFailed,
            errorText: skippedReasons.isEmpty ? nil : skippedReasons.joined(separator: " | "),
            detailNote: noteParts.joined(separator: "; "),
            detailNoteES: summaryES,
            restorable: false,
            journal: activeJournal,
            home: home
        )

        let report = OperationExecutionReport(
            planID: plan.id,
            domain: .docker,
            outcome: outcome,
            mechanism: .toolCommand,
            restorable: false,
            completedItems: completedItems,
            rejectedItems: rejectedItems,
            failedItems: failedItems,
            skippedOnCancellation: skippedOnCancellation,
            reclaimedBytesEstimate: completedCount == plan.affectedResources.count ? plan.totalBytes : nil,
            summaryES: summaryES,
            summaryEN: summaryEN,
            commandOutput: outputs.isEmpty ? nil : outputs.joined(separator: "\n"),
            journalEntries: [finalEntry]
        )

        return DockerCleanupExecutionResult(
            plan: plan,
            report: report,
            removedContainerIDs: removedContainers,
            removedImageIDs: removedImages,
            removedVolumeNames: removedVolumes,
            prunedBuildCacheScope: prunedBuildScope,
            skippedReasons: skippedReasons
        )
    }

    // MARK: - Live Revalidation Before Per-Resource Command

    private func revalidateContainerStillStopped(executable: String, id: String, control: ScanControl?) -> Bool {
        guard let res = try? runDocker(
            executable: executable,
            arguments: ["inspect", "--format", "{{.State.Running}}", id],
            control: control
        ), res.status == 0, !res.timedOut else {
            return false
        }
        let trimmed = res.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed == "false"
    }

    private func revalidateImageSafeToRemove(executable: String, id: String, control: ScanControl?) -> Bool {
        guard let res = try? runDocker(
            executable: executable,
            arguments: ["ps", "-a", "--filter", "ancestor=\(id)", "--format", "{{.ID}}"],
            control: control
        ), res.status == 0, !res.timedOut else {
            return false
        }
        return res.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func revalidateVolumeUnmounted(executable: String, name: String, control: ScanControl?) -> Bool {
        guard let res = try? runDocker(
            executable: executable,
            arguments: ["ps", "-a", "--filter", "volume=\(name)", "--format", "{{.ID}}"],
            control: control
        ), res.status == 0, !res.timedOut else {
            return false
        }
        return res.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Subprocess & Parsing Helpers

    private func resolvedJournal() throws -> Journal {
        if let journal { return journal }
        let dir = URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/Brisa", isDirectory: true)
        return Journal(store: try PrivateStore(directory: dir))
    }

    private func resolveDockerExecutable() -> String? {
        if let executableOverride {
            return executableOverride.isEmpty ? nil : executableOverride
        }
        return ExecutableLocator.resolve(
            name: "docker",
            extraDirectories: [
                "/usr/local/bin",
                "/opt/homebrew/bin",
                "/Applications/Docker.app/Contents/Resources/bin",
                home + "/.rd/bin",
                home + "/.orbstack/bin"
            ],
            home: home
        )
    }

    private func runDocker(
        executable: String,
        arguments: [String],
        control: ScanControl?
    ) throws -> CommandResult {
        try executor.run(
            CommandExecutionRequest(
                executable: executable,
                arguments: arguments,
                timeout: timeoutSeconds,
                directory: URL(fileURLWithPath: home, isDirectory: true)
            ),
            control: control
        )
    }

    private func cleanErrorOutput(_ result: CommandResult) -> String {
        let raw = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            return raw
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedTrimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func decodeJSONString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }
}

// MARK: - Structured JSON Models & Byte Parser

private struct RawSystemDFLine: Decodable {
    let type: String?
    let totalCount: String?
    let active: String?
    let size: String?
    let reclaimable: String?

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case totalCount = "TotalCount"
        case active = "Active"
        case size = "Size"
        case reclaimable = "Reclaimable"
    }
}

private struct RawVerboseSystemDF: Decodable {
    let images: [RawVerboseImage]?
    let containers: [RawVerboseContainer]?
    let volumes: [RawVerboseVolume]?

    enum CodingKeys: String, CodingKey {
        case images = "Images"
        case containers = "Containers"
        case volumes = "Volumes"
    }
}

private struct RawVerboseImage: Decodable {
    let id: String?
    let repository: String?
    let tag: String?
    let size: String?
    let sharedSize: String?
    let uniqueSize: String?
    let containers: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case repository = "Repository"
        case tag = "Tag"
        case size = "Size"
        case sharedSize = "SharedSize"
        case uniqueSize = "UniqueSize"
        case containers = "Containers"
    }
}

private struct RawVerboseContainer: Decodable {
    let id: String?
    let names: String?
    let size: String?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case names = "Names"
        case size = "Size"
        case state = "State"
    }
}

private struct RawVerboseVolume: Decodable {
    let name: String?
    let driver: String?
    let scope: String?
    let mountpoint: String?
    let links: String?
    let size: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case driver = "Driver"
        case scope = "Scope"
        case mountpoint = "Mountpoint"
        case links = "Links"
        case size = "Size"
    }
}

private struct RawImageLine: Decodable {
    let id: String?
    let repository: String?
    let tag: String?
    let digest: String?
    let createdAt: String?
    let createdSince: String?
    let size: String?
    let sharedSize: String?
    let uniqueSize: String?
    let containers: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case repository = "Repository"
        case tag = "Tag"
        case digest = "Digest"
        case createdAt = "CreatedAt"
        case createdSince = "CreatedSince"
        case size = "Size"
        case sharedSize = "SharedSize"
        case uniqueSize = "UniqueSize"
        case containers = "Containers"
    }
}

private struct RawContainerLine: Decodable {
    let id: String?
    let names: String?
    let image: String?
    let state: String?
    let status: String?
    let size: String?
    let mounts: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case names = "Names"
        case image = "Image"
        case state = "State"
        case status = "Status"
        case size = "Size"
        case mounts = "Mounts"
        case createdAt = "CreatedAt"
    }
}

private struct RawBuilderDULine: Decodable {
    let id: String?
    let type: String?
    let description: String?
    let size: String?
    let shared: Bool?
    let reclaimable: Bool?
    let mutable: Bool?
    let usageCount: Int?
    let createdAt: String?
    let lastUsedAt: String?
    let parents: [String]?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case type = "Type"
        case description = "Description"
        case size = "Size"
        case shared = "Shared"
        case reclaimable = "Reclaimable"
        case mutable = "Mutable"
        case usageCount = "UsageCount"
        case createdAt = "CreatedAt"
        case lastUsedAt = "LastUsedAt"
        case parents = "Parents"
    }
}

private struct RawVolumeLine: Decodable {
    let name: String?
    let driver: String?
    let scope: String?
    let mountpoint: String?
    let labels: String?
    let links: String?
    let size: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case driver = "Driver"
        case scope = "Scope"
        case mountpoint = "Mountpoint"
        case labels = "Labels"
        case links = "Links"
        case size = "Size"
    }
}

private struct RawInspectContainer: Decodable {
    let id: String?
    let name: String?
    let image: String?
    let state: RawInspectState?
    let config: RawInspectConfig?
    let mounts: [RawInspectMount]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case image = "Image"
        case state = "State"
        case config = "Config"
        case mounts = "Mounts"
    }
}

private struct RawInspectState: Decodable {
    let status: String?
    let running: Bool?
    let paused: Bool?
    let restarting: Bool?

    enum CodingKeys: String, CodingKey {
        case status = "Status"
        case running = "Running"
        case paused = "Paused"
        case restarting = "Restarting"
    }
}

private struct RawInspectConfig: Decodable {
    let image: String?

    enum CodingKeys: String, CodingKey {
        case image = "Image"
    }
}

private struct RawInspectMount: Decodable {
    let type: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case name = "Name"
    }
}

private struct DockerContainerInspectInfo {
    let id: String
    let imageID: String
    let imageName: String
    let isRunning: Bool
    let volumeNames: [String]
}

private struct VerboseSystemDFDetails {
    var imagesByShortID: [String: RawVerboseImage] = [:]
    var containersByShortID: [String: RawVerboseContainer] = [:]
    var volumesByName: [String: RawVerboseVolume] = [:]
}

private extension DockerManager {
    func normalizeDockerID(_ raw: String) -> String {
        let stripped = raw.hasPrefix("sha256:") ? String(raw.dropFirst(7)) : raw
        return String(stripped.prefix(12)).lowercased()
    }

    func decodeNDJSON<T: Decodable>(_ type: T.Type, from output: String) -> [T] {
        let decoder = JSONDecoder()
        return output
            .components(separatedBy: .newlines)
            .compactMap { line -> T? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
                return try? decoder.decode(T.self, from: data)
            }
    }

    func parseSystemDFSummary(_ output: String) -> [DockerCategorySummary] {
        decodeNDJSON(RawSystemDFLine.self, from: output).compactMap { row in
            guard let typeName = row.type, !typeName.isEmpty else { return nil }
            let rawSize = row.size ?? "0B"
            let rawReclaimable = row.reclaimable ?? "0B"
            let (reclaimableBytes, percent) = parseDockerReclaimable(rawReclaimable)
            return DockerCategorySummary(
                typeName: typeName,
                totalCount: Int(row.totalCount ?? "0") ?? 0,
                activeCount: Int(row.active ?? "0") ?? 0,
                sizeBytes: parseDockerSizeBytes(rawSize),
                reclaimableBytes: reclaimableBytes,
                reclaimablePercent: percent,
                rawSizeText: rawSize,
                rawReclaimableText: rawReclaimable
            )
        }
    }

    func parseVerboseSystemDF(_ output: String) -> VerboseSystemDFDetails {
        var details = VerboseSystemDFDetails()
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(RawVerboseSystemDF.self, from: data) else {
            return details
        }
        for img in parsed.images ?? [] {
            if let id = img.id {
                details.imagesByShortID[normalizeDockerID(id)] = img
            }
        }
        for container in parsed.containers ?? [] {
            if let id = container.id {
                details.containersByShortID[normalizeDockerID(id)] = container
            }
        }
        for volume in parsed.volumes ?? [] {
            if let name = volume.name {
                details.volumesByName[name] = volume
            }
        }
        return details
    }

    func parseContainersNDJSON(_ output: String) -> [RawContainerLine] {
        decodeNDJSON(RawContainerLine.self, from: output)
    }

    func parseImagesNDJSON(_ output: String) -> [RawImageLine] {
        decodeNDJSON(RawImageLine.self, from: output)
    }

    func parseVolumesNDJSON(_ output: String) -> [RawVolumeLine] {
        decodeNDJSON(RawVolumeLine.self, from: output)
    }

    func parseBuildCacheNDJSON(_ output: String) -> [DockerBuildCacheRecord] {
        decodeNDJSON(RawBuilderDULine.self, from: output).compactMap { row in
            guard let id = row.id, !id.isEmpty else { return nil }
            return DockerBuildCacheRecord(
                id: id,
                recordType: row.type ?? "regular",
                description: row.description ?? "",
                sizeBytes: parseDockerSizeBytes(row.size ?? "0B"),
                shared: row.shared ?? false,
                reclaimable: row.reclaimable ?? true,
                mutable: row.mutable ?? true,
                usageCount: row.usageCount ?? 0,
                createdAt: row.createdAt ?? "",
                lastUsedAt: row.lastUsedAt ?? "",
                parents: row.parents ?? []
            )
        }
    }

    func parseContainerInspect(_ output: String) -> [String: DockerContainerInspectInfo] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let items = try? JSONDecoder().decode([RawInspectContainer].self, from: data) else {
            return [:]
        }
        var map: [String: DockerContainerInspectInfo] = [:]
        for item in items {
            guard let id = item.id else { continue }
            let volumeNames = (item.mounts ?? [])
                .filter { ($0.type ?? "").lowercased() == "volume" }
                .compactMap(\.name)
            let isRunning = (item.state?.running ?? false)
                || (item.state?.restarting ?? false)
                || (item.state?.paused ?? false)
            let info = DockerContainerInspectInfo(
                id: id,
                imageID: item.image ?? "",
                imageName: item.config?.image ?? "",
                isRunning: isRunning,
                volumeNames: volumeNames
            )
            map[id] = info
            map[normalizeDockerID(id)] = info
        }
        return map
    }

    func buildContainers(
        rawContainers: [RawContainerLine],
        inspectMap: [String: DockerContainerInspectInfo],
        verboseDetails: VerboseSystemDFDetails
    ) -> [DockerContainerResource] {
        rawContainers.compactMap { raw in
            guard let id = raw.id, !id.isEmpty else { return nil }
            let shortID = normalizeDockerID(id)
            let inspected = inspectMap[id] ?? inspectMap[shortID]
            let verbose = verboseDetails.containersByShortID[shortID]
            let stateText = (raw.state ?? "").lowercased()
            let activeState = stateText == "running" || stateText == "restarting" || stateText == "paused"
            let isRunning = inspected?.isRunning ?? activeState
            let name = (raw.names ?? shortID).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let rawSize = (raw.size ?? verbose?.size) ?? "0B"
            let (writableBytes, virtualBytes) = parseDockerContainerSize(rawSize)
            let mounts: [String]
            if let inspectedMounts = inspected?.volumeNames {
                mounts = inspectedMounts
            } else {
                mounts = (raw.mounts ?? "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            return DockerContainerResource(
                id: id,
                shortID: shortID,
                name: name.isEmpty ? shortID : name,
                imageName: inspected?.imageName.isEmpty == false ? (inspected?.imageName ?? "") : (raw.image ?? ""),
                imageID: inspected?.imageID ?? "",
                state: raw.state ?? "unknown",
                statusText: raw.status ?? "",
                createdAt: raw.createdAt ?? "",
                writableSizeBytes: writableBytes,
                virtualSizeBytes: virtualBytes,
                mountedVolumeNames: mounts,
                isRunning: isRunning
            )
        }
    }

    func buildImages(
        rawImages: [RawImageLine],
        verboseDetails: VerboseSystemDFDetails,
        containers: [DockerContainerResource]
    ) -> [DockerImageResource] {
        var seenIDs = Set<String>()
        var result: [DockerImageResource] = []
        for raw in rawImages {
            guard let id = raw.id, !id.isEmpty, seenIDs.insert(id).inserted else { continue }
            let shortID = normalizeDockerID(id)
            let verbose = verboseDetails.imagesByShortID[shortID]
            let sizeText = raw.size ?? verbose?.size ?? "0B"
            let sharedText = (raw.sharedSize != nil && raw.sharedSize != "N/A") ? raw.sharedSize! : (verbose?.sharedSize ?? "0B")
            let uniqueText = (raw.uniqueSize != nil && raw.uniqueSize != "N/A") ? raw.uniqueSize! : (verbose?.uniqueSize ?? "0B")

            let matchingContainers = containers.filter { container in
                if !container.imageID.isEmpty {
                    return normalizeDockerID(container.imageID) == shortID || container.imageID == id
                }
                let displayTag = (raw.repository ?? "") + ((raw.tag?.isEmpty == false && raw.tag != "<none>") ? ":\(raw.tag!)" : "")
                return !displayTag.isEmpty && container.imageName == displayTag
            }

            result.append(DockerImageResource(
                id: id,
                shortID: shortID,
                repository: raw.repository ?? "<none>",
                tag: raw.tag ?? "<none>",
                digest: raw.digest ?? "<none>",
                createdAt: raw.createdAt ?? "",
                createdSince: raw.createdSince ?? "",
                virtualSizeBytes: parseDockerSizeBytes(sizeText),
                sharedBytes: parseDockerSizeBytes(sharedText),
                uniqueBytes: parseDockerSizeBytes(uniqueText),
                containerCount: Int(raw.containers ?? verbose?.containers ?? "0") ?? matchingContainers.count,
                referencingContainerIDs: matchingContainers.map(\.id),
                referencingContainerNames: matchingContainers.map(\.name),
                isUsedByRunningContainer: matchingContainers.contains(where: \.isRunning)
            ))
        }
        return result
    }

    func buildVolumes(
        rawVolumes: [RawVolumeLine],
        verboseDetails: VerboseSystemDFDetails,
        containers: [DockerContainerResource]
    ) -> [DockerVolumeResource] {
        rawVolumes.compactMap { raw in
            guard let name = raw.name, !name.isEmpty else { return nil }
            let verbose = verboseDetails.volumesByName[name]
            let sizeText = (raw.size != nil && raw.size != "N/A") ? raw.size! : (verbose?.size ?? "0B")
            let linksText = (raw.links != nil && raw.links != "N/A") ? raw.links! : (verbose?.links ?? "0")
            let mountedBy = containers.filter { $0.mountedVolumeNames.contains(name) }
            return DockerVolumeResource(
                name: name,
                driver: raw.driver ?? verbose?.driver ?? "local",
                scope: raw.scope ?? verbose?.scope ?? "local",
                mountpoint: raw.mountpoint ?? verbose?.mountpoint ?? "",
                labels: raw.labels ?? "",
                sizeBytes: parseDockerSizeBytes(sizeText),
                linkCount: Int(linksText) ?? mountedBy.count,
                mountedByContainerIDs: mountedBy.map(\.id),
                mountedByContainerNames: mountedBy.map(\.name),
                isMountedByRunningContainer: mountedBy.contains(where: \.isRunning),
                protectedByDefault: true
            )
        }
    }

    func parseDockerReclaimable(_ text: String) -> (Int64, Double?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "N/A" else { return (0, nil) }
        if let openIdx = trimmed.firstIndex(of: "("),
           let closeIdx = trimmed.firstIndex(of: ")"),
           openIdx < closeIdx {
            let sizePart = String(trimmed[..<openIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let pctPart = String(trimmed[trimmed.index(after: openIdx)..<closeIdx])
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (parseDockerSizeBytes(sizePart), Double(pctPart))
        }
        return (parseDockerSizeBytes(trimmed), nil)
    }

    func parseDockerContainerSize(_ text: String) -> (writable: Int64, virtual: Int64) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let virtualRange = trimmed.range(of: "(virtual ", options: .caseInsensitive),
           let closeParen = trimmed[virtualRange.upperBound...].firstIndex(of: ")") {
            let writablePart = String(trimmed[..<virtualRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let virtualPart = String(trimmed[virtualRange.upperBound..<closeParen]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (parseDockerSizeBytes(writablePart), parseDockerSizeBytes(virtualPart))
        }
        let val = parseDockerSizeBytes(trimmed)
        return (val, val)
    }

    func parseDockerSizeBytes(_ text: String) -> Int64 {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "N/A", trimmed != "--" else { return 0 }

        var numberChars = ""
        var unitChars = ""
        for ch in trimmed {
            if (ch.isNumber || ch == "." || ch == ",") && unitChars.isEmpty {
                numberChars.append(ch == "," ? "." : ch)
            } else if !ch.isWhitespace {
                unitChars.append(ch)
            }
        }
        guard let value = Double(numberChars) else { return 0 }
        let unit = unitChars.lowercased()
        let multiplier: Double
        switch unit {
        case "", "b", "bytes":
            multiplier = 1
        case "kb":
            multiplier = 1_000
        case "kib":
            multiplier = 1_024
        case "mb":
            multiplier = 1_000_000
        case "mib":
            multiplier = 1_048_576
        case "gb":
            multiplier = 1_000_000_000
        case "gib":
            multiplier = 1_073_741_824
        case "tb":
            multiplier = 1_000_000_000_000
        case "tib":
            multiplier = 1_099_511_627_776
        default:
            multiplier = 1
        }
        return Int64((value * multiplier).rounded())
    }
}
