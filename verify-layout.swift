import AppKit
import Foundation

// The connected fixture screens must show the cyan composer controls near the
// bottom of the viewport. This guards the observed missing-composer regression.
for filename in CommandLine.arguments.dropFirst() {
    let data = try Data(contentsOf: URL(fileURLWithPath: filename))
    guard let bitmap = NSBitmapImageRep(data: data) else { fatalError("Cannot decode \(filename)") }
    var cyanPixels = 0
    for y in Int(Double(bitmap.pixelsHigh) * 0.82)..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
               c.redComponent < 0.35, c.greenComponent > 0.6, c.blueComponent > 0.7 {
                cyanPixels += 1
            }
        }
    }
    guard cyanPixels > 200 else { fatalError("Composer controls are missing from \(filename)") }
    print("PASS: connected screen composer visible: \(filename)")
}
