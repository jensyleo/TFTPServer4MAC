// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

enum TransferDirection: Equatable {
    case upload
    case download
}

/// Registro histórico de una transferencia ya finalizada, para la tab
/// "Transfers" (PROJECT.md, sección 21). `clientAddress` y `direction` pueden
/// no conocerse con certeza — ver limitaciones documentadas en
/// TransferActivityParser y AppState.
struct TFTPTransfer: Identifiable {
    let id = UUID()
    let date: Date
    let clientAddress: String?
    let filename: String
    let direction: TransferDirection?
    let size: Int64?
    let status: TransferProgress.Status
    let duration: TimeInterval?
}
