// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import XCTest
@testable import TFTPServer

final class QueueSessionTests: XCTestCase {
    func testNilForEmptyFileList() {
        XCTAssertNil(QueueSession(filenames: []))
    }

    func testNoUpperLimitOnFileCount() {
        let manyFiles = (1...137).map { "file\($0).bin" }
        let session = QueueSession(filenames: manyFiles)
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.totalBatches, 14)
    }

    func testBatchesOfTen() {
        let filenames = (1...25).map { "file\($0).bin" }
        guard let session = QueueSession(filenames: filenames) else {
            return XCTFail("Expected a session")
        }
        XCTAssertEqual(session.totalBatches, 3)
        XCTAssertEqual(session.batches[0].count, 10)
        XCTAssertEqual(session.batches[1].count, 10)
        XCTAssertEqual(session.batches[2].count, 5)
    }

    func testMarkingCompletedAdvancesCurrentBatch() {
        let filenames = (1...15).map { "file\($0).bin" }
        guard var session = QueueSession(filenames: filenames) else {
            return XCTFail("Expected a session")
        }
        XCTAssertEqual(session.currentBatchIndex, 0)

        for filename in session.batches[0] {
            session.markCompleted(filename: filename)
        }

        XCTAssertEqual(session.currentBatchIndex, 1)
        XCTAssertFalse(session.isComplete)
    }

    func testIgnoresFilesOutsideOriginalSnapshot() {
        guard var session = QueueSession(filenames: ["a.bin", "b.bin"]) else {
            return XCTFail("Expected a session")
        }
        session.markCompleted(filename: "not-in-the-queue.bin")
        XCTAssertEqual(session.overallCompletedCount, 0)
    }

    func testIsCompleteWhenAllFilesMarked() {
        guard var session = QueueSession(filenames: ["a.bin", "b.bin"]) else {
            return XCTFail("Expected a session")
        }
        session.markCompleted(filename: "a.bin")
        XCTAssertFalse(session.isComplete)
        session.markCompleted(filename: "b.bin")
        XCTAssertTrue(session.isComplete)
    }
}
