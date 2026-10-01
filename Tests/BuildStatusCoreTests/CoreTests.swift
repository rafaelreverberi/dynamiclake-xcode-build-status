import XCTest
@testable import BuildStatusCore

final class CoreTests: XCTestCase {
    func testSettingsDefaultsAndValidation() {
        XCTAssertEqual(Settings().success, 3); XCTAssertEqual(Settings().failure, 5)
        for (input, expected): (Any, Double) in [(0,1), (20,10), (4.6,5), (true,3), ("8",3), (Double.nan,3)] {
            XCTAssertEqual(Settings.duration(input, fallback: 3), expected)
        }
    }
    func testSettingsEnvelopeAndLiveValues() throws {
        func data(_ id: String, _ values: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["schemaVersion":1,"identifier":id,"values":values])
        }
        XCTAssertNil(Settings.decode(try data("wrong", [:])))
        XCTAssertNil(Settings.decode(Data("{}".utf8)))
        let first = Settings.decode(try data(pluginIdentifier,["successDisplaySeconds":1,"failureDisplaySeconds":10]))!
        let second = Settings.decode(try data(pluginIdentifier,["successDisplaySeconds":7]))!
        XCTAssertEqual(first.success,1); XCTAssertEqual(first.failure,10)
        XCTAssertEqual(second.success,7); XCTAssertEqual(second.failure,5)
    }
    func testEWMAAndUnreliableHistory() {
        var history = DurationHistory(duration:10, now:0)
        history.learn(20,now:1)
        XCTAssertEqual(history.mean,13,accuracy:0.0001)
        XCTAssertEqual(history.deviation,3,accuracy:0.0001)
        XCTAssertEqual(history.count,2)
        history.learn(.nan,now:2); XCTAssertEqual(history.count,2)
        history.learn(100,now:2); XCTAssertNil(history.estimate)
    }
    func testHistoryBucketsContainNoPath() {
        let key = historyKey("/Users/private/SecretProject|Debug")
        XCTAssertEqual(key.count,64); XCTAssertFalse(key.contains("SecretProject"))
        XCTAssertNotEqual(key,historyKey("/Users/private/SecretProject|Release"))
    }
    func testProgressIndeterminateFirstBuildAndOverrun() {
        var first = ActiveBuild(started:10,bucket:"a",estimate:nil)
        XCTAssertNil(first.value(now:11))
        var active = ActiveBuild(started:0,bucket:"a",estimate:10)
        XCTAssertEqual(active.value(now:12),0.95)
        XCTAssertNil(active.value(now:26))
    }
    func testProgressRangeMonotonicAndCapped() {
        var active = ActiveBuild(started:100,bucket:"a",estimate:100)
        var previous = 0.0
        for now in stride(from:90.0,through:300,by:0.3) {
            let value = active.value(now:now)!
            XCTAssertGreaterThanOrEqual(value,previous); XCTAssertGreaterThanOrEqual(value,0)
            XCTAssertLessThanOrEqual(value,0.95); previous = value
        }
        XCTAssertEqual(active.value(now:110),previous) // clock rollback cannot reverse progress
    }
    func record(start: Double = 100, end: Double = 110, result: ResultState = .success, id: String = "one") -> BuildRecord {
        BuildRecord(id:id,start:start,end:end,result:result,filename:"test.xcactivitylog",scheme:"test")
    }
    func testSuccessAndExactCompletionDeadline() {
        var m = BuildMachine(launched:90)
        XCTAssertTrue(m.begin(now:100,bucket:"a",estimate:10))
        XCTAssertTrue(m.finish(record(),now:110))
        XCTAssertNil(m.active); XCTAssertEqual(m.completed,.success)
        XCTAssertFalse(m.expire(now:112.99,settings:Settings()))
        XCTAssertTrue(m.expire(now:113,settings:Settings())); XCTAssertNil(m.completed)
    }
    func testFailureDynamicDurationAndCleanup() {
        var m = BuildMachine(launched:90); _ = m.begin(now:100,bucket:"a",estimate:nil)
        XCTAssertTrue(m.finish(record(result:.failed),now:110,error:"Cannot find x"))
        XCTAssertEqual(m.completed,.failed); XCTAssertEqual(m.detail,"Cannot find x")
        XCTAssertFalse(m.finish(record(result:.failed),now:114))
        XCTAssertEqual(m.completedAt,110)
        let changed = Settings(values:["failureDisplaySeconds":2])
        XCTAssertEqual(m.dismissalDeadline(settings:changed),112)
        XCTAssertFalse(m.expire(now:111.99,settings:changed))
        XCTAssertTrue(m.expire(now:112,settings:changed))
        XCTAssertNil(m.completed); XCTAssertNil(m.completedAt); XCTAssertEqual(m.detail,"")
    }
    func testNewBuildReplacesFailure() {
        var m = BuildMachine(launched:90); _ = m.begin(now:100,bucket:"a",estimate:nil)
        _ = m.finish(record(result:.failed),now:110,error:"Cannot find x")
        XCTAssertTrue(m.begin(now:111,bucket:"b",estimate:10))
        XCTAssertNotNil(m.active); XCTAssertNil(m.completedAt); XCTAssertNil(m.completed)
        XCTAssertEqual(m.detail,"")
        XCTAssertNil(m.dismissalDeadline(settings:Settings()))
        XCTAssertFalse(m.expire(now:2000,settings:Settings()))
    }
    func testFailurePayloadKeepsDiagnosticWithoutAutoPresentation() {
        let message = Messages.activity(id:"a",create:false,result:.failed,detail:"Cannot find x",features:[])
        XCTAssertEqual(surfaces(message)["sneakPeek"]?["center"]?["text"] as? String,"Build Failed — Cannot find x")
        XCTAssertEqual(surfaces(message)["sneakPeek"]?["rightSlot"]?["systemImage"] as? String,"xmark")
        XCTAssertNil(message["presentSneakPeek"])
    }
    func testIconSettingDefaultsAndInvalidValues() {
        XCTAssertEqual(Settings().iconStyle,.hammer)
        XCTAssertEqual(Settings(values:["iconStyle":"Xcode App Icon"]).iconStyle,.xcode)
        for invalid: Any in ["unknown",true,42] {
            XCTAssertEqual(Settings(values:["iconStyle":invalid]).iconStyle,.hammer)
        }
    }
    func testSuppliedPNGUsedInBothSlotsAndFrameBudget() throws {
        var png = Data([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a])
        png.append(Data(repeating:0,count:Messages.maximumIconBytes-png.count))
        let message = Messages.activity(id:"a",create:true,result:.failed,detail:String(repeating:"x",count:160),iconStyle:.xcode,iconPNG:png)
        let image = surfaces(message)["compactLiveActivity"]!["leftSlot"]!
        XCTAssertEqual(image["source"] as? String,"inlineData")
        XCTAssertEqual(image["mimeType"] as? String,"image/png")
        XCTAssertEqual(Data(base64Encoded:image["base64Data"] as! String),png)
        XCTAssertNil(image["tint"])
        XCTAssertEqual(surfaces(message)["sneakPeek"]?["leftSlot"]?["base64Data"] as? String,image["base64Data"] as? String)
        XCTAssertEqual(surfaces(message)["compactLiveActivity"]?["rightSlot"]?["base64Data"] as? String,image["base64Data"] as? String)
        XCTAssertLessThan(try Messages.frame(message).count,64_004)
        XCTAssertEqual(Messages.leftImage(style:.hammer,iconPNG:png)["systemImage"] as? String,"hammer.fill")
        png.append(0)
        XCTAssertEqual(Messages.leftImage(style:.xcode,iconPNG:png)["source"] as? String,"sfSymbol")
        XCTAssertEqual(Messages.leftImage(style:.xcode)["source"] as? String,"sfSymbol")
        XCTAssertEqual(Messages.leftImage(style:.xcode,iconPNG:Data("bad".utf8))["source"] as? String,"sfSymbol")
    }
    func testRapidBuildPrecedesPreviousCompletion() {
        var m = BuildMachine(launched:90); _ = m.begin(now:100,bucket:"a",estimate:nil)
        _ = m.finish(record(),now:110)
        XCTAssertTrue(m.begin(now:111,bucket:"b",estimate:nil))
        XCTAssertNil(m.completedAt); XCTAssertNil(m.completed)
        XCTAssertFalse(m.expire(now:200,settings:Settings())); XCTAssertNotNil(m.active)
    }
    func testStaleAndDuplicateFiltering() {
        var m = BuildMachine(launched:90); _ = m.begin(now:100,bucket:"a",estimate:nil)
        XCTAssertFalse(m.begin(now:102,bucket:"b",estimate:nil))
        XCTAssertFalse(m.finish(record(start:89),now:110))
        XCTAssertFalse(m.finish(record(start:94),now:110))
        XCTAssertFalse(m.finish(record(start:110),now:120))
        XCTAssertTrue(m.finish(record(),now:110))
        XCTAssertFalse(m.finish(record(),now:111))
    }
    func testCancellationAndUnknownDismissWithoutSuccess() {
        for result in [ResultState.cancelled,.unknown] {
            var m = BuildMachine(launched:90); _ = m.begin(now:100,bucket:"a",estimate:nil)
            XCTAssertTrue(m.finish(record(result:result),now:110))
            XCTAssertNil(m.active); XCTAssertNil(m.completed); XCTAssertNil(m.completedAt)
        }
    }
    func testPrivacySanitization() {
        XCTAssertFalse(sanitizeError("Error in /Users/private/project/main.swift:42").contains("/Users"))
        XCTAssertFalse(sanitizeError("file:///Volumes/Private/path.swift").contains("/Volumes"))
        XCTAssertFalse(sanitizeError("at ~/Projects/secret.swift").contains("Projects"))
        XCTAssertEqual(sanitizeError("API_KEY='abc'"),"")
        XCTAssertEqual(sanitizeError("password is invalid"),"")
        XCTAssertEqual(sanitizeError("Hello\nworld\u{202e}"),"Hello world")
        XCTAssertEqual(sanitizeError(String(repeating:"x",count:300)).count,160)
    }
    func surfaces(_ message: [String: Any]) -> [String: [String: [String: Any]]] {
        message["surfaces"] as! [String: [String: [String: Any]]]
    }
    func testMessagesUseDocumentedNativeComponents() {
        let message = Messages.activity(id:"a",create:true)
        XCTAssertEqual(message["size"] as? String,"small"); XCTAssertEqual(message["priority"] as? String,"normal")
        let s = surfaces(message)
        XCTAssertEqual(s["compactLiveActivity"]?["leftSlot"]?["systemImage"] as? String,"hammer.fill")
        XCTAssertEqual(s["compactLiveActivity"]?["rightSlot"]?["type"] as? String,"progress")
        XCTAssertNil(s["compactLiveActivity"]?["rightSlot"]?["value"])
        XCTAssertNil(message["presentSneakPeek"])
    }
    func testCompletionFeatureDetectionAndFailureDetail() throws {
        let features = Messages.features("numericText, presentSneakPeek")
        XCTAssertTrue(features.contains("presentSneakPeek")); XCTAssertTrue(Messages.features(nil).isEmpty)
        for result in [ResultState.success,.failed] {
            let m = Messages.activity(id:"a",create:false,result:result,detail:"Cannot find x /Users/private/src",duration:10,features:features)
            XCTAssertEqual(m["presentSneakPeek"] as? Double,10)
            XCTAssertEqual(surfaces(m)["compactLiveActivity"]?["rightSlot"]?["systemImage"] as? String,"hammer.fill")
            for surface in ["sneakPeek"] {
                let right = surfaces(m)[surface]!["rightSlot"]!
                XCTAssertEqual(right["type"] as? String,"image")
                XCTAssertEqual(right["source"] as? String,"sfSymbol")
                XCTAssertEqual(right["systemImage"] as? String,result == .success ? "checkmark" : "xmark")
                XCTAssertEqual(right["tint"] as? String,result == .success ? "green" : "red")
                XCTAssertNil(right["status"])
            }
            XCTAssertFalse(String(data:try JSONSerialization.data(withJSONObject:m),encoding:.utf8)!.contains("/Users"))
            XCTAssertNil(Messages.activity(id:"a",create:false,result:result)["presentSneakPeek"])
        }
        XCTAssertNil(Messages.activity(id:"a",create:false,value:0.2,features:features)["presentSneakPeek"])
    }
    func testFramesAndProgressClamping() throws {
        let message = Messages.activity(id:"a",create:true,value:10)
        XCTAssertEqual(surfaces(message)["compactLiveActivity"]?["rightSlot"]?["value"] as? Double,0.95)
        let frame = try Messages.frame(message)
        XCTAssertEqual(frame.prefix(4).reduce(0) { $0*256+Int($1) },frame.count-4)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with:frame.dropFirst(4)))
        XCTAssertThrowsError(try Messages.frame(["text":String(repeating:"x",count:64_001)]))
        XCTAssertEqual(Messages.dismiss(id:"a")["type"] as? String,"dismiss")
    }
    func testManifestParserRealShapeAndUnsafePaths() throws {
        let id = "12345678-1234-1234-1234-123456789012"
        var entry: [String: Any] = ["className":"IDEActivityLogSection","domainType":"Xcode.IDEActivityLogDomainType.BuildLog",
          "uniqueIdentifier":id,"fileName":id+".xcactivitylog","timeStartedRecording":100.0,"timeStoppedRecording":110.0,
          "primaryObservable":["highLevelStatus":"W","totalNumberOfErrors":0]]
        func parse(_ e: [String: Any]) throws -> [BuildRecord] {
            try ManifestParser.parse(PropertyListSerialization.data(fromPropertyList:["logs":[id:e]],format:.binary,options:0))
        }
        XCTAssertEqual(try parse(entry).first?.result,.success)
        entry["primaryObservable"] = ["highLevelStatus":"E","totalNumberOfErrors":1]
        XCTAssertEqual(try parse(entry).first?.result,.failed)
        entry["primaryObservable"] = ["highLevelStatus":"?","totalNumberOfErrors":0]
        XCTAssertEqual(try parse(entry).first?.result,.unknown)
        entry["fileName"] = "../../private.xcactivitylog"; XCTAssertTrue(try parse(entry).isEmpty)
        entry["fileName"] = id+".xcactivitylog"; entry["className"] = "IDECommandLineBuildLog"
        XCTAssertTrue(try parse(entry).isEmpty)
        XCTAssertThrowsError(try ManifestParser.parse(Data("bad".utf8)))
    }
    func requestData(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var d: [String: Any] = ["buildCommand":["command":"build"],"enableIndexBuildArena":false,"useDryRun":false,
            "containerPath":"/private/project", "parameters":["action":"build","configurationName":"Debug","overrides":[:]],
            "configuredTargets":[["guid":"a"]]]
        mutate(&d); return try JSONSerialization.data(withJSONObject:d)
    }
    func testBuildRequestExcludesIndexDryRunAndCLI() throws {
        XCTAssertNotNil(BuildRequest.parse(try requestData()))
        XCTAssertNil(BuildRequest.parse(try requestData { $0["enableIndexBuildArena"] = true }))
        XCTAssertNil(BuildRequest.parse(try requestData { $0["useDryRun"] = true }))
        XCTAssertNil(BuildRequest.parse(try requestData { $0["parameters"] = ["action":"build","configurationName":"Debug","overrides":["commandLine":[:]]] }))
        XCTAssertNil(BuildRequest.parse(try requestData { $0["parameters"] = ["action":"indexbuild","configurationName":"Debug","overrides":[:]] }))
        XCTAssertNil(BuildRequest.parse(try requestData { $0["parameters"] = ["action":"build","configurationName":"Debug","overrides":["synthesized":["table":["ENABLE_PREVIEWS":"YES"]]]] }))
    }
    func slfString(_ s: String) -> String { "\(s.utf8.count)\"\(s)" }
    func slf(cancelled: Bool = false, failed: Bool = false, error: String = "") -> Data {
        let id = "12345678-1234-1234-1234-123456789012"
        let diagnostic = error.isEmpty ? "" : "31%IDEDiagnosticActivityLogMessage1@" + slfString(error) + "-1#0#0#-2#"
        // Synthetic token stream tests only the intentionally narrow diagnostic and root trailer fields.
        return Data(("SLF013#" + diagnostic + "\(failed ? 1:0)#\(cancelled ? 1:0)#0#0#---" + slfString(id) + slfString("Result") + "-0(0#").utf8)
    }
    func testSLFSuccessFailureCancellationAndUTF8() throws {
        let id = "12345678-1234-1234-1234-123456789012"
        XCTAssertFalse(try ActivityLog.parse(slf(),rootID:id).cancelled)
        let failure = try ActivityLog.parse(slf(failed:true,error:"Cannot find 'ü' in scope"),rootID:id)
        XCTAssertFalse(failure.cancelled); XCTAssertEqual(failure.error,"Cannot find 'ü' in scope")
        XCTAssertTrue(try ActivityLog.parse(slf(cancelled:true,failed:true),rootID:id).cancelled)
    }
    func testSLFRejectsTruncationUnknownVersionsAndClassReferences() {
        let id = "12345678-1234-1234-1234-123456789012"
        for d in [Data(),Data("SLF099#1@".utf8),Data("SLF013#2@".utf8),Data("SLF013#900\"x".utf8),slf().dropLast(70)] {
            XCTAssertThrowsError(try ActivityLog.parse(d,rootID:id))
        }
    }
}
