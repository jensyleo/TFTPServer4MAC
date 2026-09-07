// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import XCTest
@testable import TFTPServer

final class SystemDetectorTests: XCTestCase {
    func testDetectsTftpdOnThisMachine() {
        // Confirmado en Fase 0 (SystemCompatibilityReport.md): tftpd y tftp
        // existen en macOS Tahoe 26.6.2 arm64.
        let capabilities = SystemDetector().detectCapabilities()
        XCTAssertTrue(capabilities.tftpdAvailable)
        XCTAssertTrue(capabilities.tftpClientAvailable)
        XCTAssertTrue(capabilities.launchdAvailable)
    }
}
