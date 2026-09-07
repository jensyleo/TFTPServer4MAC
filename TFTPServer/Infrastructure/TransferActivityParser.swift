// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

enum TransferEvent {
    case filenameDetected(String)
}

/// Interpreta las líneas de debug del `tftpd` real (activado con `-l -d15`,
/// visibles solo con `log stream --level debug`, ver LogStreamMonitor) en
/// eventos estructurados.
///
/// Investigado en vivo en macOS Tahoe 26.6.2 (2026-09-04): tanto RRQ como WRQ
/// producen exactamente la misma línea `Filename: 'x'` seguida de
/// `Mode: 'octet'` — no hay ninguna línea que distinga lectura de escritura,
/// ni progreso por bloque (`"%s block %d..."`, `"Received %d bytes..."` del
/// binario nunca aparecieron en el log real pese al debug level 15; deben
/// usar una ruta de impresión que no pasa por syslog cuando corre sin tty).
/// Por eso el parser solo puede exponer "se detectó un archivo", y
/// `AppState` infiere la dirección observando si el archivo crece en disco.
enum TransferActivityParser {
    nonisolated(unsafe) private static let filenamePattern = /Filename: '(.+)'/

    static func parse(line: String) -> TransferEvent? {
        guard let match = line.firstMatch(of: filenamePattern) else { return nil }
        return .filenameDetected(String(match.1))
    }
}
