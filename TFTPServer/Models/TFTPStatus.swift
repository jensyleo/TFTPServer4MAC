// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Estado observable del servicio TFTP.
///
/// El daemon nativo (`tftpd`) es socket-activated: no existe un proceso de larga
/// duración con PID estable. `launchctl print` reporta `state = not running` en
/// reposo aunque el socket esté escuchando. Por eso el estado real no se deriva
/// de "hay un proceso corriendo" sino de si el listener del socket está armado
/// (ver TFTPServerResearch/SystemCompatibilityReport.md, sección 3).
enum TFTPStatus: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case error
    case unknown
}
