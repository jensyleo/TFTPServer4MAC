// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import SwiftUI

/// Panel flotante, no modal, para las transferencias de UNA sola dirección —
/// separado en dos ventanas independientes (Downloads / Uploads) a pedido del
/// usuario (2026-09-07): "para carga una ventana y para descarga otra, de esa
/// manera se discrimina qué se sube y qué se baja". Cada panel es totalmente
/// independiente: su propia lista, su propia barra global, su propio botón
/// "Done" — una transferencia recién detectada no afecta ni oculta las
/// tarjetas ya terminadas del otro panel ni del mismo.
struct DirectionalTransfersPanel: View {
    @EnvironmentObject private var appState: AppState
    let direction: TransferDirection
    let transfers: [TransferProgress]

    /// "Done" solo se ofrece cuando NINGUNA transferencia del panel sigue en
    /// curso — feedback explícito del usuario (2026-09-07, repetido dos
    /// veces): no debe aparecer mientras algo todavía esté transfiriéndose,
    /// aunque ya haya otras completadas. Antes se mostraba con solo una
    /// terminada (para descartarla sin esperar a las demás); ese diseño se
    /// abandona a favor de esta regla más simple y explícita.
    private var allTransfersFinished: Bool {
        !transfers.isEmpty && !transfers.contains { $0.status == .inProgress }
    }

