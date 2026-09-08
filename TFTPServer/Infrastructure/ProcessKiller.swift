// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// El `tftpd` que atiende cada transferencia corre con el mismo usuario que
/// la GUI (`UserName` en el plist de NativeTFTPService), no como root — así
/// que matarlo no requiere autorización. Cancelar una transferencia debe
/// sentirse instantáneo, no pedir contraseña de nuevo (feedback del usuario,
/// 2026-09-04).
///
/// Mata un PID específico, no todos los `tftpd` (2026-09-07): con
/// transferencias simultáneas reales, cancelar una no debe tocar las demás.
enum ProcessKiller {
    static func kill(pid: Int32) async {
        _ = try? await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/bin/kill"),
            arguments: [String(pid)]
        )
    }
}
