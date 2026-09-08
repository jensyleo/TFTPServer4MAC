// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import SwiftUI

/// Aparece justo después de elegir una carpeta con "Change Path" cuando esa
/// carpeta (o su padre) tiene un problema de permisos, con el botón "Fix"
/// correspondiente ahí mismo — en vez de depender de que el usuario note el
/// "Fix needed" en la barra de estado inferior. Pedido del usuario
/// (2026-09-08): "que verifique si la carpeta ya tiene fix y si no lo tiene
/// genere una ventana emergente con el botón de fix".
///
/// No bloquea nada (a diferencia de `OrphanedServerBlockingView`): Start ya
/// rechaza arrancar por su cuenta mientras haya un problema sin resolver
/// (`AppState.start()`), así que esta ventana es solo un aviso más
/// oportuno, no la única barrera de seguridad.
struct PermissionsNeededView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("This Folder Needs a Permission Fix")
                .font(.headline)

            Text("The server won't be able to start from this folder until the issue below is fixed.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                if !appState.workingPathPermissionsOK {
                    permissionRow(title: "Working path permissions") {
                        appState.repairWorkingPathPermissions()
                    }
                }
                if !appState.parentFolderPermissionsOK {
                    permissionRow(title: "Parent folder permissions") {
                        appState.repairParentFolderPermissions()
                    }
                }
            }

            Button("Not Now") {
                appState.isShowingPermissionsNeededPrompt = false
            }
        }
        .padding(32)
        .frame(width: 380)
    }

    @ViewBuilder
    private func permissionRow(title: String, fix: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
            Spacer()
            Button("Fix", action: fix)
        }
    }
}

#Preview {
    PermissionsNeededView()
        .environmentObject(AppState())
}
