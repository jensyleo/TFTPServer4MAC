// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

struct TFTPConfiguration: Equatable, Sendable {
    var rootDirectory: URL
    var allowDownloads: Bool
    var allowUploads: Bool
    var allowCreateFiles: Bool
    var startAtLogin: Bool
    var loggingEnabled: Bool

    static var conservativeDefault: TFTPConfiguration {
        let defaultRoot = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("TFTP", isDirectory: true)
        return TFTPConfiguration(
            rootDirectory: defaultRoot,
            allowDownloads: true,
            allowUploads: false,
            allowCreateFiles: false,
            startAtLogin: false,
            loggingEnabled: true
        )
    }
}
