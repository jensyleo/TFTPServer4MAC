// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var serverStatus: TFTPStatus = .unknown
    @Published var configuration: TFTPConfiguration
    @Published var networkInterfaces: [NetworkInterface] = []
    @Published var selectedInterfaceID: String?
    @Published var transfers: [TFTPTransfer] = []
    @Published var lastError: TFTPServiceError?
    @Published var files: [FileEntry] = []
    @Published var logEntries: [LogEntry] = []
    @Published var workingPathPermissionsOK = true
    @Published var parentFolderPermissionsOK = true
    /// Una entrada por proceso `tftpd` real actualmente en curso — el daemon
    /// nativo sí atiende múltiples clientes en paralelo (confirmado en vivo,
    /// 2026-09-07), así que la app debe poder mostrarlos todos, no solo el
    /// último detectado. Keyed por PID (ver `TransferProgress.pid`).
    @Published var activeTransfers: [Int32: TransferProgress] = [:]
    /// `true` cuando, al arrancar, se detecta que el servidor ya estaba
    /// corriendo desde una sesión anterior que no cerró limpiamente (p. ej.
    /// Force Quit / kill -9, que no permite ejecutar ningún código de
    /// limpieza — ver AppDelegate). Bloquea el uso de la app hasta que el
    /// usuario autorice detenerlo, por decisión explícita del usuario
    /// (2026-09-04): nunca continuar en silencio con un daemon huérfano.
    @Published var isBlockedByOrphanedServer = false
    /// Se activa justo después de elegir una carpeta nueva con "Change Path"
    /// si esa carpeta (o su padre) tiene un problema de permisos — en vez de
    /// depender de que el usuario mire la barra de estado inferior. Pedido
    /// del usuario (2026-09-08) tras ver un caso confuso: cambiar de ruta
    /// con el servidor ya corriendo deja "Running" (el daemon sigue sirviendo
    /// la carpeta ANTERIOR hasta un Stop/Start) al lado de "Fix needed" (ya
    /// describiendo la carpeta nueva) — sin este aviso, es fácil no notar el
    /// problema hasta intentar reiniciar el servidor.
    @Published var isShowingPermissionsNeededPrompt = false

    private let serviceController: TFTPServiceController
    private let networkMonitor = NetworkMonitor()
    private let fileSystemService = FileSystemService()
    private let logStreamMonitor = LogStreamMonitor()
    private var trackingTasks: [Int32: Task<Void, Never>] = [:]
    private var lastSpeedSamples: [Int32: (bytes: Int64, date: Date)] = [:]
    /// Último conteo de bytes visto por PID — permite resolver la dirección
    /// al finalizar cuando la transferencia terminó antes de que
    /// `updateTransfer` alcanzara a verla cruzar el umbral normal (ver
    /// `finalizeTransfer`).
    private var lastByteCounts: [Int32: NetworkByteMonitor.ByteCounts] = [:]

    init(serviceController: TFTPServiceController = TFTPServiceController(service: NativeTFTPService())) {
        self.serviceController = serviceController
        self.configuration = .conservativeDefault
        log(.application, "TFTP Server launched")
    }

    /// Progreso combinado de todas las descargas de esta sesión (en curso o
    /// ya completadas, mientras sigan visibles sin descartar) con tamaño
    /// conocido — subidas se excluyen: no hay total confiable que sumar (ver
    /// PROJECT.md sección 49). `nil` si no hay ninguna descarga con tamaño
    /// conocido.
    ///
    /// Incluye completadas a propósito (no solo `.inProgress`): si se
    /// excluyeran, el % global "retrocedería" cada vez que una descarga
    /// termina (el numerador y denominador perderían sus bytes de golpe) en
    /// vez de avanzar de forma acumulativa — bug real reportado en vivo
    /// (2026-09-07) con 2 descargas simultáneas.
    var globalDownloadFraction: Double? {
        let downloads = activeTransfers.values.filter {
            $0.direction == .download && $0.totalBytes != nil
                && ($0.status == .inProgress || $0.status == .completed)
        }
        guard !downloads.isEmpty else { return nil }
        let totalBytes = downloads.reduce(0) { $0 + ($1.totalBytes ?? 0) }
        guard totalBytes > 0 else { return nil }
        let transferredBytes = downloads.reduce(0) { $0 + $1.transferredBytes }
        return min(1.0, Double(transferredBytes) / Double(totalBytes))
    }

    /// Subidas activas o completadas: sin porcentaje (no hay total confiable
    /// — ver PROJECT.md sección 49), pero sí un conteo y total de bytes
    /// recibidos, para no dejarlas completamente invisibles frente a las
    /// descargas.
    var uploadsSummary: (count: Int, totalBytesReceived: Int64)? {
        let uploads = activeTransfers.values.filter {
            $0.direction == .upload && ($0.status == .inProgress || $0.status == .completed)
        }
        guard !uploads.isEmpty else { return nil }
        return (uploads.count, uploads.reduce(0) { $0 + $1.transferredBytes })
    }

    /// Transferencias agrupadas por dirección, para los paneles separados de
    /// Descargas y Subidas — feedback del usuario (2026-09-07): "para carga
    /// una ventana y para descarga otra". `nil` = todavía "Detecting…"
    /// (normalmente dura una fracción de segundo).
    var downloadTransfers: [TransferProgress] {
        activeTransfers.values.filter { $0.direction == .download }.sorted { $0.startDate < $1.startDate }
    }

    var uploadTransfers: [TransferProgress] {
        activeTransfers.values.filter { $0.direction == .upload }.sorted { $0.startDate < $1.startDate }
    }

    var detectingTransfers: [TransferProgress] {
        activeTransfers.values.filter { $0.direction == nil }.sorted { $0.startDate < $1.startDate }
    }

    /// Un solo botón por panel para descartar todas las transferencias ya
    /// terminadas de esa dirección (completadas/canceladas/fallidas) de una
    /// vez, en vez de un "Done" por tarjeta — feedback del usuario
    /// (2026-09-07). `direction: nil` cubre las que nunca llegaron a
    /// resolverse (caso raro).
    func dismissAllFinishedTransfers(direction: TransferDirection?) {
        for (pid, transfer) in activeTransfers where transfer.direction == direction && transfer.status != .inProgress {
            dismissTransfer(pid: pid)
        }
    }

    func refreshAll() async {
        await refreshStatus()
        refreshNetworkInterfaces()
        refreshFiles()
        refreshPermissions()
    }

    /// Debe llamarse una sola vez al arrancar la app, antes de cualquier
    /// interacción del usuario.
    func checkForOrphanedServerAtLaunch() async {
        await refreshStatus()
        if serverStatus == .running {
            isBlockedByOrphanedServer = true
        }
    }

    /// El usuario autorizó detener el daemon huérfano detectado al arrancar.
    /// Si falla (canceló el diálogo de autorización), la app sigue bloqueada
    /// para que decida de nuevo — nunca continúa en silencio.
    func resolveOrphanedServer() async {
        await stop()
        if serverStatus != .running {
            isBlockedByOrphanedServer = false
        }
    }

    func refreshStatus() async {
        serverStatus = await serviceController.status()
    }

    func refreshNetworkInterfaces() {
        networkInterfaces = networkMonitor.currentInterfaces()
        if selectedInterfaceID == nil {
            selectedInterfaceID = networkInterfaces.first?.id
        }
    }

    func refreshFiles() {
        ensureRootDirectoryExists()
        files = fileSystemService.listEntries(in: configuration.rootDirectory)
    }

    func refreshPermissions() {
        workingPathPermissionsOK = fileSystemService.hasAppropriatePermissions(configuration.rootDirectory)
        let parent = configuration.rootDirectory.deletingLastPathComponent()
        parentFolderPermissionsOK = fileSystemService.hasAppropriatePermissions(parent)
    }

    /// Botón "Fix" junto a "Working path permissions" — feedback del usuario
    /// (2026-09-07): "esto siempre me ha aparecido OK, pero debe quedar que
    /// cuando no, haya un botón que solucione eso, igual que el Start del
    /// server". Solo agrega el bit de lectura/ejecución faltante para el
    /// dueño; no requiere autorización porque la app corre como el usuario
    /// actual y solo toca carpetas que ya le pertenecen.
    func repairWorkingPathPermissions() {
        guard fileSystemService.repairPermissions(configuration.rootDirectory) else {
            lastError = .permissionsRepairFailed
            return
        }
        refreshPermissions()
        dismissPermissionsPromptIfResolved()
    }

    /// Mismo botón, para "Parent folder permissions".
    func repairParentFolderPermissions() {
        let parent = configuration.rootDirectory.deletingLastPathComponent()
        guard fileSystemService.repairPermissions(parent) else {
            lastError = .permissionsRepairFailed
            return
        }
        refreshPermissions()
        dismissPermissionsPromptIfResolved()
    }

    private func dismissPermissionsPromptIfResolved() {
        if workingPathPermissionsOK, parentFolderPermissionsOK {
            isShowingPermissionsNeededPrompt = false
        }
    }

    func changeRootDirectory(to url: URL) {
        guard PathValidator.isValidRoot(url) else {
            lastError = .rootDirectoryInvalid
            return
        }
        configuration.rootDirectory = url
        log(.application, "TFTP root changed to \(url.path)")
        refreshFiles()
        refreshPermissions()
        if !workingPathPermissionsOK || !parentFolderPermissionsOK {
            isShowingPermissionsNeededPrompt = true
        }
    }

    func createEmptyFile(named name: String) {
        let destination = configuration.rootDirectory.appendingPathComponent(name)
        let created = FileManager.default.createFile(atPath: destination.path, contents: Data())
        log(.application, created ? "Created file \(name)" : "Failed to create file \(name)")
        refreshFiles()
    }

    /// El usuario pidió (2026-09-08) que el servidor no pueda arrancar
    /// mientras la carpeta TFTP o su padre tengan un problema de permisos
    /// sin resolver — en vez de arrancar igual y fallar de forma menos
    /// clara más adelante (o servir desde una carpeta a medio verificar).
    func start() async {
        refreshPermissions()
        guard workingPathPermissionsOK, parentFolderPermissionsOK else {
            lastError = .permissionsMustBeFixedFirst
            return
        }

        do {
            // `AppState.configuration` (root elegido con "Change Path", flags
            // de Settings) vive solo aquí — el actor `NativeTFTPService`
            // tiene su propia copia interna que nunca se actualizaba (bug
            // real encontrado 2026-09-07 al probar "Allow uploads": el
            // toggle no tenía ningún efecto porque nunca llegaba al servicio,
            // que seguía generando el plist con su config por defecto).
            try await serviceController.updateConfiguration(configuration)
            try await serviceController.start()
            log(.application, "Server started")
            logStreamMonitor.start { [weak self] line in
                self?.handleActivityLine(line)
            }
        } catch let error as TFTPServiceError {
            lastError = error
            log(.application, "Start failed: \(error.userFacingMessage)")
        } catch {
            lastError = .unknown
        }
        await refreshStatus()
    }

    func stop() async {
        logStreamMonitor.stop()
        trackingTasks.values.forEach { $0.cancel() }
        trackingTasks.removeAll()
        do {
            try await serviceController.stop()
            log(.application, "Server stopped")
        } catch let error as TFTPServiceError {
            lastError = error
            log(.application, "Stop failed: \(error.userFacingMessage)")
        } catch {
            lastError = .unknown
        }
        await refreshStatus()
    }

    func cancelTransfer(pid: Int32) async {
        guard activeTransfers[pid] != nil else { return }
        trackingTasks[pid]?.cancel()
        await ProcessKiller.kill(pid: pid)
        activeTransfers[pid]?.status = .cancelled
        activeTransfers[pid]?.endDate = Date()
        archiveTransfer(pid: pid)
    }

    func dismissTransfer(pid: Int32) {
        activeTransfers[pid] = nil
        trackingTasks[pid] = nil
        lastSpeedSamples[pid] = nil
        lastByteCounts[pid] = nil
    }

    private func ensureRootDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: configuration.rootDirectory,
            withIntermediateDirectories: true
        )
    }

    private func log(_ source: LogSource, _ message: String) {
        logEntries.append(LogEntry(date: Date(), source: source, message: message))
    }

    private func handleActivityLine(_ line: String) {
        log(.system, line)
        guard case .filenameDetected(let pid, let filename) = TransferActivityParser.parse(line: line) else { return }
        guard activeTransfers[pid] == nil else { return }

        let fileURL = configuration.rootDirectory.appendingPathComponent(filename)
        let knownDownloadSize = fileSystemService.fileSize(at: fileURL)

        activeTransfers[pid] = TransferProgress(
            pid: pid,
            filename: filename,
            startDate: Date(),
            endDate: nil,
            direction: nil,
            totalBytes: knownDownloadSize,
            transferredBytes: 0,
            speedBytesPerSecond: nil,
            status: .inProgress
        )

        trackTransfer(pid: pid, knownDownloadSize: knownDownloadSize)
    }

    /// Fuente única de verdad para una transferencia activa: progreso real,
    /// dirección y fin, todo leído de `nettop` (bytes reales enviados/
    /// recibidos por ESE proceso específico, sin sudo porque corre como el
    /// usuario actual). `tftpd` no expone esto por log ni API — verificado en
    /// vivo (2026-09-05). RRQ (descarga) = tftpd envía datos → `bytesOut`
    /// grande; WRQ (subida) = tftpd recibe datos → `bytesIn` grande. Una
    /// tarea independiente por PID permite trackear transferencias
    /// simultáneas de verdad (confirmado en vivo, 2026-09-07: dos `tftpd`
    /// corriendo a la vez sirviendo archivos distintos).
    private func trackTransfer(pid: Int32, knownDownloadSize: Int64?) {
        trackingTasks[pid]?.cancel()
        trackingTasks[pid] = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let counts = await NetworkByteMonitor.byteCounts(forPID: pid) else {
                    self.finalizeTransfer(pid: pid)
                    return
                }
                self.updateTransfer(pid: pid, counts: counts, knownDownloadSize: knownDownloadSize)
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private func updateTransfer(pid: Int32, counts: NetworkByteMonitor.ByteCounts, knownDownloadSize: Int64?) {
        lastByteCounts[pid] = counts
        guard var transfer = activeTransfers[pid], transfer.status == .inProgress else { return }

        if transfer.direction == nil {
            if counts.bytesOut > 4096, counts.bytesOut > counts.bytesIn * 2 {
                transfer.direction = .download
            } else if counts.bytesIn > 4096, counts.bytesIn > counts.bytesOut * 2 {
                transfer.direction = .upload
            }
        }

        switch transfer.direction {
        case .download:
            transfer.transferredBytes = counts.bytesOut
            transfer.totalBytes = knownDownloadSize
        case .upload:
            transfer.transferredBytes = counts.bytesIn
            // `totalBytes` was seeded at creation with the TARGET file's
            // pre-existing size (only meaningful for downloads) before the
            // direction was known — must be cleared here, or an upload to a
            // non-empty existing file shows a fabricated, meaningless
            // percentage against the OLD content's size instead of no
            // percentage at all. Bug found in vivo, 2026-09-07: an upload
            // legitimately showed "100%" purely by size coincidence with a
            // leftover target file from a prior test run.
            transfer.totalBytes = nil
        case nil:
            break
        }

        let now = Date()
        if let last = lastSpeedSamples[pid] {
            let elapsed = now.timeIntervalSince(last.date)
            if elapsed > 0 {
                let deltaBytes = transfer.transferredBytes - last.bytes
                transfer.speedBytesPerSecond = Double(deltaBytes) / elapsed
            }
        }
        lastSpeedSamples[pid] = (transfer.transferredBytes, now)

        activeTransfers[pid] = transfer
    }

    /// El proceso `tftpd` de esta sesión (socket-activated, uno por
    /// transferencia) desapareció — es la única señal de "terminó" que
    /// tenemos.
    ///
    /// Transferencias por localhost pueden terminar en menos de un ciclo de
    /// sondeo (150ms) sin que `updateTransfer` haya visto nunca un conteo que
    /// cruzara el umbral de dirección — quedarían atrapadas para siempre en
    /// el panel "Detecting" (bug real encontrado en vivo, 2026-09-07, con 3
    /// subidas de ~1GB terminando en <1s). Si eso pasa, se resuelve aquí con
    /// el último conteo conocido, sin exigir el margen de 2x — al terminar el
    /// proceso, cualquier byte movido ya identifica la dirección real.
    private func finalizeTransfer(pid: Int32) {
        guard var transfer = activeTransfers[pid], transfer.status == .inProgress else { return }

        if transfer.direction == nil, let counts = lastByteCounts[pid], counts.bytesOut != counts.bytesIn {
            if counts.bytesOut > counts.bytesIn {
                transfer.direction = .download
                transfer.transferredBytes = counts.bytesOut
            } else {
                transfer.direction = .upload
                transfer.transferredBytes = counts.bytesIn
                transfer.totalBytes = nil // ver nota en `updateTransfer`
            }
        }

        transfer.status = .completed
        transfer.endDate = Date()
        if transfer.direction == .download, let total = transfer.totalBytes {
            transfer.transferredBytes = total
        }
        activeTransfers[pid] = transfer
        lastByteCounts[pid] = nil
        archiveTransfer(pid: pid)
    }

    private func archiveTransfer(pid: Int32) {
        guard let transfer = activeTransfers[pid] else { return }
        let record = TFTPTransfer(
            date: transfer.startDate,
            clientAddress: nil,
            filename: transfer.filename,
            direction: transfer.direction,
            size: transfer.totalBytes ?? transfer.transferredBytes,
            status: transfer.status,
            duration: transfer.elapsedSeconds
        )
        transfers.insert(record, at: 0)
    }
}
