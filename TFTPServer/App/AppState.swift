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
    @Published var diagnostics: [DiagnosticResult] = []
    @Published var lastError: TFTPServiceError?
    @Published var files: [FileEntry] = []
    @Published var logEntries: [LogEntry] = []
    @Published var workingPathPermissionsOK = true
    @Published var parentFolderPermissionsOK = true
    @Published var activeTransfer: TransferProgress?
    /// `true` cuando, al arrancar, se detecta que el servidor ya estaba
    /// corriendo desde una sesión anterior que no cerró limpiamente (p. ej.
    /// Force Quit / kill -9, que no permite ejecutar ningún código de
    /// limpieza — ver AppDelegate). Bloquea el uso de la app hasta que el
    /// usuario autorice detenerlo, por decisión explícita del usuario
    /// (2026-09-04): nunca continuar en silencio con un daemon huérfano.
    @Published var isBlockedByOrphanedServer = false
    @Published var queueSession: QueueSession?

    private let serviceController: TFTPServiceController
    private let networkMonitor = NetworkMonitor()
    private let fileSystemService = FileSystemService()
    private let logStreamMonitor = LogStreamMonitor()
    private var transferTrackingTask: Task<Void, Never>?
    private var lastSpeedSample: (bytes: Int64, date: Date)?

    init(serviceController: TFTPServiceController = TFTPServiceController(service: NativeTFTPService())) {
        self.serviceController = serviceController
        self.configuration = .conservativeDefault
        log(.application, "TFTP Server launched")
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

    func changeRootDirectory(to url: URL) {
        guard PathValidator.isValidRoot(url) else {
            lastError = .rootDirectoryInvalid
            return
        }
        configuration.rootDirectory = url
        log(.application, "TFTP root changed to \(url.path)")
        refreshFiles()
        refreshPermissions()
    }

    func createEmptyFile(named name: String) {
        let destination = configuration.rootDirectory.appendingPathComponent(name)
        let created = FileManager.default.createFile(atPath: destination.path, contents: Data())
        log(.application, created ? "Created file \(name)" : "Failed to create file \(name)")
        refreshFiles()
    }

    func start() async {
        do {
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
        transferTrackingTask?.cancel()
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

    func cancelActiveTransfer() async {
        guard activeTransfer != nil else { return }
        transferTrackingTask?.cancel()
        await ProcessKiller.killTftpdChild()
        activeTransfer?.status = .cancelled
        activeTransfer?.endDate = Date()
        archiveActiveTransfer()
    }

    func dismissActiveTransfer() {
        activeTransfer = nil
    }

    /// Toma un snapshot de los archivos actualmente en la carpeta TFTP y los
    /// fija como el lote a trackear (ver PROJECT.md sección 49.2). No cambia
    /// nada del comportamiento real del servidor — es puramente un contador
    /// visual de qué tanto de ese lote ya fue efectivamente pedido por algún
    /// dispositivo.
    func startQueueSession() {
        guard serverStatus == .running else {
            lastError = .serverNotRunning
            return
        }
        refreshFiles()
        let filenames = files.map(\.name)
        guard let session = QueueSession(filenames: filenames) else {
            lastError = .emptyQueueFolder
            return
        }
        lastError = nil
        queueSession = session
        log(.application, "Queue started: \(filenames.count) file(s) in \(session.totalBatches) batch(es)")
    }

    func stopQueueSession() {
        queueSession = nil
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
        guard case .filenameDetected(let filename) = TransferActivityParser.parse(line: line) else { return }

        let fileURL = configuration.rootDirectory.appendingPathComponent(filename)
        let knownDownloadSize = fileSystemService.fileSize(at: fileURL)

        activeTransfer = TransferProgress(
            filename: filename,
            startDate: Date(),
            endDate: nil,
            direction: nil,
            totalBytes: knownDownloadSize,
            transferredBytes: 0,
            speedBytesPerSecond: nil,
            status: .inProgress
        )
        lastSpeedSample = nil

        trackActiveTransfer(knownDownloadSize: knownDownloadSize)
    }

    /// Fuente única de verdad para una transferencia activa: progreso real,
    /// dirección y fin, todo leído de `nettop` (bytes reales enviados/
    /// recibidos por el proceso `tftpd`, sin sudo porque corre como el
    /// usuario actual). `tftpd` no expone esto por log ni API — verificado en
    /// vivo (2026-09-05). RRQ (descarga) = tftpd envía datos → `bytesOut`
    /// grande; WRQ (subida) = tftpd recibe datos → `bytesIn` grande.
    private func trackActiveTransfer(knownDownloadSize: Int64?) {
        transferTrackingTask?.cancel()
        transferTrackingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let pid = await NetworkByteMonitor.currentPID() else {
                    self.finalizeActiveTransfer()
                    return
                }
                if let counts = await NetworkByteMonitor.byteCounts(forPID: pid) {
                    self.updateActiveTransfer(counts: counts, knownDownloadSize: knownDownloadSize)
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private func updateActiveTransfer(counts: NetworkByteMonitor.ByteCounts, knownDownloadSize: Int64?) {
        guard var transfer = activeTransfer, transfer.status == .inProgress else { return }

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
        case nil:
            break
        }

        let now = Date()
        if let last = lastSpeedSample {
            let elapsed = now.timeIntervalSince(last.date)
            if elapsed > 0 {
                let deltaBytes = transfer.transferredBytes - last.bytes
                transfer.speedBytesPerSecond = Double(deltaBytes) / elapsed
            }
        }
        lastSpeedSample = (transfer.transferredBytes, now)

        activeTransfer = transfer
    }

    /// El proceso `tftpd` de esta sesión (socket-activated, uno por
    /// transferencia) desapareció — es la única señal de "terminó" que
    /// tenemos.
    private func finalizeActiveTransfer() {
        guard var transfer = activeTransfer, transfer.status == .inProgress else { return }
        transfer.status = .completed
        transfer.endDate = Date()
        activeTransfer = transfer
        archiveActiveTransfer()
    }

    private func archiveActiveTransfer() {
        guard let transfer = activeTransfer else { return }
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

        if transfer.status == .completed {
            queueSession?.markCompleted(filename: transfer.filename)
        }
    }
}
