#!/usr/bin/env swift
import AppKit
import CoreGraphics

let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
    print("CGWindowListCopyWindowInfo returned nil")
    exit(1)
}

print("on-screen windows (\(raw.count)):")
for d in raw {
    let owner = (d[kCGWindowOwnerName as String] as? String) ?? "?"
    let title = (d[kCGWindowName as String] as? String) ?? ""
    let layer = (d[kCGWindowLayer as String] as? Int) ?? 0
    if layer != 0 { continue }  // skip menu bar / dock layer windows
    print("  owner=\"\(owner)\" title=\"\(title)\"")
}
