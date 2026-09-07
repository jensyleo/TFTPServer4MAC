// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit

/// Garantiza que cerrar la app (Cmd+Q, menú, etc.) detiene el servidor TFTP
/// si estaba corriendo — coherente con el enfoque "sin rastro en el sistema"
/// (PROJECT.md, sección 33): la app no debe dejar un daemon huérfano cargado
/// después de cerrarse. `.terminateLater` retrasa el cierre real hasta que
/// `stop()` (que incluye el `launchctl unload` + borrado del plist) termine.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard appState.serverStatus == .running else {
            return .terminateNow
        }

        Task { @MainActor in
            await appState.stop()
            // Si el usuario canceló el diálogo de autorización, stop() falla
            // y el servidor sigue corriendo — en ese caso NO se debe cerrar
            // la app dejando un daemon huérfano; se cancela el quit para que
            // el usuario decida de nuevo (bug reportado 2026-09-04: Cmd+Q +
            // Cancel cerraba la app igual, dejando el server activo).
            let stoppedSuccessfully = appState.serverStatus != .running
            NSApp.reply(toApplicationShouldTerminate: stoppedSuccessfully)
        }
        return .terminateLater
    }
}
