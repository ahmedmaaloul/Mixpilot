#!/usr/bin/env swift
// Changes an app's volume in a running debug build of Mixpilot, without the panel.
//   scripts/debug-volume.swift com.apple.QuickTimePlayerX 0.3
//   scripts/debug-volume.swift com.apple.QuickTimePlayerX mute | unmute
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 2, let app = arguments.first, let value = arguments.last else {
    print("usage: debug-volume.swift <bundle ID> <0…1 | mute | unmute>")
    exit(1)
}
var info: [String: Any] = ["app": app]
switch value {
case "mute": info["muted"] = true
case "unmute": info["muted"] = false
default:
    guard let volume = Double(value) else { print("not a number: \(value)"); exit(1) }
    info["volume"] = volume
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("app.mixpilot.debug.volume"), object: nil, userInfo: info, deliverImmediately: true
)
