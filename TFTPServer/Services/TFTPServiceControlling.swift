// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

protocol TFTPServiceControlling: Sendable {
    func start() async throws
    func stop() async throws
    func restart() async throws
    func status() async -> TFTPStatus
    func configuration() async throws -> TFTPConfiguration
    func updateConfiguration(_ configuration: TFTPConfiguration) async throws
}
