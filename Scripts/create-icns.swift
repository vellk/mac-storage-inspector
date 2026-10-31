#!/usr/bin/env swift
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: create-icns.swift <iconset-directory> <output.icns>\n", stderr)
    exit(2)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let chunks = [
    ("ic10", "icon_512x512@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic08", "icon_256x256.png"),
    ("ic07", "icon_128x128.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("icp4", "icon_16x16.png")
]

func bigEndianBytes(_ value: Int) -> Data {
    var encoded = UInt32(value).bigEndian
    return withUnsafeBytes(of: &encoded) { Data($0) }
}

var body = Data()
for (type, filename) in chunks {
    let png = try Data(contentsOf: iconset.appendingPathComponent(filename))
    body.append(Data(type.utf8))
    body.append(bigEndianBytes(png.count + 8))
    body.append(png)
}

var result = Data("icns".utf8)
result.append(bigEndianBytes(body.count + 8))
result.append(body)
try result.write(to: output, options: .atomic)
