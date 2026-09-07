// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import SwiftUI

struct CurrentPathView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Table(appState.files) {
            TableColumn("Name", value: \.name)
            TableColumn("Date modified") { file in
                Text(file.formattedDate)
            }
            TableColumn("Size") { file in
                Text(file.formattedSize)
            }
        }
    }
}

#Preview {
    CurrentPathView()
        .environmentObject(AppState())
}
