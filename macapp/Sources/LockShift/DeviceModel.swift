import Foundation

/// Hardware identifiers verified against DeviceKit's device catalog:
/// https://github.com/devicekit/DeviceKit/blob/master/Source/Device.generated.swift
/// Unknown models retain their device-reported name rather than guessing.
enum DeviceModel {
    static func name(for identifier: String?) -> String? {
        switch identifier {
        case "iPhone14,5": return "iPhone 13"
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        case "iPhone17,5": return "iPhone 16e"
        case "iPad11,3", "iPad11,4": return "iPad Air (3rd generation)"
        case "iPad13,1", "iPad13,2": return "iPad Air (4th generation)"
        case "iPad13,16", "iPad13,17": return "iPad Air (5th generation)"
        case "iPad14,8", "iPad14,9": return "iPad Air 11-inch (M2)"
        case "iPad14,10", "iPad14,11": return "iPad Air 13-inch (M2)"
        case "iPad15,3", "iPad15,4": return "iPad Air 11-inch (M3)"
        case "iPad15,5", "iPad15,6": return "iPad Air 13-inch (M3)"
        case "iPad11,6", "iPad11,7": return "iPad (8th generation)"
        case "iPad12,1", "iPad12,2": return "iPad (9th generation)"
        case "iPad13,18", "iPad13,19": return "iPad (10th generation)"
        case "iPad15,7", "iPad15,8": return "iPad (A16)"
        case "iPad11,1", "iPad11,2": return "iPad mini (5th generation)"
        case "iPad14,1", "iPad14,2": return "iPad mini (6th generation)"
        case "iPad16,1", "iPad16,2": return "iPad mini (A17 Pro)"
        case "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7": return "iPad Pro 11-inch (M1)"
        case "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11": return "iPad Pro 12.9-inch (M1)"
        case "iPad14,3", "iPad14,4": return "iPad Pro 11-inch (M2)"
        case "iPad14,5", "iPad14,6": return "iPad Pro 12.9-inch (M2)"
        case "iPad16,3", "iPad16,4": return "iPad Pro 11-inch (M4)"
        case "iPad16,5", "iPad16,6": return "iPad Pro 13-inch (M4)"
        default: return nil
        }
    }
}

/// Explicit choices win over the default iPhone preference while still attached.
enum DeviceSelection {
    static func preferred(in devices: [DeviceInfo], explicit: String?) -> String? {
        if let explicit, devices.contains(where: { $0.udid == explicit }) { return explicit }
        return devices.sorted {
            if $0.isIPhone != $1.isIPhone { return $0.isIPhone }
            return $0.udid < $1.udid
        }.first?.udid
    }
}
