// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

struct FileEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let modificationDate: Date?
    let sizeInBytes: Int64?

    var formattedSize: String {
        guard let sizeInBytes else { return "--" }
        return ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }

    var formattedDate: String {
        guard let modificationDate else { return "--" }
        return modificationDate.formatted(date: .abbreviated, time: .shortened)
    }
}
