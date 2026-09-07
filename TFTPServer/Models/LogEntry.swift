// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Diferencia logs propios de la app de los logs de tftpd/sistema
/// (PROJECT.md, sección 50).
enum LogSource: String {
    case application = "App"
    case system = "System"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let source: LogSource
    let message: String

    var formattedDate: String {
        date.formatted(date: .omitted, time: .standard)
    }
}
