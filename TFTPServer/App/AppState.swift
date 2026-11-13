// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

@MainActor
final class AppState: ObservableObject {
    /// Sin tope, `logEntries`/`transfers` crecerían sin límite durante toda
    /// la vida de la app — una sesión larga con muchas transferencias podría
    /// acumular decenas de miles de entradas, degradando el `List`/`Table`
    /// que las muestra. Pedido del usuario (2026-09-08): revisar que exista
    /// algún límite, no necesariamente un toggle para desactivar el log.
    private static let maxLogEntries = 5000
    private static let maxTransferHistory = 1000
    @Published var serverStatus: TFTPStatus = .unknown
    @Published var configuration: TFTPConfiguration {
        didSet { saveConfiguration() }
    }
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
    /// Cuántas líneas del archivo de captura de IP (ver
    /// `ClientIPCaptureService`) ya se emparejaron con una transferencia —
    /// las líneas llegan aproximadamente en el mismo orden que las
    /// detecciones de `handleActivityLine`, así que se consumen en fila
    /// (FIFO), no por ningún identificador compartido (no existe uno: el
    /// puerto 69 no dice nada sobre a qué PID terminará asignándose la
    /// transferencia).
    private var consumedClientIPLines = 0

    private enum DefaultsKey {
        static let rootPath = "rootDirectoryPath"
        static let clientIPCapture = "clientIPCaptureEnabled"
    }

    private let defaults: UserDefaults

    init(
        serviceController: TFTPServiceController = TFTPServiceController(service: NativeTFTPService()),
        defaults: UserDefaults = .standard
    ) {
        self.serviceController = serviceController
        self.defaults = defaults
        self.configuration = Self.loadConfiguration(from: defaults)
        log(.application, "TFTP Server launched")
    }

