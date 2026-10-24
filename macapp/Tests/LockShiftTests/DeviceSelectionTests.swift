import XCTest
@testable import LockShift

final class DeviceSelectionTests: XCTestCase {
    private let phone = DeviceInfo(udid: "z-phone", name: "My phone", productType: "iPhone17,1", productVersion: "26.0")
    private let pad = DeviceInfo(udid: "a-pad", name: "My tablet", productType: "iPad13,1", productVersion: "26.0")

    func testIPhoneWinsDefaultRegardlessOfDiscoveryOrder() {
        XCTAssertEqual(DeviceSelection.preferred(in: [pad, phone], explicit: nil), phone.udid)
        XCTAssertEqual(DeviceSelection.preferred(in: [phone, pad], explicit: nil), phone.udid)
    }

    func testExplicitIPadChoicePersistsWhenIPhoneIsPresent() {
        XCTAssertEqual(DeviceSelection.preferred(in: [pad, phone], explicit: pad.udid), pad.udid)
    }

    func testUnpluggedChoiceFallsBackToRemainingDevice() {
        XCTAssertEqual(DeviceSelection.preferred(in: [pad], explicit: phone.udid), pad.udid)
        XCTAssertNil(DeviceSelection.preferred(in: [], explicit: phone.udid))
    }

    func testIPadModelAndOperatingSystemAreDecoded() {
        XCTAssertEqual(pad.modelName, "iPad Air (4th generation)")
        XCTAssertEqual(pad.usbConnectionDescription, "iPad Air (4th generation) · iPadOS 26.0 · USB connected")
        XCTAssertEqual(pad.family, "iPad")
        XCTAssertEqual(phone.modelName, "iPhone 16 Pro")
    }

    func testUnknownModelUsesReportedNameWithoutInventingOne() {
        let unknown = DeviceInfo(udid: "future", name: "My new iPad", productType: "iPad99,1", productVersion: nil)
        XCTAssertEqual(unknown.modelName, "My new iPad")
        XCTAssertEqual(unknown.usbConnectionDescription, "My new iPad · USB connected")
    }
}
