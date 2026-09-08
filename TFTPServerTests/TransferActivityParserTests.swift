// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import XCTest
@testable import TFTPServer

final class TransferActivityParserTests: XCTestCase {
    func testParsesFilenameLineWithPID() {
        let event = TransferActivityParser.parse(line: "2026-09-07 07:15:00.000 I  tftpd[38082:17258d] Filename: 'bigfile.bin'")
        guard case .filenameDetected(let pid, let filename) = event else {
            return XCTFail("Expected .filenameDetected, got \(String(describing: event))")
        }
        XCTAssertEqual(pid, 38082)
        XCTAssertEqual(filename, "bigfile.bin")
    }

    func testDistinguishesConcurrentPIDs() {
        let eventA = TransferActivityParser.parse(line: "tftpd[100:1] Filename: 'a.bin'")
        let eventB = TransferActivityParser.parse(line: "tftpd[200:1] Filename: 'b.bin'")
        guard case .filenameDetected(let pidA, _) = eventA, case .filenameDetected(let pidB, _) = eventB else {
            return XCTFail("Expected both to parse")
        }
        XCTAssertNotEqual(pidA, pidB)
    }

    func testIgnoresUnrelatedLines() {
        XCTAssertNil(TransferActivityParser.parse(line: "tftpd[38082:17258d] Mode: 'octet'"))
        XCTAssertNil(TransferActivityParser.parse(line: "Some unrelated log line"))
    }
}
