// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import SwiftUI

/// Bloquea el uso de la app hasta que el usuario autorice detener un
/// servidor TFTP que quedó corriendo de una sesión anterior mal cerrada
/// (Force Quit, kill -9, corte de energía). Decisión explícita del usuario
/// (2026-09-04): nunca continuar en silencio con un daemon huérfano.
struct OrphanedServerBlockingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isResolving = false
    /// Pedido del usuario (2026-09-08): "Quit App" cerraba la app dejando el
    /// servidor huérfano corriendo, sin ninguna advertencia — inconsistente
    /// con el propósito de esta pantalla entera (nunca un daemon huérfano en
    /// silencio). No se bloquea la opción (sigue siendo válida para "ahora
    /// no quiero resolver esto"), pero ahora exige una confirmación
    /// explícita que dice exactamente qué va a quedar corriendo.
    @State private var isShowingQuitConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("TFTP Server Still Running")
                .font(.headline)

            Text("""
            A TFTP server from a previous session is still active on this Mac. \
            This usually happens after a force quit or crash. For security, \
            you must stop it before using this app.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            if let error = appState.lastError {
                Text(error.userFacingMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    isResolving = true
                    await appState.resolveOrphanedServer()
                    isResolving = false
                }
            } label: {
                if isResolving {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Stop Server & Continue")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isResolving)

            Button("Quit App") {
                isShowingQuitConfirmation = true
            }
        }
        .padding(32)
        .frame(width: 380)
        .interactiveDismissDisabled()
        .alert("The Server Will Keep Running", isPresented: $isShowingQuitConfirmation) {
            Button("Quit Anyway", role: .destructive) {
                // NSApp.terminate(nil) dispararía de nuevo
                // AppDelegate.applicationShouldTerminate, que intentaría
                // detener el servidor huérfano y pediría otra autorización —
                // justo lo contrario de lo que este botón promete (salir sin
                // resolver nada). exit(0) cierra el proceso sin pasar por ese
                // hook (bug reportado 2026-09-04).
                exit(0)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Quitting without stopping it leaves this unauthenticated TFTP server active and reachable on your network until you reopen the app and stop it, or restart this Mac.")
        }
    }
}

#Preview {
    OrphanedServerBlockingView()
        .environmentObject(AppState())
}
