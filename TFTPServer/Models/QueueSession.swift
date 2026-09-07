// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Seguimiento de una "cola" de transferencias esperadas contra la carpeta
/// TFTP actual — ver PROJECT.md sección 49.2 para la decisión de diseño
/// completa y sus límites.
///
/// La app es un servidor pasivo: no elige qué archivo pide un dispositivo ni
/// en qué orden. `QueueSession` solo cuenta, de los archivos que había en la
/// carpeta al momento de iniciar la cola, cuáles ya fueron efectivamente
/// transferidos al menos una vez en esta sesión — no fuerza nada del lado
/// del protocolo.
struct QueueSession: Equatable {
    /// Decisión (2026-09-05): no hay tope al tamaño de la carpeta ni al
    /// número de archivos en la cola — el sistema operativo ya limita eso, y
    /// un límite artificial rompería casos reales (PXE boot con cientos de
    /// archivos, repositorios de firmware). Las tandas de 10 son solo para
    /// que la barra de progreso sea legible, no una restricción funcional:
    /// con 137 archivos hay 14 tandas, sin más.
    static let batchSize = 10

    let allFilenames: [String]
    private(set) var completedFilenames: Set<String> = []

    init?(filenames: [String]) {
        guard !filenames.isEmpty else { return nil }
        self.allFilenames = filenames
    }

    var totalFiles: Int { allFilenames.count }
    var totalBatches: Int { Int(ceil(Double(totalFiles) / Double(Self.batchSize))) }

    var batches: [[String]] {
        stride(from: 0, to: allFilenames.count, by: Self.batchSize).map {
            Array(allFilenames[$0..<min($0 + Self.batchSize, allFilenames.count)])
        }
    }

    /// Índice de la tanda actual: la primera que todavía tiene al menos un
    /// archivo pendiente. Si todas están completas, apunta a la última.
    var currentBatchIndex: Int {
        let allBatches = batches
        for (index, batch) in allBatches.enumerated() {
            if !batch.allSatisfy({ completedFilenames.contains($0) }) {
                return index
            }
        }
        return max(0, allBatches.count - 1)
    }

    var currentBatch: [String] {
        let allBatches = batches
        guard !allBatches.isEmpty else { return [] }
        return allBatches[currentBatchIndex]
    }

    var currentBatchCompletedCount: Int {
        currentBatch.filter { completedFilenames.contains($0) }.count
    }

    var currentBatchFraction: Double {
        guard !currentBatch.isEmpty else { return 0 }
        return Double(currentBatchCompletedCount) / Double(currentBatch.count)
    }

    var overallCompletedCount: Int { completedFilenames.count }
    var overallFraction: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(overallCompletedCount) / Double(totalFiles)
    }

    var isComplete: Bool { completedFilenames.count >= allFilenames.count }

    /// Marca un archivo como transferido. No hace nada si el archivo no
    /// pertenece al lote original (p. ej. un archivo nuevo creado después de
    /// iniciar la cola) — deliberado: la cola es un snapshot fijo del
    /// momento en que se inició, no se recalcula sola.
    mutating func markCompleted(filename: String) {
        guard allFilenames.contains(filename) else { return }
        completedFilenames.insert(filename)
    }
}
