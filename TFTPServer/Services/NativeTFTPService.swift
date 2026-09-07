// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Implementación que utiliza el `tftpd` nativo de macOS directamente vía
/// `launchctl load`/`unload` sobre un plist propio, exactamente como se probó
/// manualmente en la Fase 0 (TFTPServerResearch/SystemCompatibilityReport.md).
///
/// Decisión (2026-09-04): se descartó `SMAppService`/`TFTPHelper` porque
/// registra la app en Ajustes del Sistema → Elementos de inicio de forma
/// persistente. El usuario pidió explícitamente un enfoque monolítico: al
/// pulsar Start se eleva privilegios una sola vez (diálogo nativo de
/// administrador, no sudo de terminal — ver PrivilegedShellRunner), se
/// escribe el plist, se hace `load`; al pulsar Stop se hace `unload` y se
/// borra el plist. Sin rastro persistente, sin aparecer en el sistema.
actor NativeTFTPService: TFTPServiceControlling {
    static let appleLabel = "com.apple.tftpd"
    static let ownLabel = "com.jensyleo.tftpserver"
    static let ownPlistPath = "/Library/LaunchDaemons/com.jensyleo.tftpserver.plist"

    private let launchdManager: LaunchdManager
    private let privilegedShellRunner: PrivilegedShellRunning
    private let systemDetector: SystemDetector
    private var currentConfiguration: TFTPConfiguration

    init(
        launchdManager: LaunchdManager = LaunchdManager(),
        privilegedShellRunner: PrivilegedShellRunning = PrivilegedShellRunner(),
        systemDetector: SystemDetector = SystemDetector(),
        configuration: TFTPConfiguration = .conservativeDefault
    ) {
        self.launchdManager = launchdManager
        self.privilegedShellRunner = privilegedShellRunner
        self.systemDetector = systemDetector
        self.currentConfiguration = configuration
    }

    func start() async throws {
        let capabilities = systemDetector.detectCapabilities()
        guard capabilities.tftpdAvailable else {
            throw TFTPServiceError.tftpdNotFound
        }

        guard PathValidator.isValidRoot(currentConfiguration.rootDirectory) else {
            throw TFTPServiceError.rootDirectoryInvalid
        }

        // com.apple.tftpd y nuestro propio label no deben coexistir en el
        // mismo socket UDP/69 (comportamiento indeterminado, confirmado en
        // Fase 0).
        if try await launchdManager.isRegistered(label: Self.appleLabel) {
            throw TFTPServiceError.conflictingSystemService
        }

        let plistXML = Self.plistContents(
            root: currentConfiguration.rootDirectory,
            allowWrites: currentConfiguration.allowUploads || currentConfiguration.allowCreateFiles
        )
        let writeAndLoadCommand = """
        cat > \(Self.ownPlistPath) << 'TFTPSERVER_PLIST_EOF'
        \(plistXML)
        TFTPSERVER_PLIST_EOF
        launchctl load -w \(Self.ownPlistPath)
        """

        do {
            try privilegedShellRunner.runElevated(writeAndLoadCommand)
        } catch PrivilegedShellError.userCancelled {
            throw TFTPServiceError.permissionDenied
        } catch {
            throw TFTPServiceError.serviceStartFailed
        }

        // launchctl load puede reportar error incluso cuando sí tuvo efecto
        // (Fase 0) — confirmar siempre con print, nunca con el resultado de load.
        guard try await launchdManager.isRegistered(label: Self.ownLabel) else {
            throw TFTPServiceError.serviceStartFailed
        }
    }

    func stop() async throws {
        let unloadCommand = """
        launchctl unload -w \(Self.ownPlistPath)
        rm -f \(Self.ownPlistPath)
        """

        do {
            try privilegedShellRunner.runElevated(unloadCommand)
        } catch PrivilegedShellError.userCancelled {
            throw TFTPServiceError.permissionDenied
        } catch {
            throw TFTPServiceError.serviceStopFailed
        }
    }

    func restart() async throws {
        try await stop()
        try await start()
    }

    func status() async -> TFTPStatus {
        guard let registered = try? await launchdManager.isRegistered(label: Self.ownLabel) else {
            return .unknown
        }
        return registered ? .running : .stopped
    }

    func configuration() async throws -> TFTPConfiguration {
        currentConfiguration
    }

    func updateConfiguration(_ configuration: TFTPConfiguration) async throws {
        guard PathValidator.isValidRoot(configuration.rootDirectory) else {
            throw TFTPServiceError.rootDirectoryInvalid
        }
        currentConfiguration = configuration
        // Si el servidor ya está corriendo con el root anterior, el usuario
        // debe reiniciarlo explícitamente para aplicar el cambio (restart()),
        // en vez de recargar el plist de forma implícita aquí.
    }

    /// Traducción honesta de `TFTPConfiguration` a flags reales de `tftpd`:
    ///
    /// - **`allowUploads`/`allowCreateFiles` → `-w`**: sin `-w`, el daemon
    ///   nunca crea archivos nuevos, pero SÍ permite sobrescribir un archivo
    ///   ya existente si es "publicly writable" (permisos de escritura para
    ///   todos) — verificado en vivo (2026-09-04). Es una limitación real del
    ///   binario nativo: la app no puede bloquear al 100% las subidas sin
    ///   `-w` si el usuario tiene archivos con permisos de escritura amplios
    ///   en su TFTP root. Se documenta aquí en vez de fingir un control que
    ///   no existe.
    /// `UserName` hace que launchd baje privilegios de root al usuario actual
    /// para el proceso `tftpd` DESPUÉS de hacer `bind()` en el puerto
    /// privilegiado 69 (eso lo hace launchd mismo, como root, antes del
    /// handoff — no requiere que tftpd sea root). Resultado: cancelar una
    /// transferencia (`kill` sobre el proceso) ya no necesita otro diálogo de
    /// autorización — el proceso es del mismo usuario que la GUI. Cambio
    /// motivado por feedback del usuario (2026-09-04): pedir contraseña para
    /// cancelar "no tenía sentido".
    private static func plistContents(root: URL, allowWrites: Bool) -> String {
        let writeFlag = allowWrites ? "\n                <string>-w</string>" : ""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(ownLabel)</string>
            <key>UserName</key>
            <string>\(NSUserName())</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/libexec/tftpd</string>
                <string>-i</string>
                <string>\(root.path)</string>
                <string>-l</string>
                <string>-d15</string>\(writeFlag)
            </array>
            <key>Sockets</key>
            <dict>
                <key>Listeners</key>
                <dict>
                    <key>SockServiceName</key>
                    <string>tftp</string>
                    <key>SockType</key>
                    <string>dgram</string>
                </dict>
            </dict>
            <key>inetdCompatibility</key>
            <dict>
                <key>Wait</key>
                <true/>
            </dict>
        </dict>
        </plist>
        """
    }
}
