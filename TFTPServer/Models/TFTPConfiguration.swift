// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

struct TFTPConfiguration: Equatable, Sendable {
    var rootDirectory: URL
    /// Activa la captura acotada de IP de origen (ver
    /// `ClientIPCaptureService`) — se decide antes de pulsar Start para
    /// aplicarse en la misma elevación; cambiarlo con el servidor ya
    /// corriendo requiere su propia autorización (aunque ahora es una sola,
    /// ver `NativeTFTPService.restart`). Activada por defecto (2026-09-08,
    /// pedido del usuario) — saber de dónde viene cada transferencia es
    /// más útil que el costo mínimo de la captura acotada por sí sola.
    var isClientIPCaptureEnabled: Bool = true

    static var conservativeDefault: TFTPConfiguration {
        let defaultRoot = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("TFTP", isDirectory: true)
        return TFTPConfiguration(rootDirectory: defaultRoot)
    }
}
