import Foundation
import AppKit
import XCTest
@testable import Geist

final class UpdateShutdownTests: XCTestCase {
    @MainActor
    func testMenuQuitCannotBypassPendingUpdateShutdown() async {
        let delegate = AppDelegate()
        let app = NSApplication.shared
        XCTAssertEqual(delegate.applicationShouldTerminate(app), .terminateNow)
        let release = DispatchSemaphore(value: 0)
        let failed = expectation(description: "failed stop")
        delegate.updateShutdown.prepare(stop: {
            _ = release.wait(timeout: .now() + 2)
            return false
        }) { _ in failed.fulfill() }
        XCTAssertEqual(delegate.applicationShouldTerminate(app), .terminateCancel)
        release.signal()
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertEqual(delegate.applicationShouldTerminate(app), .terminateCancel)
        delegate.updateShutdown.reset()
        XCTAssertEqual(delegate.applicationShouldTerminate(app), .terminateNow)
    }

    @MainActor
    func testSparkleCanCallEverySafetyCallback() {
        let delegate = AppDelegate()
        for selector in ["updaterShouldRelaunchApplication:",
                         "updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:",
                         "updater:didFinishUpdateCycleForUpdateCheck:error:"] {
            XCTAssertTrue(delegate.responds(to: NSSelectorFromString(selector)), selector)
        }
    }

    @MainActor
    func testFailedStopPreventsInstallAndNewCycleCanRetry() async {
        let gate = UpdateShutdown()
        let failed = expectation(description: "failed stop aborts resumed install")
        gate.prepare(stop: { false }) { stopped in
            XCTAssertFalse(stopped)
            XCTAssertFalse(gate.mayInstall)
            failed.fulfill()
        }
        XCTAssertFalse(gate.mayInstall)
        await fulfillment(of: [failed], timeout: 3)
        gate.reset()
        let recovered = expectation(description: "successful retry permits install")
        gate.prepare(stop: { true }) { stopped in
            XCTAssertTrue(stopped)
            XCTAssertTrue(gate.mayInstall)
            recovered.fulfill()
        }
        await fulfillment(of: [recovered], timeout: 3)
    }

    @MainActor
    func testStopRunsOffMainThreadAndRepeatedRequestsDoNotResumeTwice() async {
        let gate = UpdateShutdown()
        let released = DispatchSemaphore(value: 0)
        let completed = expectation(description: "one stop and completion")
        let duplicate = expectation(description: "duplicate ignored")
        duplicate.isInverted = true
        gate.prepare(stop: {
            XCTAssertFalse(Thread.isMainThread)
            _ = released.wait(timeout: .now() + 2)
            return true
        }) { _ in completed.fulfill() }
        gate.prepare(stop: { XCTFail("duplicate stop"); return true }) { _ in duplicate.fulfill() }
        XCTAssertFalse(gate.mayInstall)
        released.signal()
        await fulfillment(of: [completed, duplicate], timeout: 1)
    }

    @MainActor
    func testCancelledCycleCannotResumeItsOldInstallation() async {
        let gate = UpdateShutdown()
        let released = DispatchSemaphore(value: 0)
        let stopped = expectation(description: "worker returned")
        let obsolete = expectation(description: "obsolete install never resumes")
        obsolete.isInverted = true
        gate.prepare(stop: {
            _ = released.wait(timeout: .now() + 2)
            stopped.fulfill()
            return true
        }) { _ in obsolete.fulfill() }
        gate.reset()
        released.signal()
        await fulfillment(of: [stopped, obsolete], timeout: 1)
        XCTAssertEqual(gate.state, .idle)
        XCTAssertTrue(gate.mayInstall)
    }
}
