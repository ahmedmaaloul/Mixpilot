#!/usr/bin/env swift
// Changes an app in a running debug build of Mixpilot, without the panel.
//   scripts/debug-volume.swift com.apple.QuickTimePlayerX 0.3        volume 0…2
//   scripts/debug-volume.swift com.apple.QuickTimePlayerX mute       or unmute
//   scripts/debug-volume.swift com.apple.QuickTimePlayerX device <UID | system>
// Compile once for speed: swiftc -O scripts/debug-volume.swift -o build/debug-volume
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    print("usage: debug-volume.swift <bundle ID> <0…2 | mute | unmute | device <UID | system>>")
    exit(1)
}
var info: [String: Any] = ["app": arguments[0]]
switch arguments[1] {
case "mute": info["muted"] = true
case "unmute": info["muted"] = false
case "device":
    guard arguments.count == 3 else { print("device needs a UID or system"); exit(1) }
    info["device"] = arguments[2]
default:
    guard let volume = Double(arguments[1]) else { print("not a number: \(arguments[1])"); exit(1) }
    info["volume"] = volume
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("app.mixpilot.debug.volume"), object: nil, userInfo: info, deliverImmediately: true
)
