import XCTest
import Foundation
import AppKit
import BuildStatusCore
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
    func testShippingIconPayloadUsesActualDecodableArtwork() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let executable = root.appendingPathComponent("XcodeBuildStatus.dynamiclakeplugin/xcode-build-status")
        let png = try XCTUnwrap(packagedIcon(executableURL:executable))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data:png))
        XCTAssertEqual(bitmap.pixelsWide,128); XCTAssertEqual(bitmap.pixelsHigh,128)
        XCTAssertTrue(bitmap.hasAlpha)
        let message = Messages.activity(id:"probe",create:true,result:.failed,detail:"Sample compiler error",iconStyle:.xcode,iconPNG:png)
        let surfaces = message["surfaces"] as! [String:[String:[String:Any]]]
        let image = surfaces["compactLiveActivity"]!["leftSlot"]!
        XCTAssertEqual(image["source"] as? String,"inlineData")
        XCTAssertEqual(image["mimeType"] as? String,"image/png")
        XCTAssertEqual(Data(base64Encoded:image["base64Data"] as! String),png)
        let frame = try Messages.frame(message)
        XCTAssertLessThan(frame.count,64_004)
        print("Actual supplied icon: \(png.count) PNG bytes; framed message: \(frame.count) bytes")
    }
    func testPackagedIconResolvesAlongsideExecutableAndRejectsBadFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let executable = root.appendingPathComponent("xcode-build-status")
        let icon = root.appendingPathComponent("xcode-icon.png")
        XCTAssertNil(packagedIcon(executableURL:executable))
        let png = Data([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a])
        try png.write(to:icon)
        XCTAssertEqual(packagedIcon(executableURL:executable),png)
        let link = root.appendingPathComponent("linked-executable")
        try Data().write(to:executable)
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:executable)
        XCTAssertEqual(packagedIcon(executableURL:link),png)
        try Data("invalid".utf8).write(to:icon)
        XCTAssertNil(packagedIcon(executableURL:executable))
        try Data(repeating:0,count:Messages.maximumIconBytes+1).write(to:icon)
        XCTAssertNil(packagedIcon(executableURL:executable))
    }
    func testBoundedReadRejectsOversizedFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        try Data(repeating:65,count:101).write(to:url)
        XCTAssertThrowsError(try boundedRead(url,limit:100))
        XCTAssertEqual(try boundedRead(url,limit:101).count,101)
    }
}
