// Scroll frame-drop analysis for iOS screen recordings.
//
//   swiftc -O docs/tools/scroll-frame-analysis.swift -o /tmp/sfa
//   /tmp/sfa docs/ScreenRecording1.MP4                    # summary
//   /tmp/sfa portrait.MP4 landscape.MP4                   # one summary each
//   /tmp/sfa docs/ScreenRecording1.MP4 --csv              # per-frame CSV (single file)
//
// Requires a recording whose frame rate matches the device refresh rate
// (60 fps recording on a 60 Hz device).
//
// WHAT THE OUTPUT IS NOT: a repeated frame is not reliably a dropped display
// frame. A control run over Apple Calendar produced roughly 13 % with this
// method while Flux produced about 5 %, so the absolute rate is dominated by
// how ReplayKit captures, not by how the app scrolls. Read the numbers only as
// a comparison between two arms recorded in the same sitting, and never as a
// release gate or a quality figure.
//
// Method: each frame is reduced to a 640-entry luminance profile along the axis
// the content scrolls on. The scroll offset between consecutive frames is
// estimated by SAD cross-correlation; `mad` is the mean absolute profile
// difference and detects duplicated frames. Motion is classified from the
// median neighbour velocity so a dropped frame cannot suppress its own
// classification.
//
// Two properties of real recordings the profile has to survive:
//
//   * A landscape capture is stored rotated — the track carries a ±90°
//     `preferredTransform` while `naturalSize` stays portrait. Profiling rows
//     of the stored frame would then scan across the scroll direction and
//     report almost no motion, so the scan axis follows the transform.
//   * Starting, stopping and rotating leave second-long gaps between
//     presentation timestamps. A pair spanning more than 1.5 intervals is
//     excluded, so a pause is never mistaken for a fast scroll.
//
// The effective frame rate is taken from the median presentation-timestamp
// interval rather than `nominalFrameRate`, which averages over those gaps and
// consequently understates the rate (57.19 instead of 60.00 on a recording
// containing two rotations).

import AVFoundation
import Foundation

let profileBins = 640
let thinAxis = 64
let maximumShift = 120
let duplicateThreshold = 0.06
let motionThreshold = 300.0 // pt/s
// iOS renders at 3x on the phones this timeline targets, so points are pixels / 3.
let renderScale = 3.0

struct Frame {
    let time: Double
    let shift: Double
    let difference: Double
    /// False when the gap to the previous frame spans a recording pause.
    let usable: Bool
}

func estimateShift(_ previous: [Double], _ current: [Double]) -> Double {
    var bestShift = 0
    var bestScore = Double.greatestFiniteMagnitude
    for shift in -maximumShift...maximumShift {
        var score = 0.0
        var samples = 0
        var index = max(0, -shift)
        let end = min(profileBins, profileBins - shift)
        guard end - index >= profileBins / 3 else { continue }
        while index < end {
            score += abs(previous[index + shift] - current[index])
            samples += 1
            index += 1
        }
        let mean = score / Double(samples)
        if mean < bestScore {
            bestScore = mean
            bestShift = shift
        }
    }
    return Double(bestShift)
}

