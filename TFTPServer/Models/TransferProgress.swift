// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

struct TransferProgress: Equatable, Identifiable {
    /// El PID del proceso `tftpd` de esta transferencia, no el nombre de
    /// archivo — con transferencias simultáneas reales (2026-09-07), dos
    /// clientes distintos podrían, en teoría, pedir el mismo archivo a la
    /// vez, y cada uno es un proceso y una identidad distintos.
    var id: Int32 { pid }
    let pid: Int32

    enum Status: Equatable {
        case inProgress
        case completed
        case cancelled
        case failed(String)
    }

    var filename: String
    var startDate: Date
    var endDate: Date?
    /// `nil` mientras se determina (los primeros ~150-450ms tras detectar la
    /// transferencia): tftpd no distingue RRQ/WRQ en su log, así que la
    /// dirección se infiere comparando bytes enviados vs. recibidos por el
    /// proceso (ver AppState.trackActiveTransfer / NetworkByteMonitor).
    var direction: TransferDirection?
    /// Conocido de inmediato para descargas (el archivo ya existe en el TFTP
    /// root, completo). Para subidas no hay forma fiable de conocer el total
    /// sin que el cliente negocie `tsize` (raro en la práctica) — ver
    /// PROJECT.md sección 49.
    var totalBytes: Int64?
    /// Bytes reales transferidos hasta ahora, leídos de `nettop` (ver
    /// NetworkByteMonitor) — no una estimación.
    var transferredBytes: Int64
    /// Bytes/segundo, calculado en `AppState` a partir de dos muestras
    /// consecutivas de `nettop`. `nil` hasta la segunda muestra.
    var speedBytesPerSecond: Double?
    var status: Status
    /// La IP de origen real del datagrama inicial (RRQ/WRQ) — solo se
    /// conoce si "Show client IP" está activo (ver `ClientIPCaptureService`);
    /// `nil` en caso contrario o mientras aún no se correlaciona.
    var clientIP: String?

    var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1.0, Double(transferredBytes) / Double(totalBytes))
    }

    /// Solo tiene sentido para descargas (total conocido) con velocidad > 0.
    var estimatedSecondsRemaining: Double? {
        guard let totalBytes, let speedBytesPerSecond, speedBytesPerSecond > 0 else { return nil }
        let remaining = totalBytes - transferredBytes
        guard remaining > 0 else { return nil }
        return Double(remaining) / speedBytesPerSecond
    }

    var elapsedSeconds: TimeInterval {
        (endDate ?? Date()).timeIntervalSince(startDate)
    }
}
