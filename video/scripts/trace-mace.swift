// Finds the mace in each frame of a swing, which Vision will not do for you:
// it detects people, and a gada is not a person.
//
// What it keys on is the head. The brass is the only strongly yellow thing in
// the room - skin is warmer but far less separated between its red and blue
// channels, and the lamp is the one other candidate, which is why the search
// is restricted to an annulus around the hands at roughly the mace's own
// length. The shaft is not tracked at all: two points, the grip and the head,
// are the whole of what a drawn mace needs.
//
// Usage: swift video/scripts/trace-mace.swift pose.jsonl frames-dir > mace.jsonl
//
// Output is one JSON object per line, matched to pose.jsonl by file name, in
// the same top-left pixel coordinates.

import AppKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 else {
    FileHandle.standardError.write(
        "usage: trace-mace.swift <pose.jsonl> <frames-dir>\n".data(using: .utf8)!)
    exit(1)
}
let (posePath, framesDir) = (args[0], args[1])

/// How far the head sits from the hands, as a fraction of the subject's own
/// height in frame. Measured off this footage rather than assumed: the grip
/// is partway up the handle, so it is well short of the whole implement.
let MACE_MIN = 0.38
let MACE_MAX = 0.72

/// Brass against a dim room. `r - b` carries most of the signal; requiring
/// `g` to sit between them is what separates brass from skin and from the
/// pink of the lamp.
func brassScore(_ r: Int, _ g: Int, _ b: Int, _ floor: Int) -> Int {
    guard r > 130, g > b, r > g else { return 0 }
    let warmth = (r - b) + (g - b)
    return warmth > floor ? warmth : 0
}

/// Through the fast part of the revolution the head smears across a third of
/// the frame and every pixel of it washes out, so a threshold tight enough to
/// reject the lamp when the mace is still finds nothing at all when it moves.
/// Take the tightest one that finds something.
let BRASS_FLOORS = [85, 62, 45]

struct Frame {
    let file: String
    let grip: CGPoint?
    let height: CGFloat
}

// --- the poses, for the grip and the scale ------------------------------
var frames: [Frame] = []
for line in (try! String(contentsOfFile: posePath, encoding: .utf8)).split(separator: "\n") {
    guard
        let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        let file = obj["file"] as? String
    else { continue }
    let joints = (obj["joints"] as? [String: [Double]]) ?? [:]

    // The hands are together on the handle, so either wrist will do; average
    // the ones Vision was willing to commit to.
    var sum = CGPoint.zero
    var n = 0.0
    for key in ["leftWrist", "rightWrist"] {
        guard let p = joints[key], p.count == 3, p[2] > 0.1 else { continue }
        sum.x += p[0]
        sum.y += p[1]
        n += 1
    }
    let grip = n > 0 ? CGPoint(x: sum.x / n, y: sum.y / n) : nil

    // Subject height in frame: ankle to nose, which is stable even when a
    // limb is mid-blur.
    var subject: CGFloat = 0
    if let nose = joints["nose"], let ankle = joints["leftAnkle"] {
        subject = abs(CGFloat(ankle[1] - nose[1]))
    }
    frames.append(Frame(file: file, grip: grip, height: subject))
}

// --- the brass, frame by frame -----------------------------------------
func jsonString(_ s: String) -> String { "\"\(s)\"" }

for frame in frames {
    let path = "\(framesDir)/\(frame.file)"
    guard let image = NSImage(contentsOfFile: path),
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
        let data = cg.dataProvider?.data,
        let bytes = CFDataGetBytePtr(data)
    else {
        FileHandle.standardError.write("could not load \(path)\n".data(using: .utf8)!)
        continue
    }
    let w = cg.width, h = cg.height
    let stride = cg.bytesPerRow
    let pixelBytes = cg.bitsPerPixel / 8
    guard let grip = frame.grip, frame.height > 0 else {
        print("{\(jsonString("file")): \(jsonString(frame.file)), \"found\": false}")
        continue
    }
    let rMin = frame.height * MACE_MIN, rMax = frame.height * MACE_MAX

    // Bin the brass into a coarse grid and take the heaviest bin: the head is
    // a blob, and a blob outscores the scattered pixels a warm highlight
    // leaves behind.
    let bin = 16
    var weight: [Int: Int] = [:]
    var centroid: [Int: (Double, Double)] = [:]
    var floorUsed = 0
    for floor in BRASS_FLOORS {
        weight.removeAll()
        centroid.removeAll()
        floorUsed = floor
        for y in Swift.stride(from: 0, to: h, by: 2) {
            for x in Swift.stride(from: 0, to: w, by: 2) {
                let d = hypot(CGFloat(x) - grip.x, CGFloat(y) - grip.y)
                guard d >= rMin, d <= rMax else { continue }
                let i = y * stride + x * pixelBytes
                let s = brassScore(Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), floor)
                guard s > 0 else { continue }
                let key = (y / bin) * 1000 + (x / bin)
                weight[key, default: 0] += s
                let c = centroid[key] ?? (0, 0)
                centroid[key] = (c.0 + Double(x) * Double(s), c.1 + Double(y) * Double(s))
            }
        }
        if let top = weight.values.max(), top > 900 { break }
    }
    guard let (key, total) = weight.max(by: { $0.value < $1.value }), total > 0 else {
        print("{\(jsonString("file")): \(jsonString(frame.file)), \"found\": false}")
        continue
    }
    // Re-centre over the neighbouring bins too, so a head straddling a bin
    // edge does not get pulled to one side of itself.
    let bx = key % 1000, by = key / 1000
    var sx = 0.0, sy = 0.0, sw = 0.0
    for dy in -1...1 {
        for dx in -1...1 {
            let k = (by + dy) * 1000 + (bx + dx)
            guard let wgt = weight[k], let c = centroid[k] else { continue }
            sx += c.0
            sy += c.1
            sw += Double(wgt)
        }
    }
    let hx = sx / sw, hy = sy / sw
    // Screen angle from the grip, measured the way the drawing wants it:
    // zero straight up, growing clockwise.
    let angle = atan2(hx - Double(grip.x), Double(grip.y) - hy) * 180 / .pi
    print(
        "{\(jsonString("file")): \(jsonString(frame.file)), \"found\": true, "
            + "\"head\": [\(String(format: "%.1f", hx)), \(String(format: "%.1f", hy))], "
            + "\"grip\": [\(String(format: "%.1f", grip.x)), \(String(format: "%.1f", grip.y))], "
            + "\"angle\": \(String(format: "%.1f", angle < 0 ? angle + 360 : angle)), "
            + "\"radius\": \(String(format: "%.1f", hypot(hx - Double(grip.x), hy - Double(grip.y)))), "
            + "\"score\": \(total), \"floor\": \(floorUsed)}")
}
