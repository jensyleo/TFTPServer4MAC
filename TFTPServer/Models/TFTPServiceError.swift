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
    case serverNotRunning
    case emptyQueueFolder
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
            return "The selected TFTP folder is not valid or not accessible."
        case .conflictingSystemService:
            return "macOS's built-in TFTP service is already loaded and must be stopped first."
        case .requiresUserApproval:
            return "Open System Settings → General → Login Items & Extensions and allow TFTP Server, then try again."
        case .firewallIssue:
            return "The firewall may be blocking incoming TFTP traffic."
        case .serverNotRunning:
            return "Start the TFTP server before starting a queue."
        case .emptyQueueFolder:
            return "The TFTP folder has no files to queue."
        case .unknown:
            return "An unknown error occurred."
        }
    }
}