    var body: some View {
        if !transfers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                header

                if transfers.count > 1 {
                    Divider()
                }

                // `ScrollView` con tope de altura: sin esto, 3+ tarjetas con
                // velocidad/ETA/tiempo transcurrido pueden crecer más que la
                // ventana y superponerse con el panel de la esquina opuesta
                // (bug real visto en vivo, 2026-09-07, con 3 subidas + 3
                // descargas a la vez). 380pt en vez de un valor más bajo: con
                // 280pt, una tercera tarjeta en curso quedaba cortada justo
                // en su título, sin mostrar nada de su progreso — parecía
                // "rota" en vez de simplemente necesitar scroll (bug real
                // encontrado en vivo el mismo día, tras el primer ajuste). La
                // separación de Cancel/Done se resuelve con el `Divider()`
                // de abajo, no con esta altura — no volver a bajarla para
                // "arreglar" ese problema.
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(transfers) { transfer in
                            TransferCard(transfer: transfer)
                            if transfer.id != transfers.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: 380)

                if allTransfersFinished {
                    Divider()
                    HStack {
                        Spacer()
                        Button("Done") {
                            appState.dismissAllFinishedTransfers(direction: direction)
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(16)
            .frame(width: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 8)
            .padding(16)
            // Sin esto, cuando una transferencia pasa del panel "Detecting"
            // (centro-arriba) a este panel (una esquina inferior) se sentía
            // como un salto brusco de posición — un panel desaparece y el
            // otro aparece de golpe, sin transición. Feedback del usuario
            // (2026-09-07): "sale un menú en el centro y después se
            // desplaza a la izquierda... tiene inconsistencias". No es un
            // salto real de un mismo elemento (son dos paneles distintos por
            // diseño — no se puede conocer la posición final hasta resolver
            // la dirección), pero un fundido suaviza la transición en vez de
            // un cambio instantáneo.
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            // Ojo: animar sobre `appState.activeTransfers` directamente
            // dispara la transición en CADA actualización de progreso (cada
            // ~150ms), no solo cuando una tarjeta aparece/desaparece —
            // produce un "fantasma" visible con números superpuestos en
            // cada refresco (bug real visto en vivo, 2026-09-07). Animar
            // solo sobre el conjunto de PIDs presentes evita eso: cambia
            // únicamente cuando se agrega o quita una transferencia.
            .animation(.easeOut(duration: 0.2), value: transfers.map(\.pid))
        }
    }

    @ViewBuilder
    private var header: some View {
        let title = direction == .download ? "Downloads" : "Uploads"
        let icon = direction == .download ? "arrow.down.circle" : "arrow.up.circle"

        VStack(alignment: .leading, spacing: 4) {
            Label("\(title) — \(transfers.count) this session", systemImage: icon)
                .font(.caption.weight(.medium))

            if direction == .download, let fraction = appState.globalDownloadFraction {
                HStack {
                    Text("Combined progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(fraction * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: fraction)
            }

            if direction == .upload, let uploads = appState.uploadsSummary {
                let bytesText = ByteCountFormatter.string(fromByteCount: uploads.totalBytesReceived, countStyle: .file)
                Text("\(bytesText) received across \(uploads.count) transfer\(uploads.count == 1 ? "" : "s") — no combined percentage (no reliable total).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Transferencias detectadas hace apenas un instante, cuya dirección todavía
/// no se ha podido determinar (normalmente dura una fracción de segundo —
/// ver `AppState.updateTransfer`). Panel aparte, minimalista, para no forzar
/// a los paneles de Downloads/Uploads a lidiar con un estado "sin dirección".
struct DetectingTransfersPanel: View {
    @EnvironmentObject private var appState: AppState
    let transfers: [TransferProgress]

    /// Normalmente esto nunca debería pasar (ver `AppState.finalizeTransfer`)
    /// — pero si alguna vez una transferencia termina sin que su dirección
    /// se resuelva (p. ej. cero bytes movidos), se queda aquí para siempre
    /// sin este botón. Sin él no había forma de descartarla.
    /// Mismo criterio que en `DirectionalTransfersPanel`: solo cuando nada
    /// sigue en curso.
    private var allTransfersFinished: Bool {
        !transfers.isEmpty && !transfers.contains { $0.status == .inProgress }
    }

    var body: some View {
        if !transfers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Detecting \(transfers.count) transfer\(transfers.count == 1 ? "" : "s")…", systemImage: "arrow.up.arrow.down.circle")
                    .font(.caption.weight(.medium))
                ForEach(transfers) { transfer in
                    TransferCard(transfer: transfer)
                }
                if allTransfersFinished {
                    HStack {
                        Spacer()
                        Button("Done") {
                            appState.dismissAllFinishedTransfers(direction: nil)
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 8)
            .padding(16)
        }
    }
}

struct TransferCard: View {
    @EnvironmentObject private var appState: AppState
    let transfer: TransferProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: directionIcon)
                    .foregroundStyle(iconColor)
                Text(transfer.filename)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let clientIP = transfer.clientIP {
                Text("From \(clientIP)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            progressView

            timingView

            statusLabel

            if transfer.status == .inProgress {
                HStack {
                    Spacer()
                    Button("Cancel") {
                        Task { await appState.cancelTransfer(pid: transfer.pid) }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var progressView: some View {
        if transfer.status == .inProgress {
            if let fraction = transfer.fractionCompleted {
                ProgressView(value: fraction)
                Text("\(Int(fraction * 100))% — \(progressCaption)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Uploads never have a known total (the protocol doesn't
                // announce it to anything short of packet-level sniffing —
                // out of scope, see PROJECT.md/Help "Uploads"), so there's
                // no percentage to show — only an indeterminate spinner.
                // Without a filling bar to watch, the received-bytes count
                // is the only real signal of progress, so it's made
                // prominent (monospaced, larger, primary color) instead of
                // a quiet caption easy to miss next to a static spinner —
                // feedback from the user (2026-09-07): uploads "jump" to
                // 100% because there was nothing visible changing in
                // between.
                ProgressView()
                Text(progressCaption)
                    .font(.title3.monospacedDigit().weight(.semibold))
            }

            if let speed = transfer.speedBytesPerSecond {
                Text(speedCaption(speed))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var timingView: some View {
        if transfer.status == .inProgress {
            HStack(spacing: 4) {
                Text("Elapsed:")
                Text(transfer.startDate, style: .timer)
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let eta = transfer.estimatedSecondsRemaining {
                Text("Remaining: \(formattedDuration(eta))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Finished in \(formattedDuration(transfer.elapsedSeconds))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func speedCaption(_ bytesPerSecond: Double) -> String {
        let speedText = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file)
        return "Speed: \(speedText)/s"
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: max(0, seconds)) ?? "0:00"
    }

    private var progressCaption: String {
        let transferred = ByteCountFormatter.string(fromByteCount: transfer.transferredBytes, countStyle: .file)
        switch transfer.direction {
        case .upload:
            return "\(transferred) received"
        case .download:
            if let total = transfer.totalBytes {
                return "\(transferred) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
            }
            return "\(transferred) sent"
        case nil:
            return "Detecting…"
        }
    }

    private var directionIcon: String {
        switch transfer.direction {
        case .upload: return "arrow.up.circle"
        case .download: return "arrow.down.circle"
        case nil: return "arrow.up.arrow.down.circle"
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch transfer.status {
        case .inProgress:
            EmptyView()
        case .completed:
            Label("Transfer completed", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .cancelled:
            Label("Transfer cancelled", systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var iconColor: Color {
        switch transfer.status {
        case .inProgress: return .accentColor
        case .completed: return .green
        case .cancelled: return .secondary
        case .failed: return .red
        }
    }
}
