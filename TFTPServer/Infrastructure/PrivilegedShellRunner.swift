// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

enum PrivilegedShellError: Error, Sendable {
    case userCancelled
    case scriptFailed(String)
}

protocol PrivilegedShellRunning: Sendable {
    /// Ejecuta un comando de shell una sola vez con privilegios de
    /// administrador, usando el diálogo nativo de autorización de macOS
    /// (Touch ID / contraseña) vía AppleScript `do shell script ... with
    /// administrator privileges`. No usa `sudo` de terminal ni deja nada
    /// registrado de forma persistente (PROJECT.md, sección 33 — el usuario
    /// decidió el 2026-09-04 no usar SMAppService para evitar que la app
    /// aparezca en Ajustes del Sistema; este es el mecanismo de reemplazo).
    func runElevated(_ shellCommand: String) throws
}

struct PrivilegedShellRunner: PrivilegedShellRunning {
    func runElevated(_ shellCommand: String) throws {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScriptSource = "do shell script \"\(escaped)\" with administrator privileges"

        guard let script = NSAppleScript(source: appleScriptSource) else {
            throw PrivilegedShellError.scriptFailed("Could not create AppleScript")
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let number = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            // -128 = el usuario canceló el diálogo de autorización.
            if number == -128 {
                throw PrivilegedShellError.userCancelled
            }
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
            throw PrivilegedShellError.scriptFailed(message)
        }
    }
}
