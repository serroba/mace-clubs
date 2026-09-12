// Reads a body pose out of each frame of a swing using macOS's built-in
// Vision framework - the same reason tools/e2e/ocr.swift uses it, which is
// that a Connect IQ dev machine already has `swift` and nothing else has to
// be installed.
//
// Output is one JSON object per line, one line per frame, with every joint in
// pixel coordinates with y pointing down (Vision hands them back normalised
// with the origin at the bottom-left, which no drawing tool wants).
//
// Usage: swift video/scripts/trace-pose.swift frames/*.jpg > pose.jsonl
//
// The mace is not in here. Vision finds people, not implements, and the
// shaft is tracked separately - see trace-mace.swift, which starts from the
// wrists this produces.

import AppKit
import Vision

let paths = Array(CommandLine.arguments.dropFirst())
guard !paths.isEmpty else {
    FileHandle.standardError.write("usage: trace-pose.swift <frame.jpg> ...\n".data(using: .utf8)!)
    exit(1)
}

// Every joint Vision reports, in a fixed order so the output diffs cleanly.
let joints: [(String, VNHumanBodyPoseObservation.JointName)] = [
    ("nose", .nose),
    ("neck", .neck),
    ("leftShoulder", .leftShoulder), ("rightShoulder", .rightShoulder),
    ("leftElbow", .leftElbow), ("rightElbow", .rightElbow),
    ("leftWrist", .leftWrist), ("rightWrist", .rightWrist),
    ("root", .root),
    ("leftHip", .leftHip), ("rightHip", .rightHip),
    ("leftKnee", .leftKnee), ("rightKnee", .rightKnee),
    ("leftAnkle", .leftAnkle), ("rightAnkle", .rightAnkle),
]

func jsonString(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

for path in paths {
    guard let image = NSImage(contentsOfFile: path),
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        FileHandle.standardError.write("could not load \(path)\n".data(using: .utf8)!)
        continue
    }
    let width = CGFloat(cgImage.width)
    let height = CGFloat(cgImage.height)

    let request = VNDetectHumanBodyPoseRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        FileHandle.standardError.write("vision failed on \(path): \(error)\n".data(using: .utf8)!)
        continue
    }

    // One person in frame. If Vision finds more (a reflection, someone
    // walking past), the largest-confidence observation is the subject.
    guard
        let observation = (request.results ?? [])
            .max(by: { $0.confidence < $1.confidence })
    else {
        print("{\"file\": \(jsonString(path)), \"found\": false}")
        continue
    }
    let points = (try? observation.recognizedPoints(.all)) ?? [:]

    var fields: [String] = [
        "\"file\": \(jsonString((path as NSString).lastPathComponent))",
        "\"found\": true",
        "\"width\": \(Int(width))",
        "\"height\": \(Int(height))",
    ]
    var body: [String] = []
    for (name, key) in joints {
        guard let p = points[key], p.confidence > 0 else { continue }
        // Vision's origin is bottom-left and normalised; flip to top-left
        // pixels, which is what SVG and every other drawing surface uses.
        let x = p.location.x * width
        let y = (1 - p.location.y) * height
        body.append(
            "\(jsonString(name)): [\(String(format: "%.1f", x)), "
                + "\(String(format: "%.1f", y)), \(String(format: "%.2f", p.confidence))]")
    }
    fields.append("\"joints\": {\(body.joined(separator: ", "))}")
    print("{\(fields.joined(separator: ", "))}")
}
