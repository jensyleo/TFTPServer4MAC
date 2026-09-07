// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Valida rutas usadas como TFTP root. Rechaza traversal, rutas del sistema y
/// destinos que no sean directorios reales (PROJECT.md, sección 34).
enum PathValidator {
    private static let disallowedPrefixes = [
        "/etc",
        "/private/etc",
        "/System",
        "/bin",
        "/sbin",
        "/usr/bin",
        "/usr/sbin",
        "/usr/libexec"
    ]

    static func isValidRoot(_ url: URL, fileManager: FileManager = .default) -> Bool {
        let standardizedPath = url.standardizedFileURL.path

        guard !standardizedPath.contains("..") else {
            return false
        }

        guard disallowedPrefixes.allSatisfy({ !standardizedPath.hasPrefix($0) }) else {
            return false
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        return fileManager.isReadableFile(atPath: standardizedPath)
    }
}
