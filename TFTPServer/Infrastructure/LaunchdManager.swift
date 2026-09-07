// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Encapsula la interacción con `launchctl`.
///
/// Hallazgos de la Fase 0 (ver TFTPServerResearch/SystemCompatibilityReport.md)
/// que determinan este diseño:
///
/// - `launchctl load`/`unload` pueden reportar `Input/output error` en stderr con
///   exit code distinto de cero incluso cuando la operación SÍ tuvo efecto. Por
///   eso este manager nunca confía en el resultado de `load`/`unload` por sí
///   solo: siempre confirma el estado real con `launchctl print`.
/// - El daemon nativo (`com.apple.tftpd`) y una copia propia
///   (`com.jensyleo.tftpserver`) pueden registrarse ambos en el mismo socket UDP
///   ("tftp"/69) sin que launchd lo impida, pero cuál de los dos atiende cada
///   datagrama es indeterminado. Por eso `start()` en `NativeTFTPService` debe
///   verificar y, con permiso del usuario, descargar `com.apple.tftpd` antes de
///   cargar el propio.
struct LaunchdManager: Sendable {
    private let processRunner: ProcessRunning
    private let launchctlPath = URL(fileURLWithPath: "/bin/launchctl")

    init(processRunner: ProcessRunning = ProcessRunner()) {
        self.processRunner = processRunner
    }

    /// Verifica si un servicio está registrado en el dominio `system` de launchd,
    /// leyendo la salida de `launchctl print` en lugar de asumir nada por el
    /// exit code de `load`/`unload`.
    func isRegistered(label: String) async throws -> Bool {
        let result = try await processRunner.run(
            executable: launchctlPath,
            arguments: ["print", "system/\(label)"]
        )
        return !result.standardError.contains("Could not find service")
    }

    /// Carga un plist de LaunchDaemon. El resultado se confirma con `isRegistered`,
    /// no con el exit code de este comando.
    func load(plistPath: URL, label: String) async throws {
        _ = try await processRunner.run(
            executable: launchctlPath,
            arguments: ["load", "-w", plistPath.path]
        )
        guard try await isRegistered(label: label) else {
            throw TFTPServiceError.serviceStartFailed
        }
    }

    /// Descarga un plist de LaunchDaemon. El resultado se confirma con
    /// `isRegistered`, no con el exit code de este comando.
    func unload(plistPath: URL, label: String) async throws {
        _ = try await processRunner.run(
            executable: launchctlPath,
            arguments: ["unload", "-w", plistPath.path]
        )
        guard try await isRegistered(label: label) == false else {
            throw TFTPServiceError.serviceStopFailed
        }
    }
}
