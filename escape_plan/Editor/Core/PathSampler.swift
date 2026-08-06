//  PathSampler.swift
//  Pure motion sampling for an engine-produced evacuation track.
//
//  TimedStep coordinates stay in the model's floor-local plan frame. The renderer is solely
//  responsible for lifting them into SceneKit via DollhouseGeometry. In particular, a stair
//  crossing has no horizontal length: its two endpoints share x/y and differ only by floor.
//  `FloorTransition` preserves that interval so the renderer can interpolate between the two
//  known floor base heights instead of teleporting.

import Foundation

/// A finite point in floor-local plan meters.
nonisolated struct PathPosition: Equatable {
    var x: Double
    var y: Double
}

/// A floor change in progress. `progress` is always finite and clamped to 0...1.
nonisolated struct FloorTransition: Equatable {
    var fromFloorID: String
    var toFloorID: String
    var progress: Double
}

/// The complete pure-math result needed to render one track at one instant.
nonisolated struct PathSample: Equatable {
    var position: PathPosition

    /// Plan-space heading in radians: 0 is +x and +pi/2 is +plan-y. It is normalized to
    /// [-pi, pi). Since plan-y maps to SceneKit -z, a renderer normally negates this value
    /// before applying it as a SceneKit yaw (then accounts for the rig's authored forward).
    var heading: Double

    /// The source step's floor while a segment is in flight; the destination floor exactly at
    /// its timestamp. During a crossing, use `floorTransition` to compute vertical position.
    var floorID: String

    /// The active engine-provided TimedStep kind. It is never inferred from geometry.
    var kind: String

    /// Segment `i` connects sanitized step i to i+1. A one-step path has no segment.
    var segmentIndex: Int?
    var segmentProgress: Double

    /// Present for the full open interval of every cross-floor segment, even when x/y are
    /// identical and horizontal speed is therefore zero.
    var floorTransition: FloorTransition?

    /// Horizontal plan speed and cumulative horizontal distance. Both are finite and
    /// non-negative. Floor height is intentionally absent from this Foundation-only layer.
    var groundSpeed: Double
    var groundDistance: Double

    /// Strict boundary flags. At exactly the final timestamp both are false while
    /// `hasReachedEnd` is true, which lets the renderer settle immediately at egress.
    var isBeforeStart: Bool
    var isAfterEnd: Bool
    var hasReachedEnd: Bool

    var currentKind: String { kind }
    var isInMotion: Bool { groundSpeed > PathSampler.motionEpsilon || floorTransition != nil }
}

