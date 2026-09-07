// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0
    @State private var isShowingCreateFileAlert = false
    @State private var newFileName = ""

    var body: some View {
        VStack(spacing: 0) {
            pathAndInterfaceBar

            Picker("", selection: $selectedTab) {
                Text("Current Path").tag(0)
                Text("Transfers").tag(1)
                Text("Log Viewer").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            Group {
                switch selectedTab {
                case 0: CurrentPathView()
                case 1: TransfersView()
                default: LogViewerView()
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            StatusBarView()
        }
        .frame(minWidth: 640, minHeight: 460)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    presentChangePathPanel()
                } label: {
                    Label("Change Path", systemImage: "folder.badge.gearshape")
                        .labelStyle(.titleAndIcon)
                }

                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appState.configuration.rootDirectory.path)
                } label: {
                    Label("Reveal", systemImage: "magnifyingglass")
                        .labelStyle(.titleAndIcon)
                }

                Button {
                    newFileName = ""
                    isShowingCreateFileAlert = true
                } label: {
                    Label("Create File", systemImage: "doc.badge.plus")
                        .labelStyle(.titleAndIcon)
                }

                Button {
                    appState.refreshFiles()
                    appState.refreshPermissions()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }

                Button {
                    if appState.queueSession != nil {
                        appState.stopQueueSession()
                    } else {
                        appState.startQueueSession()
                    }
                } label: {
                    Label(
                        appState.queueSession != nil ? "Stop Queue" : "Start Queue",
                        systemImage: "tray.full"
                    )
                    .labelStyle(.titleAndIcon)
                }
            }
        }
        .alert("New File", isPresented: $isShowingCreateFileAlert) {
            TextField("File name", text: $newFileName)
            Button("Create") {
                guard !newFileName.isEmpty else { return }
                appState.createEmptyFile(named: newFileName)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: Binding(
            get: { appState.lastError != nil },
            set: { isPresented in if !isPresented { appState.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { appState.lastError = nil }
        } message: {
            Text(appState.lastError?.userFacingMessage ?? "")
        }
        .task {
            await appState.checkForOrphanedServerAtLaunch()
            await appState.refreshAll()
        }
        .sheet(item: $appState.activeTransfer) { transfer in
            TransferProgressSheet(transfer: transfer)
        }
        .sheet(isPresented: $appState.isBlockedByOrphanedServer) {
            OrphanedServerBlockingView()
        }
    }

    private var pathAndInterfaceBar: some View {
        HStack {
            Text(appState.configuration.rootDirectory.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Spacer()

            Picker("", selection: $appState.selectedInterfaceID) {
                ForEach(appState.networkInterfaces) { interface in
                    Text("\(interface.displayName): \(interface.ipv4Address ?? "—")")
                        .tag(Optional(interface.id))
                }
            }
            .frame(maxWidth: 260)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private func presentChangePathPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            appState.changeRootDirectory(to: url)
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState())
}