func analyse(path: String, emitCSV: Bool) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let ready = DispatchSemaphore(value: 0)
    var videoTrack: AVAssetTrack?
    var naturalSize = CGSize.zero
    var preferredTransform = CGAffineTransform.identity
    Task {
        videoTrack = try? await asset.loadTracks(withMediaType: .video).first
        if let track = videoTrack {
            naturalSize = (try? await track.load(.naturalSize)) ?? .zero
            preferredTransform = (try? await track.load(.preferredTransform)) ?? .identity
        }
        ready.signal()
    }
    ready.wait()

    guard let videoTrack, naturalSize.height > 0 else {
        FileHandle.standardError.write("\(path): no readable video track\n".data(using: .utf8)!)
        return
    }

    // A ±90° transform means the stored frame is rotated: what scrolls
    // vertically on screen moves along the stored horizontal axis.
    let rotationDegrees = abs(atan2(preferredTransform.b, preferredTransform.a) * 180 / .pi)
    let isRotated = rotationDegrees > 45 && rotationDegrees < 135
    let decodeWidth = isRotated ? profileBins : thinAxis
    let decodeHeight = isRotated ? thinAxis : profileBins
    let scanAxisPixels = isRotated ? naturalSize.width : naturalSize.height
    let pointsPerProfileBin = Double(scanAxisPixels / CGFloat(profileBins)) / renderScale

    guard let reader = try? AVAssetReader(asset: asset) else {
        FileHandle.standardError.write("\(path): could not open reader\n".data(using: .utf8)!)
        return
    }
    let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: decodeWidth,
        kCVPixelBufferHeightKey as String: decodeHeight,
    ])
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else {
        FileHandle.standardError.write("\(path): could not start reading\n".data(using: .utf8)!)
        return
    }

    func profile(of buffer: CVPixelBuffer) -> [Double] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let address = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        let base = address.assumingMemoryBound(to: UInt8.self)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var result = [Double](repeating: 0, count: profileBins)
        if isRotated {
            for x in 0..<min(width, profileBins) {
                var sum = 0.0
                for y in 0..<height {
                    let pixel = base + y * stride + x * 4
                    sum += 0.114 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.299 * Double(pixel[2])
                }
                result[x] = sum / Double(height)
            }
        } else {
            for y in 0..<min(height, profileBins) {
                var sum = 0.0
                let row = base + y * stride
                for x in 0..<width {
                    let pixel = row + x * 4
                    sum += 0.114 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.299 * Double(pixel[2])
                }
                result[y] = sum / Double(width)
            }
        }
        return result
    }

    var rawFrames: [(time: Double, shift: Double, difference: Double, interval: Double)] = []
    var previousProfile: [Double]?
    var previousTime: Double?

    while let sample = output.copyNextSampleBuffer() {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
        guard time.isFinite else { continue }
        let current = profile(of: buffer)
        guard current.count == profileBins else { continue }
        if let previousProfile, let previousTime {
            var difference = 0.0
            for index in 0..<profileBins { difference += abs(previousProfile[index] - current[index]) }
            rawFrames.append((
                time: time,
                shift: estimateShift(previousProfile, current),
                difference: difference / Double(profileBins),
                interval: time - previousTime
            ))
        }
        previousProfile = current
        previousTime = time
    }

    guard rawFrames.count > 10 else {
        FileHandle.standardError.write("\(path): only \(rawFrames.count) frames decoded\n".data(using: .utf8)!)
        return
    }

    let medianInterval = rawFrames.map(\.interval).sorted()[rawFrames.count / 2]
    let effectiveFrameRate = medianInterval > 0 ? 1 / medianInterval : 60
    let frames = rawFrames.map {
        Frame(time: $0.time, shift: $0.shift, difference: $0.difference,
              usable: $0.interval < medianInterval * 1.5)
    }

    if emitCSV {
        print("index,time,shift,pointsPerSecond,difference,usable")
        for (index, frame) in frames.enumerated() {
            let velocity = abs(frame.shift) * pointsPerProfileBin * effectiveFrameRate
            print(String(format: "%d,%.4f,%.1f,%.0f,%.4f,%d",
                         index, frame.time, frame.shift, velocity, frame.difference, frame.usable ? 1 : 0))
        }
        return
    }

    // Median neighbour velocity, excluding the frame itself and any pause.
    func neighbourVelocity(_ index: Int) -> Double {
        var window: [Double] = []
        for other in max(0, index - 4)...min(frames.count - 1, index + 4)
        where other != index && frames[other].usable {
            window.append(abs(frames[other].shift) * pointsPerProfileBin * effectiveFrameRate)
        }
        guard !window.isEmpty else { return 0 }
        window.sort()
        return window[window.count / 2]
    }

    let velocities = (0..<frames.count).map(neighbourVelocity)
    let totalScroll = frames.filter(\.usable).reduce(0.0) { $0 + abs($1.shift) * pointsPerProfileBin }
    let pauses = frames.filter { !$0.usable }.count

    print("=== \((path as NSString).lastPathComponent) ===")
    print(String(format: "recording      %.2f s, stored %.0f x %.0f, rotation %.0f° -> scan %@",
                 frames[frames.count - 1].time - frames[0].time,
                 naturalSize.width, naturalSize.height, rotationDegrees,
                 isRotated ? "horizontal" : "vertical"))
    print(String(format: "               %.2f fps (median interval), %d frames, %d pause gaps",
                 effectiveFrameRate, frames.count + 1, pauses))
    print(String(format: "total scroll   %.0f pt", totalScroll))
    print("")
    print("threshold   motionFrames  dropped    rate   events   scrolled   1 drop per")

    for threshold in [motionThreshold, 1000, 2000] {
        let motion = (0..<frames.count).filter { frames[$0].usable && velocities[$0] > threshold }
        guard motion.count > 20 else { continue }
        let dropped = motion.filter { frames[$0].difference < duplicateThreshold }
        var events = 0
        var previous = -9
        for index in dropped {
            if index != previous + 1 { events += 1 }
            previous = index
        }
        let scrolled = motion.reduce(0.0) { $0 + abs(frames[$1].shift) * pointsPerProfileBin }
        print(String(format: "> %4.0f pt/s   %10d  %7d  %5.2f%%  %6d  %8.0f pt  %8.0f pt",
                     threshold, motion.count, dropped.count,
                     100 * Double(dropped.count) / Double(motion.count),
                     events, scrolled, scrolled / Double(max(1, events))))
    }

    print("")
    print("drop rate by instantaneous velocity")
    for (low, high) in [(300.0, 700.0), (700.0, 1200.0), (1200.0, 1800.0), (1800.0, 2500.0), (2500.0, Double.infinity)] {
        let bucket = (0..<frames.count).filter { frames[$0].usable && velocities[$0] >= low && velocities[$0] < high }
        guard bucket.count > 20 else { continue }
        let dropped = bucket.filter { frames[$0].difference < duplicateThreshold }
        print(String(format: "  %5.0f - %5.0f pt/s   frames %5d   dropped %4d   %5.2f%%",
                     low, min(high, 99999), bucket.count, dropped.count,
                     100 * Double(dropped.count) / Double(bucket.count)))
    }
    print("")
}

let arguments = CommandLine.arguments
let emitCSV = arguments.contains("--csv")
let paths = arguments.dropFirst().filter { $0 != "--csv" }
guard !paths.isEmpty else {
    FileHandle.standardError.write("usage: sfa <recording.mp4> [more.mp4 ...] [--csv]\n".data(using: .utf8)!)
    exit(2)
}
guard !emitCSV || paths.count == 1 else {
    FileHandle.standardError.write("--csv takes a single recording\n".data(using: .utf8)!)
    exit(2)
}
for path in paths { analyse(path: path, emitCSV: emitCSV) }
