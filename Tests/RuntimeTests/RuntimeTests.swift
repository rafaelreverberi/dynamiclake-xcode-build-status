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
    func testIconRendererPreservesTransparencyAndBounds() throws {
        let image = NSImage(size:NSSize(width:80,height:40),flipped:false) { _ in
            NSColor.blue.setFill(); NSRect(x:0,y:0,width:80,height:40).fill(); return true
        }
        let png = try XCTUnwrap(XcodeAppIcon.render(image))
        XCTAssertLessThanOrEqual(png.count,Messages.maximumIconBytes)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data:png))
        XCTAssertEqual(bitmap.pixelsWide,128); XCTAssertEqual(bitmap.pixelsHigh,128)
        XCTAssertTrue(bitmap.hasAlpha)
        XCTAssertEqual(bitmap.colorAt(x:0,y:0)?.alphaComponent,0)
        XCTAssertEqual(bitmap.colorAt(x:64,y:64)?.alphaComponent,1)
        XCTAssertNil(XcodeAppIcon.render(NSImage(size:.zero)))
    }
    func testInstalledXcodeIconWhenAvailable() throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.dt.Xcode") != nil else {
            throw XCTSkip("Xcode app not installed")
        }
        let cache = XcodeAppIcon()
        let png = try XCTUnwrap(cache.png())
        XCTAssertLessThanOrEqual(png.count,Messages.maximumIconBytes)
        XCTAssertEqual(cache.png(),png)
        XCTAssertNotEqual(cache.signature,"hammer")
        let message = Messages.activity(id:"probe",create:true,iconPNG:png)
        XCTAssertLessThan(try Messages.frame(message).count,64_004)
        print("Local Xcode app icon: \(png.count) PNG bytes, \(NSBitmapImageRep(data:png)!.pixelsWide) px")
        cache.invalidate(); XCTAssertEqual(cache.signature,"hammer")
    }
    func testBoundedReadRejectsOversizedFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        try Data(repeating:65,count:101).write(to:url)
        XCTAssertThrowsError(try boundedRead(url,limit:100))
        XCTAssertEqual(try boundedRead(url,limit:101).count,101)
    }
}
