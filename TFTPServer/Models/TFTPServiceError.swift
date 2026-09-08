// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

enum TFTPServiceError: Error, Equatable {
    case tftpdNotFound
    case configurationInvalid
    case permissionDenied
    case serviceStartFailed
    case serviceStopFailed
    case rootDirectoryInvalid
    case conflictingSystemService
    case requiresUserApproval
    case firewallIssue
    case permissionsRepairFailed
    case permissionsMustBeFixedFirst
    case unknown

    var userFacingMessage: String {
        switch self {
        case .tftpdNotFound:
            return "The macOS TFTP service (tftpd) was not found on this system."
        case .configurationInvalid:
            return "The current TFTP configuration is invalid."
        case .permissionDenied:
            return "Permission was denied for this operation."
        case .serviceStartFailed:
            return "The TFTP service could not be started."
        case .serviceStopFailed:
            return "The TFTP service could not be stopped."
        case .rootDirectoryInvalid:
            return "That folder can't be used as the TFTP folder. It must be a real, readable folder of your own — not the entire disk (\"/\"), a top-level folder like /Users or /Applications, a system folder, or a path containing \"..\"."
        case .conflictingSystemService:
            return "macOS's built-in TFTP service is already loaded and must be stopped first."
        case .requiresUserApproval:
            return "Open System Settings → General → Login Items & Extensions and allow TFTP Server, then try again."
        case .firewallIssue:
            return "The firewall may be blocking incoming TFTP traffic."
        case .permissionsRepairFailed:
            return "Couldn't fix this folder's permissions — it may belong to a different user. Try fixing it from Terminal or Finder's Get Info panel."
        case .permissionsMustBeFixedFirst:
            return "The server can't start until the permission issues shown below are fixed. Use the \"Fix\" button next to whichever one says \"Fix needed\", then try Start again."
        case .unknown:
            return "An unknown error occurred."
        }
    }
}
