// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import XCTest
@testable import TFTPServer

final class TransferActivityParserTests: XCTestCase {
    func testParsesFilenameLine() {
        let event = TransferActivityParser.parse(line: "tftpd[38082:17258d] Filename: 'bigfile.bin'")
        guard case .filenameDetected(let filename) = event else {
            return XCTFail("Expected .filenameDetected, got \(String(describing: event))")
        }
        XCTAssertEqual(filename, "bigfile.bin")
    }

    func testIgnoresUnrelatedLines() {
        XCTAssertNil(TransferActivityParser.parse(line: "tftpd[38082:17258d] Mode: 'octet'"))
        XCTAssertNil(TransferActivityParser.parse(line: "Some unrelated log line"))
    }
}
