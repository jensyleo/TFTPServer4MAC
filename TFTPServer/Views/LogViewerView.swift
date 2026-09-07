// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import SwiftUI

struct LogViewerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(appState.logEntries) { entry in
            HStack {
                Text(entry.formattedDate)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(entry.source.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Text(entry.message)
            }
        }
    }
}

#Preview {
    LogViewerView()
        .environmentObject(AppState())
}
