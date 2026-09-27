import AppKit
import XCTest
@testable import Geist

final class InstallationTests: XCTestCase {
    func testVersionComparisonAndInvalidVersions() {
        XCTAssertLessThan(AppVersion("0.5.9")!, AppVersion("0.10.0")!)
        XCTAssertLessThan(AppVersion("0.9.9")!, AppVersion("1.0.0")!)
        for value in ["", "0.5", "0.5.3-dev", "1..3", "-1.2.3", "9999999999999999999999.0.0"] {
            XCTAssertNil(AppVersion(value), value)
        }
    }
    func testWindowFitsLaptopAndDoesNotGrowOnLargeMonitor() {
        XCTAssertEqual(DesktopPolicy.initialSize(visible: .init(width: 2560, height: 1400)), .init(width: 780, height: 620))
        let laptop = DesktopPolicy.initialSize(visible: .init(width: 1280, height: 720))
        XCTAssertLessThanOrEqual(laptop.width, 780)
        XCTAssertLessThan(laptop.height, 580)
    }
    func testSignedCandidateReplacesOldBundle() throws {
        guard let runtime = ProcessInfo.processInfo.environment["GEIST_DESKTOP_RUNTIME"] else { throw XCTSkip("Build the candidate bundle first") }
        let candidate = URL(fileURLWithPath: runtime).appendingPathComponent("Geist.app")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let installed = root.appendingPathComponent("Geist.app")
        try fm.createDirectory(at: installed.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let info = ["CFBundleIdentifier": "com.geisten.geist", "CFBundleShortVersionString": "0.0.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: installed.appendingPathComponent("Contents/Info.plist"))
        // CI also builds non-release 0.0.0-dev bundles. Only numeric candidates
        // can participate in installation; development builds never relocate.
        guard AppInstallation.version(at: candidate) != nil else { throw XCTSkip("Numeric release candidate required") }
        try AppInstallation.replace(source: candidate, destination: installed, prepare: {})
        try AppInstallation.verify(installed)
        XCTAssertEqual(AppInstallation.version(at: installed), AppInstallation.version(at: candidate))
    }

    func testMinorReplacementAndFailuresPreserveInstalledBundle() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func bundle(_ name: String, version: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try fm.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let info = ["CFBundleIdentifier": "com.geisten.geist", "CFBundleShortVersionString": version]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: url.appendingPathComponent("Contents/Info.plist"))
            return url
        }
        let installed = try bundle("Geist.app", version: "0.4.1")
        let incoming = try bundle("download.app", version: "0.5.3")
        XCTAssertFalse(AppInstallation.isAtLeastAsNew(installed, as: incoming))
        let same = try bundle("same.app", version: "0.5.3")
        XCTAssertTrue(AppInstallation.isAtLeastAsNew(same, as: incoming))
        let newerBuild = ["CFBundleIdentifier": "com.geisten.geist", "CFBundleShortVersionString": "0.5.3", "CFBundleVersion": "28"]
        try PropertyListSerialization.data(fromPropertyList: newerBuild, format: .xml, options: 0)
            .write(to: incoming.appendingPathComponent("Contents/Info.plist"))
        XCTAssertFalse(AppInstallation.isAtLeastAsNew(same, as: incoming))
        let data = root.appendingPathComponent("models-marker")
        try Data("untouched".utf8).write(to: data)
        var prepared = false
        XCTAssertThrowsError(try AppInstallation.replace(source: incoming, destination: installed,
            verify: { _ in throw AppInstallation.Failure.invalidBundle }, prepare: { prepared = true }))
        XCTAssertFalse(prepared)
        XCTAssertEqual(AppInstallation.version(at: installed), AppVersion("0.4.1"))
        XCTAssertThrowsError(try AppInstallation.replace(source: incoming, destination: installed,
            verify: { _ in }, prepare: { throw AppInstallation.Failure.unsafeDestination }))
        XCTAssertEqual(AppInstallation.version(at: installed), AppVersion("0.4.1"))
        try AppInstallation.replace(source: incoming, destination: installed, verify: { _ in }, prepare: { prepared = true })
        XCTAssertTrue(prepared)
        XCTAssertEqual(AppInstallation.version(at: installed), AppVersion("0.5.3"))
        XCTAssertEqual(try String(contentsOf: data), "untouched")
        let old = try bundle("old.app", version: "0.4.9")
        XCTAssertThrowsError(try AppInstallation.replace(source: old, destination: installed, verify: { _ in }, prepare: {}))
        let link = root.appendingPathComponent("linked.app")
        try fm.createSymbolicLink(at: link, withDestinationURL: installed)
        XCTAssertThrowsError(try AppInstallation.replace(source: incoming, destination: link, verify: { _ in }, prepare: {}))
        XCTAssertFalse(try fm.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".Geist-") })
    }
}
