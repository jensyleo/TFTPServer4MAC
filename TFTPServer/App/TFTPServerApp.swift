// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import SwiftUI

@main
struct TFTPServerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(appDelegate.appState)
        }
        .commands {
            CommandGroup(replacing: .help) {
                HelpMenuButton()
            }
        }

        // `Window` (not `WindowGroup`): a single, unique window — opening
        // "Help" again while one's already showing should just bring it
        // forward, not spawn a second copy. Mirrors ROMForge/HardwareSentry's
        // own Help window (jensyleo's request, 2026-09-05).
        Window("TFTP Server Help", id: "help") {
            HelpView()
        }
    }
}

private struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("TFTP Server Help") { openWindow(id: "help") }
    }
}
