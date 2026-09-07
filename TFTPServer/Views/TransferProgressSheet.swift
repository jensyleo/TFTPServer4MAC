// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import SwiftUI

struct TransferProgressSheet: View {
    @EnvironmentObject private var appState: AppState
    let transfer: TransferProgress

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: directionIcon)
                .font(.system(size: 36))
                .foregroundStyle(iconColor)

            Text(transfer.filename)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            progressView

            timingView

            if let session = appState.queueSession {
                Divider()
                queueProgressView(session)
            }

            statusLabel

            HStack {
                if transfer.status == .inProgress {
                    Button("Cancel") {
                        Task { await appState.cancelActiveTransfer() }
                    }
                } else {
                    Button("Done") {
                        appState.dismissActiveTransfer()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 320)
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
                ProgressView()
                Text(progressCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var timingView: some View {
        VStack(spacing: 2) {
            if transfer.status == .inProgress {
                HStack(spacing: 4) {
                    Text("Elapsed:")
                    Text(transfer.startDate, style: .timer)
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Finished in \(formattedDuration(transfer.elapsedSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let speed = transfer.speedBytesPerSecond, transfer.status == .inProgress {
                Text(speedCaption(speed))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func speedCaption(_ bytesPerSecond: Double) -> String {
        let speedText = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file)
        var caption = "Speed: \(speedText)/s"
        if let eta = transfer.estimatedSecondsRemaining {
            caption += " — Remaining: \(formattedDuration(eta))"
        }
        return caption
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

    @ViewBuilder
    private func queueProgressView(_ session: QueueSession) -> some View {
        VStack(spacing: 6) {
            HStack {
                Label("Batch \(session.currentBatchIndex + 1) of \(session.totalBatches)", systemImage: "tray.full")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(session.overallCompletedCount) of \(session.totalFiles) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: session.currentBatchFraction)
            HStack {
                Text(session.isComplete
                     ? "All files in this batch have been requested"
                     : "Waiting for the device to request the rest")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Stop Queue") {
                    appState.stopQueueSession()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
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
                .foregroundStyle(.green)
        case .cancelled:
            Label("Transfer cancelled", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
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
