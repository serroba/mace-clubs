// Reads text out of a screenshot PNG using macOS's built-in Vision OCR -
// no extra dependency to install, since Xcode command line tools (which
// ship `swift`) are typically already present on a Connect IQ dev machine.
// One line of recognized text per line of output.
//
// Usage: swift tools/e2e/ocr.swift path/to/screenshot.png

import AppKit
import Vision

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: ocr.swift <image-path>\n".data(using: .utf8)!)
    exit(1)
}

let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: path),
    let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write("could not load image at \(path)\n".data(using: .utf8)!)
    exit(1)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([request])
} catch {
    FileHandle.standardError.write("OCR failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}

for observation in request.results ?? [] {
    if let candidate = observation.topCandidates(1).first {
        print(candidate.string)
    }
}
