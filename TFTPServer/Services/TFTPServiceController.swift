// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Coordina las operaciones del servicio TFTP. La Presentation layer solo
/// conoce este controller, nunca `launchctl`, `plist` ni `NativeTFTPService`
/// directamente (PROJECT.md, sección 8 y 31).
final class TFTPServiceController: Sendable {
    private let service: TFTPServiceControlling

    init(service: TFTPServiceControlling) {
        self.service = service
    }

    func start() async throws {
        try await service.start()
    }

    func stop() async throws {
        try await service.stop()
    }

    func restart() async throws {
        try await service.restart()
    }

    func status() async -> TFTPStatus {
        await service.status()
    }

    func updateConfiguration(_ configuration: TFTPConfiguration) async throws {
        try await service.updateConfiguration(configuration)
    }
}
