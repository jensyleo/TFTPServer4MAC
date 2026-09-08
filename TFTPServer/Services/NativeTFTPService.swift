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

        // El plist viaja codificado en base64 en vez de en un heredoc de
        // shell (vulnerabilidad real corregida, 2026-09-07, auditoría de
        // seguridad): un heredoc con delimitador sin comillas simples
        // permite expansión de variables/comandos, y aun con el delimitador
        // entre comillas simples ('TFTPSERVER_PLIST_EOF', como estaba antes)
        // seguía siendo posible terminarlo antes de tiempo si el contenido
        // (en la práctica, `root.path`) contuviera un salto de línea seguido
        // exactamente de ese delimitador — inyectando comandos arbitrarios
        // ejecutados como administrador. base64 solo produce el alfabeto
        // [A-Za-z0-9+/=], sin metacaracteres de shell ni saltos de línea
        // relevantes, así que esta clase de inyección queda cerrada sin
        // importar el contenido del plist.
        let plistXML = Self.plistContents(root: currentConfiguration.rootDirectory)
        let plistBase64 = Data(plistXML.utf8).base64EncodedString()
        // La captura de IP (si está activa) se arranca en esta MISMA
        // elevación — una sola autorización cubre ambas cosas. Si el
        // usuario la activa con el servidor ya corriendo, eso pasa por
        // `restart()`/una nueva llamada a `start()`, que sí pediría su
        // propia autorización — inevitable, pero solo en ese caso puntual.
        let captureFragment = currentConfiguration.isClientIPCaptureEnabled
            ? "\n" + ClientIPCaptureService.startCaptureShellFragment()
            : ""
        let writeAndLoadCommand = """
        echo \(plistBase64) | base64 -D -o \(Self.ownPlistPath)
        launchctl load -w \(Self.ownPlistPath)\(captureFragment)
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
        // La limpieza de la captura de IP se intenta siempre, esté activa o
        // no — es inofensiva si nunca se inició (el `if -f` de adentro no
        // hace nada si el pidfile no existe) y evita depender de que
        // `currentConfiguration` siga reflejando lo que de verdad se lanzó.
        let unloadCommand = """
        launchctl unload -w \(Self.ownPlistPath)
        rm -f \(Self.ownPlistPath)
        \(ClientIPCaptureService.stopCaptureShellFragment())
        """

        do {
            try privilegedShellRunner.runElevated(unloadCommand)
        } catch PrivilegedShellError.userCancelled {
            throw TFTPServiceError.permissionDenied
        } catch {
            throw TFTPServiceError.serviceStopFailed
        }
    }

    func status() async -> TFTPStatus {
        guard let registered = try? await launchdManager.isRegistered(label: Self.ownLabel) else {
            return .unknown
        }
        return registered ? .running : .stopped
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

    /// `-w` (crear archivos nuevos por WRQ) se eliminó del plist por completo
    /// (2026-09-07): confirmado en vivo que no funciona de forma confiable en
    /// este modo — ver PROJECT.md ("`-w` no funciona de forma confiable fuera
    /// de modo chroot") para el hallazgo completo y la investigación
    /// pendiente sobre `-s`/`-u`. La única forma real de recibir una subida
    /// es que el archivo destino ya exista y sea "publicly writable" — eso sí
    /// funciona siempre, sin ningún flag, y es lo único que esta app puede
    /// prometer hoy.
    ///
    /// `UserName` hace que launchd baje privilegios de root al usuario actual
    /// para el proceso `tftpd` DESPUÉS de hacer `bind()` en el puerto
    /// privilegiado 69 (eso lo hace launchd mismo, como root, antes del
    /// handoff — no requiere que tftpd sea root). Resultado: cancelar una
    /// transferencia (`kill` sobre el proceso) ya no necesita otro diálogo de
    /// autorización — el proceso es del mismo usuario que la GUI. Cambio
    /// motivado por feedback del usuario (2026-09-04): pedir contraseña para
    /// cancelar "no tenía sentido".
    private static func plistContents(root: URL) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(ownLabel)</string>
            <key>UserName</key>
            <string>\(xmlEscaped(NSUserName()))</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/libexec/tftpd</string>
                <string>-i</string>
                <string>\(xmlEscaped(root.path))</string>
                <string>-l</string>
                <string>-d15</string>
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

    /// Vulnerabilidad real corregida (2026-09-07, auditoría de seguridad):
    /// `root.path` (elegido por el usuario vía "Change Path", o el nombre de
    /// cualquier carpeta a la que apunte) se interpolaba sin escapar dentro
    /// de este XML. Un nombre de carpeta que contuviera literalmente algo
    /// como `</string></array><key>ProgramArguments</key>...` habría podido
    /// reescribir claves del plist — incluyendo qué proceso lanza `launchd`
    /// como root. Escapar las 5 entidades XML básicas cierra esa vía sin
    /// afectar rutas normales.
    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
