// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                statusColumn(
                    title: "Server status",
                    systemImage: serverStatusIcon,
                    tint: serverStatusColor,
                    text: serverStatusText
                )
                Button(appState.serverStatus == .running ? "Stop" : "Start") {
                    Task {
                        if appState.serverStatus == .running {
                            await appState.stop()
                        } else {
                            await appState.start()
                        }
                    }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            Divider()
            statusColumn(
                title: "Working path permissions",
                systemImage: appState.workingPathPermissionsOK ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                tint: appState.workingPathPermissionsOK ? .green : .orange,
                text: appState.workingPathPermissionsOK ? "Attributes OK" : "Fix needed"
            )
            Divider()
            statusColumn(
                title: "Parent folder permissions",
                systemImage: appState.parentFolderPermissionsOK ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                tint: appState.parentFolderPermissionsOK ? .green : .orange,
                text: appState.parentFolderPermissionsOK ? "Attributes OK" : "Fix needed"
            )
        }
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func statusColumn(title: String, systemImage: String, tint: Color, text: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(text, systemImage: systemImage)
                .foregroundStyle(tint)
                .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity)
    }

    private var serverStatusIcon: String {
        switch appState.serverStatus {
        case .running: return "checkmark.circle.fill"
        case .stopped: return "stop.circle.fill"
        case .starting, .stopping: return "clock.fill"
        case .error: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var serverStatusColor: Color {
        switch appState.serverStatus {
        case .running: return .green
        case .stopped: return .secondary
        case .starting, .stopping: return .yellow
        case .error: return .red
        case .unknown: return .secondary
        }
    }

    private var serverStatusText: String {
        switch appState.serverStatus {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .starting: return "Starting…"
        case .stopping: return "Stopping…"
        case .error: return "Error"
        case .unknown: return "Unknown"
        }
    }
}

#Preview {
    StatusBarView()
        .environmentObject(AppState())
}
