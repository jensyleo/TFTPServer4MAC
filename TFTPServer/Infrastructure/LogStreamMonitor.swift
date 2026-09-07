// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Transmite en vivo el log unificado de macOS para el proceso `tftpd`.
///
/// `--level debug` es obligatorio: por defecto `log stream`/`log show`
/// ocultan los mensajes de nivel debug/info, que es exactamente el nivel que
/// usa `tftpd -d15` (confirmado en vivo — sin este flag, el stream nunca
/// mostraba nada aunque el daemon sí estaba logueando).
@MainActor
final class LogStreamMonitor {
    private var process: Process?
    private var pipe: Pipe?

    func start(onLine: @escaping @MainActor @Sendable (String) -> Void) {
        guard process == nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--level", "debug",
            "--style", "compact",
            "--predicate", "process == \"tftpd\""
        ]

        let pipe = Pipe()
        process.standardOutput = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.split(separator: "\n").map(String.init)
            Task { @MainActor in
                lines.forEach(onLine)
            }
        }

        do {
            try process.run()
            self.process = process
            self.pipe = pipe
        } catch {
            onLine("Could not start log streaming: \(error.localizedDescription)")
        }
    }

    func stop() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        pipe = nil
    }
}