/// Deterministic interpolation over an engine-produced `[TimedStep]`.
///
/// The input contract promises non-decreasing timestamps. The sampler still defends against
/// malformed/non-finite values because animation math must never put NaN into an SCNNode:
/// coordinates fall back to the last finite coordinate (or zero), and a backwards/non-finite
/// timestamp is clamped to the preceding timestamp. Input order is never rearranged.
nonisolated struct PathSampler {
    static let motionEpsilon = 1e-9

    /// A compact view used by GaitPhaseLock. It deliberately exposes only ground-motion facts,
    /// keeping gait math from learning anything about routing or floors.
    struct MotionSegment: Equatable {
        var startTime: Double
        var endTime: Double
        var duration: Double
        var distance: Double
        var speed: Double
        var isFloorTransition: Bool
    }

    private struct Step: Equatable {
        var position: PathPosition
        var floorID: String
        var time: Double
        var kind: String
    }

    private let steps: [Step]
    private let cumulativeDistances: [Double]
    private let vertexHeadings: [Double]
    private let segmentHeadings: [Double?]
    private let headingSmoothingFraction: Double

    let motionSegments: [MotionSegment]

    var startTime: Double? { steps.first?.time }
    var endTime: Double? { steps.last?.time }
    var totalGroundDistance: Double { cumulativeDistances.last ?? 0 }

    /// `headingSmoothingFraction` is the fraction at each end of a moving segment used to
    /// ease between the corner's circular-mean heading and the segment's true tangent.
    /// Values are clamped to 0...0.5. A stationary segment smoothly bridges its endpoint
    /// headings across the whole interval.
    init(steps rawSteps: [TimedStep], headingSmoothingFraction: Double = 0.22) {
        var sanitized: [Step] = []
        sanitized.reserveCapacity(rawSteps.count)

        for raw in rawSteps {
            let previous = sanitized.last
            let x = raw.x.isFinite ? raw.x : (previous?.position.x ?? 0)
            let y = raw.y.isFinite ? raw.y : (previous?.position.y ?? 0)
            let proposedTime = raw.t_s.isFinite ? raw.t_s : (previous?.time ?? 0)
            let time = max(previous?.time ?? proposedTime, proposedTime)
            sanitized.append(Step(position: PathPosition(x: x, y: y),
                                  floorID: raw.floor_id,
                                  time: time,
                                  kind: raw.kind))
        }
        steps = sanitized

        var distances: [Double] = sanitized.isEmpty ? [] : [0]
        var segments: [MotionSegment] = []
        var headings: [Double?] = []
        segments.reserveCapacity(max(0, sanitized.count - 1))
        headings.reserveCapacity(max(0, sanitized.count - 1))

        if sanitized.count >= 2 {
            for index in 0..<(sanitized.count - 1) {
                let a = sanitized[index]
                let b = sanitized[index + 1]
                let dx = b.position.x - a.position.x
                let dy = b.position.y - a.position.y
                let distance = Self.finiteHypot(dx, dy)
                let duration = max(0, b.time - a.time)
                let speed = duration > Self.motionEpsilon ? distance / duration : 0
                let nextCumulative = distances[index] + distance
                distances.append(nextCumulative.isFinite ? nextCumulative : distances[index])
                segments.append(MotionSegment(startTime: a.time,
                                              endTime: b.time,
                                              duration: duration,
                                              distance: distance,
                                              speed: speed.isFinite ? speed : 0,
                                              isFloorTransition: a.floorID != b.floorID))
                headings.append(distance > Self.motionEpsilon
                                ? Self.normalizedAngle(atan2(dy, dx))
                                : nil)
            }
        }
        cumulativeDistances = distances
        motionSegments = segments
        segmentHeadings = headings
        vertexHeadings = Self.makeVertexHeadings(stepCount: sanitized.count,
                                                 segmentHeadings: headings)
        self.headingSmoothingFraction = headingSmoothingFraction.isFinite
            ? min(max(headingSmoothingFraction, 0), 0.5)
            : 0.22
    }

    /// Sample at modeled time. Empty tracks return nil; all other tracks return finite math.
    func sample(at requestedTime: Double) -> PathSample? {
        guard let first = steps.first else { return nil }
        let lastIndex = steps.count - 1
        let last = steps[lastIndex]
        let time = sanitizedQueryTime(requestedTime, start: first.time, end: last.time)
        let before = requestedTime == -.infinity || (requestedTime.isFinite && requestedTime < first.time)
        let after = requestedTime == .infinity || (requestedTime.isFinite && requestedTime > last.time)

        guard steps.count >= 2 else {
            return PathSample(position: first.position,
                              heading: vertexHeadings.first ?? 0,
                              floorID: first.floorID,
                              kind: first.kind,
                              segmentIndex: nil,
                              segmentProgress: after ? 1 : 0,
                              floorTransition: nil,
                              groundSpeed: 0,
                              groundDistance: 0,
                              isBeforeStart: before,
                              isAfterEnd: after,
                              hasReachedEnd: time >= first.time && !before)
        }

        if before || time < first.time {
            return endpointSample(stepIndex: 0, before: true, after: false,
                                  hasReachedEnd: false)
        }
        if after || time >= last.time {
            return endpointSample(stepIndex: lastIndex, before: false, after: after,
                                  hasReachedEnd: true)
        }

        // Upper bound makes exact interior timestamps activate their destination step. If
        // several steps share a timestamp, every zero-duration hop is consumed atomically and
        // sampling continues from the final duplicate; there is no division by zero.
        let upper = upperBound(for: time)
        let segmentIndex = min(max(upper - 1, 0), motionSegments.count - 1)
        let a = steps[segmentIndex]
        let b = steps[segmentIndex + 1]
        let segment = motionSegments[segmentIndex]
        let progress = segment.duration > Self.motionEpsilon
            ? Self.clampedUnit((time - a.time) / segment.duration)
            : 1
        let position = PathPosition(
            x: Self.lerp(a.position.x, b.position.x, progress),
            y: Self.lerp(a.position.y, b.position.y, progress)
        )
        let crossing = a.floorID == b.floorID ? nil : FloorTransition(
            fromFloorID: a.floorID,
            toFloorID: b.floorID,
            progress: progress
        )

        let traveled = cumulativeDistances[segmentIndex] + segment.distance * progress
        return PathSample(position: position,
                          heading: smoothedHeading(segmentIndex: segmentIndex,
                                                   progress: progress),
                          floorID: a.floorID,
                          kind: a.kind,
                          segmentIndex: segmentIndex,
                          segmentProgress: progress,
                          floorTransition: crossing,
                          groundSpeed: segment.speed,
                          groundDistance: traveled.isFinite
                            ? traveled : cumulativeDistances[segmentIndex],
                          isBeforeStart: false,
                          isAfterEnd: false,
                          hasReachedEnd: false)
    }

    // MARK: - Boundaries and lookup

    private func endpointSample(stepIndex: Int,
                                before: Bool,
                                after: Bool,
                                hasReachedEnd: Bool) -> PathSample {
        let step = steps[stepIndex]
        let isLast = stepIndex == steps.count - 1
        return PathSample(position: step.position,
                          heading: vertexHeadings[stepIndex],
                          floorID: step.floorID,
                          kind: step.kind,
                          segmentIndex: isLast ? motionSegments.indices.last : 0,
                          segmentProgress: isLast ? 1 : 0,
                          floorTransition: nil,
                          groundSpeed: 0,
                          groundDistance: cumulativeDistances[stepIndex],
                          isBeforeStart: before,
                          isAfterEnd: after,
                          hasReachedEnd: hasReachedEnd)
    }

    /// First index whose timestamp is greater than `time`.
    private func upperBound(for time: Double) -> Int {
        var low = 0
        var high = steps.count
        while low < high {
            let mid = low + (high - low) / 2
            if steps[mid].time <= time { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func sanitizedQueryTime(_ time: Double, start: Double, end: Double) -> Double {
        if time.isNaN { return start }
        if time == -.infinity { return start - 1 }
        if time == .infinity { return end + 1 }
        return time
    }

    // MARK: - Circular heading smoothing

    private func smoothedHeading(segmentIndex: Int, progress: Double) -> Double {
        let startHeading = vertexHeadings[segmentIndex]
        let endHeading = vertexHeadings[segmentIndex + 1]
        guard let tangent = segmentHeadings[segmentIndex] else {
            return Self.circularLerp(startHeading, endHeading, Self.smoothstep(progress))
        }
        let fraction = headingSmoothingFraction
        guard fraction > Self.motionEpsilon else { return tangent }

        if progress < fraction {
            return Self.circularLerp(startHeading, tangent,
                                     Self.smoothstep(progress / fraction))
        }
        if progress > 1 - fraction {
            return Self.circularLerp(tangent, endHeading,
                                     Self.smoothstep((progress - (1 - fraction)) / fraction))
        }
        return tangent
    }

    private static func makeVertexHeadings(stepCount: Int,
                                           segmentHeadings: [Double?]) -> [Double] {
        guard stepCount > 0 else { return [] }
        var result: [Double] = []
        result.reserveCapacity(stepCount)

        for vertex in 0..<stepCount {
            var incoming: Double?
            if vertex > 0 {
                for index in stride(from: vertex - 1, through: 0, by: -1) {
                    if let heading = segmentHeadings[index] {
                        incoming = heading
                        break
                    }
                }
            }

            var outgoing: Double?
            if vertex < segmentHeadings.count {
                for index in vertex..<segmentHeadings.count {
                    if let heading = segmentHeadings[index] {
                        outgoing = heading
                        break
                    }
                }
            }

            switch (incoming, outgoing) {
            case let (before?, after?):
                result.append(circularLerp(before, after, 0.5))
            case let (before?, nil):
                result.append(before)
            case let (nil, after?):
                result.append(after)
            case (nil, nil):
                result.append(0)
            }
        }
        return result
    }

    static func normalizedAngle(_ angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        var wrapped = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if wrapped >= .pi { wrapped -= 2 * .pi }
        if wrapped < -.pi { wrapped += 2 * .pi }
        return wrapped == -0 ? 0 : wrapped
    }

    static func circularLerp(_ a: Double, _ b: Double, _ amount: Double) -> Double {
        let start = normalizedAngle(a)
        let delta = atan2(sin(b - start), cos(b - start))
        return normalizedAngle(start + delta * clampedUnit(amount))
    }

    private static func smoothstep(_ value: Double) -> Double {
        let t = clampedUnit(value)
        return t * t * (3 - 2 * t)
    }

    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func lerp(_ a: Double, _ b: Double, _ amount: Double) -> Double {
        let t = clampedUnit(amount)
        if t <= 0 { return a }
        if t >= 1 { return b }
        // Weighted endpoints avoid overflow in `(b - a)` when two individually finite values
        // sit near opposite Double limits. Malformed astronomical geometry still degrades to a
        // finite endpoint rather than handing NaN to the renderer.
        let value = a * (1 - t) + b * t
        return value.isFinite ? value : (t < 0.5 ? a : b)
    }

    private static func finiteHypot(_ x: Double, _ y: Double) -> Double {
        let value = hypot(x, y)
        return value.isFinite ? value : 0
    }
}
