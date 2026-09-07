// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

struct SystemCapabilities: Sendable {
    let tftpdAvailable: Bool
    let tftpClientAvailable: Bool
    let launchdAvailable: Bool
    let architecture: String
    let macOSVersion: OperatingSystemVersion
}

/// Detecta capacidades del sistema en tiempo de ejecución.
///
/// No se asumen rutas fijas como API estable: se verifica su existencia real
/// (ver PROJECT.md, sección 12 — "Rutas del sistema").
struct SystemDetector: Sendable {
    init() {}

    func detectCapabilities() -> SystemCapabilities {
        let fileManager = FileManager.default
        return SystemCapabilities(
            tftpdAvailable: fileManager.isExecutableFile(atPath: "/usr/libexec/tftpd"),
            tftpClientAvailable: fileManager.isExecutableFile(atPath: "/usr/bin/tftp"),
            launchdAvailable: fileManager.fileExists(atPath: "/bin/launchctl"),
            architecture: currentArchitecture(),
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersion
        )
    }

    private func currentArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
