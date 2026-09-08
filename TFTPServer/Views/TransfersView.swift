// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import SwiftUI

struct TransfersView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.transfers.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No Transfers Yet")
                    .font(.headline)
                Text("Completed transfers will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(appState.transfers) {
                TableColumn("Time") { transfer in
                    Text(transfer.date.formatted(date: .omitted, time: .standard))
                }
                TableColumn("Direction") { transfer in
                    Text(directionText(transfer.direction))
                }
                TableColumn("Filename", value: \.filename)
                TableColumn("Client IP") { transfer in
                    Text(transfer.clientAddress ?? "—")
                        .foregroundStyle(transfer.clientAddress == nil ? .secondary : .primary)
                }
                TableColumn("Size") { transfer in
                    Text(transfer.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                }
                TableColumn("Status") { transfer in
                    Text(statusText(transfer.status))
                }
                TableColumn("Duration") { transfer in
                    Text(transfer.duration.map { String(format: "%.1fs", $0) } ?? "—")
                }
            }
        }
    }

    private func directionText(_ direction: TransferDirection?) -> String {
        switch direction {
        case .upload: return "Upload"
        case .download: return "Download"
        case nil: return "—"
        }
    }

    private func statusText(_ status: TransferProgress.Status) -> String {
        switch status {
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .failed(let message): return "Failed: \(message)"
        }
    }
}

#Preview {
    TransfersView()
        .environmentObject(AppState())
}
