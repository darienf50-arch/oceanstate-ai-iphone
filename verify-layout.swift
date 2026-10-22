import AppKit
import Vision
import Foundation
for filename in CommandLine.arguments.dropFirst() {
    let handler = VNImageRequestHandler(url: URL(fileURLWithPath: filename))
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try handler.perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
    for label in ["choose your atmosphere", "midnight", "matrix", "deep ocean"] {
        guard text.contains(label) else { fatalError("Missing theme control '\(label)' in \(filename)") }
    }
    print("PASS: theme picker and all three choices visible: \(filename)")
}
