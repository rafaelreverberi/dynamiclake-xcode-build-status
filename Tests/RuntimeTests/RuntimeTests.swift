import XCTest
import Foundation
@testable import XcodeBuildStatus

final class RuntimeTests: XCTestCase {
    func testSettingsObserverHandlesAtomicReplacementAndInPlaceWrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let file = root.appendingPathComponent("settings.json")
        try Data("first".utf8).write(to:file)
        let atomic = expectation(description:"atomic settings replacement")
        let inplace = expectation(description:"in-place settings write")
        var sawAtomic = false; var sawInplace = false
        let watcher = SettingsEvents(url:file) {
            let contents = try? String(contentsOf:file)
            if contents == "second" && !sawAtomic { sawAtomic = true; atomic.fulfill() }
            if contents == "third" && !sawInplace { sawInplace = true; inplace.fulfill() }
        }
        try Data("second".utf8).write(to:file,options:.atomic)
        wait(for:[atomic],timeout:3)
        try Data("third".utf8).write(to:file)
        wait(for:[inplace],timeout:3)
        withExtendedLifetime(watcher) {}
    }
    func testJournalIdentityRejectsStaleSymlinksAndTracksReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let journal = root.appendingPathComponent("build.db-journal")
        XCTAssertNil(journalIdentity(journal))
        try Data("journal".utf8).write(to:journal)
        let before = journalIdentity(journal); XCTAssertNotNil(before)
        XCTAssertFalse(databaseHasWriter(journal))
        try Data("new".utf8).write(to:journal,options:.atomic)
        XCTAssertNotEqual(before,journalIdentity(journal))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:journal)
        XCTAssertNil(journalIdentity(link))
    }
    func testBoundedReadRejectsOversizedFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        try Data(repeating:65,count:101).write(to:url)
        XCTAssertThrowsError(try boundedRead(url,limit:100))
        XCTAssertEqual(try boundedRead(url,limit:101).count,101)
    }
}