    /// La carpeta guardada solo se reutiliza si sigue siendo una raíz válida
    /// (existe y pasa `PathValidator`); si fue borrada o movida, se vuelve al
    /// valor por defecto en vez de arrancar apuntando a algo inexistente.
    private static func loadConfiguration(from defaults: UserDefaults) -> TFTPConfiguration {
        var config = TFTPConfiguration.conservativeDefault
        if let path = defaults.string(forKey: DefaultsKey.rootPath) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if PathValidator.isValidRoot(url) {
                config.rootDirectory = url
            }
        }
        if defaults.object(forKey: DefaultsKey.clientIPCapture) != nil {
            config.isClientIPCaptureEnabled = defaults.bool(forKey: DefaultsKey.clientIPCapture)
        }
        return config
    }

    private func saveConfiguration() {
        defaults.set(configuration.rootDirectory.path, forKey: DefaultsKey.rootPath)
        defaults.set(configuration.isClientIPCaptureEnabled, forKey: DefaultsKey.clientIPCapture)
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
            consumedClientIPLines = 0
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

    /// Ícono de toggle pedido por el usuario (2026-09-08) para "Show client
    /// IP". Si el servidor ya está corriendo, aplicar el cambio requiere
    /// reiniciarlo — eso sí pide su propia autorización (inevitable, pero
    /// solo en ese caso puntual; activarlo antes de Start no pide nada
    /// aparte de la autorización normal de Start).
    func toggleClientIPCapture() async {
        configuration.isClientIPCaptureEnabled.toggle()
        guard serverStatus == .running else { return }

        // `serviceController.restart()` combina detener y arrancar en una
        // sola autorización (ver `NativeTFTPService.restart`) — antes esto
        // llamaba `stop()` + `start()` por separado, pidiendo la
        // contraseña/Touch ID dos veces (bug real reportado en vivo,
        // 2026-09-08). El resto replica lo que esos dos métodos hacían por
        // su cuenta (detener el sondeo de transferencias, reiniciar el
        // stream de logs).
        logStreamMonitor.stop()
        trackingTasks.values.forEach { $0.cancel() }
        trackingTasks.removeAll()

        do {
            try await serviceController.updateConfiguration(configuration)
            try await serviceController.restart()
            log(.application, "Server restarted to apply Show Client IP")
            consumedClientIPLines = 0
            logStreamMonitor.start { [weak self] line in
                self?.handleActivityLine(line)
            }
        } catch let error as TFTPServiceError {
            lastError = error
            log(.application, "Restart failed: \(error.userFacingMessage)")
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
        if logEntries.count > Self.maxLogEntries {
            logEntries.removeFirst(logEntries.count - Self.maxLogEntries)
        }
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
            status: .inProgress,
            clientIP: nextCapturedClientIP()
        )

        trackTransfer(pid: pid, knownDownloadSize: knownDownloadSize)
    }

    /// Empareja esta transferencia recién detectada con la siguiente línea
    /// sin consumir del archivo de captura de IP (ver
    /// `ClientIPCaptureService`) — no hay ningún identificador compartido
    /// entre ambas fuentes, así que se asume orden de llegada (FIFO). `nil`
    /// si la captura no está activa o todavía no hay una línea nueva que
    /// corresponda (puede llegar unos milisegundos después que la detección
    /// del nombre de archivo).
    private func nextCapturedClientIP() -> String? {
        guard configuration.isClientIPCaptureEnabled else { return nil }
        let lines = ClientIPCaptureService.readCapturedLines()
        guard consumedClientIPLines < lines.count else { return nil }
        defer { consumedClientIPLines += 1 }
        return ClientIPCaptureService.parseSourceIP(from: lines[consumedClientIPLines])
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
                    self.finalizeTransfer(pid: pid, knownDownloadSize: knownDownloadSize)
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

        // La línea de captura de IP puede escribirse unos milisegundos
        // después de que ya se detectó el nombre de archivo (buffering de
        // `tcpdump`) — reintentar en los primeros ciclos de sondeo (cada
        // 150ms) en vez de conformarse con el intento único al crear la
        // transferencia.
        if transfer.clientIP == nil, configuration.isClientIPCaptureEnabled {
            transfer.clientIP = nextCapturedClientIP()
        }

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
    /// Bug real encontrado en vivo (2026-09-08): con 50 transferencias de
    /// archivos diminutos (21 bytes) seguidas, TODAS quedaron atascadas para
    /// siempre en el panel "Detecting" — nunca se resolvió su dirección. La
    /// causa: un archivo tan pequeño se transfiere y el proceso `tftpd`
    /// termina antes de que el primer sondeo de `nettop` (cada 150ms en
    /// `trackTransfer`) alcance a tomar una sola muestra, así que
    /// `lastByteCounts[pid]` nunca se llena — el respaldo de abajo (que
    /// compara bytesOut/bytesIn) no tiene con qué trabajar. Segundo
    /// respaldo: si el archivo ya existía en el TFTP root al detectar la
    /// transferencia (`knownDownloadSize` no nulo), es casi seguro una
    /// descarga — nadie pide leer un archivo por su nombre para luego
    /// escribirlo con ese mismo comando.
    private func finalizeTransfer(pid: Int32, knownDownloadSize: Int64? = nil) {
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

        if transfer.direction == nil, let knownDownloadSize {
            transfer.direction = .download
            transfer.transferredBytes = knownDownloadSize
            transfer.totalBytes = knownDownloadSize
        }

        // Antes todo proceso que terminaba se marcaba "Completed", aunque el
        // cliente hubiera abortado a la mitad. Para descargas el total es
        // conocido, así que si la última muestra de bytes queda claramente
        // por debajo se marca como incompleta. La tolerancia cubre que esa
        // muestra puede tener hasta ~un ciclo de sondeo de retraso respecto
        // al final real (2% del total o 1s de velocidad, lo que sea mayor).
        // Subidas no se pueden evaluar: no hay total confiable.
        var incompletePercent: Int?
        if transfer.direction == .download,
           let total = transfer.totalBytes, total > 0,
           let counts = lastByteCounts[pid] {
            let tolerance = max(Double(total) * 0.02, transfer.speedBytesPerSecond ?? 0) + 1_048_576
            if Double(counts.bytesOut) + tolerance < Double(total) {
                incompletePercent = Int(Double(counts.bytesOut) / Double(total) * 100)
                transfer.transferredBytes = counts.bytesOut
            }
        }

        transfer.endDate = Date()
        if let incompletePercent {
            transfer.status = .failed("Incomplete — only \(incompletePercent)% was sent")
        } else {
            transfer.status = .completed
            if transfer.direction == .download, let total = transfer.totalBytes {
                transfer.transferredBytes = total
            }
        }
        activeTransfers[pid] = transfer
        lastByteCounts[pid] = nil
        archiveTransfer(pid: pid)
    }

    private func archiveTransfer(pid: Int32) {
        guard let transfer = activeTransfers[pid] else { return }
        let record = TFTPTransfer(
            date: transfer.startDate,
            clientAddress: transfer.clientIP,
            filename: transfer.filename,
            direction: transfer.direction,
            size: transfer.totalBytes ?? transfer.transferredBytes,
            status: transfer.status,
            duration: transfer.elapsedSeconds
        )
        transfers.insert(record, at: 0)
        if transfers.count > Self.maxTransferHistory {
            transfers.removeLast(transfers.count - Self.maxTransferHistory)
        }
    }
}
