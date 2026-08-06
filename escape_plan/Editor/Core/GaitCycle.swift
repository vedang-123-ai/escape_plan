//  GaitCycle.swift
//  Foundation-only procedural locomotion curves and deterministic foot-plant phase locking.
//
//  Angles are additive rig rotations in radians. Distances are plan meters and cadence is a
//  complete left-to-left gait cycle per second (two footfalls for a biped). Nothing here owns a
//  clock: callers can scrub to any modeled time and receive exactly the same result.

import Foundation

/// Joint-space output from one procedural gait cycle.
///
/// Biped rigs use shoulders/elbows as arms and hips/knees/ankles as legs. A quadruped maps the
/// shoulder chain to forelegs and the hip chain to hindlegs. Wheelchair rigs ignore leg angles,
/// use the symmetric arm push, and apply `wheelRotation` to both wheels.
nonisolated struct GaitPose: Equatable {
    var leftHip: Double
    var rightHip: Double
    var leftKnee: Double
    var rightKnee: Double
    var leftAnkle: Double
    var rightAnkle: Double

    var leftShoulder: Double
    var rightShoulder: Double
    var leftElbow: Double
    var rightElbow: Double

    var spinePitch: Double
    var spineTwist: Double
    var torsoBob: Double
    var pelvisCounterRotation: Double

    /// Additive wheel angle for wheelchair rigs. One phase advances one full revolution.
    var wheelRotation: Double
    /// Optional quadruped tail yaw; zero for every other locomotion style.
    var tailSwing: Double

    static let zero = GaitPose(leftHip: 0, rightHip: 0,
                               leftKnee: 0, rightKnee: 0,
                               leftAnkle: 0, rightAnkle: 0,
                               leftShoulder: 0, rightShoulder: 0,
                               leftElbow: 0, rightElbow: 0,
                               spinePitch: 0, spineTwist: 0,
                               torsoBob: 0, pelvisCounterRotation: 0,
                               wheelRotation: 0, tailSwing: 0)

    var allValues: [Double] {
        [leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle,
         leftShoulder, rightShoulder, leftElbow, rightElbow,
         spinePitch, spineTwist, torsoBob, pelvisCounterRotation,
         wheelRotation, tailSwing]
    }
}

/// One configurable family of periodic joint curves.
nonisolated struct GaitCycle: Equatable {
    enum LocomotionStyle: Equatable {
        case biped
        case wheelchair
        case quadruped
    }

    /// Full-cycle travel at or above nominal speed, in meters.
    var strideLength: Double
    /// Desired full gait cycles per second at lower speeds.
    var cadence: Double
    /// Overall joint-curve multiplier. Zero leaves only the style's neutral posture.
    var amplitude: Double
    var style: LocomotionStyle

    /// Cross-floor segments have no horizontal arc length. Their phase therefore advances from
    /// the engine-provided interval, at a shorter, slower step than level travel. These values
    /// affect animation only and never add geometry or retime the route.
    var stairStrideScale: Double
    var stairCadenceScale: Double

    private var hipSwing: Double
    private var kneeLift: Double
    private var ankleFlex: Double
    private var shoulderSwing: Double
    private var elbowBend: Double
    private var spineLean: Double
    private var bobHeight: Double
    private var pelvisTwist: Double

    init(strideLength: Double,
         cadence: Double,
         amplitude: Double,
         style: LocomotionStyle = .biped,
         stairStrideScale: Double = 0.46,
         stairCadenceScale: Double = 0.82,
         hipSwing: Double = 0.58,
         kneeLift: Double = 0.72,
         ankleFlex: Double = 0.24,
         shoulderSwing: Double = 0.48,
         elbowBend: Double = 0.58,
         spineLean: Double = 0.10,
         bobHeight: Double = 0.045,
         pelvisTwist: Double = 0.13) {
        self.strideLength = Self.clampedFinite(strideLength, to: 0...10)
        self.cadence = Self.clampedFinite(cadence, to: 0...12)
        self.amplitude = Self.clampedFinite(amplitude, to: 0...4)
        self.style = style
        self.stairStrideScale = Self.clampedFinite(stairStrideScale, to: 0...1)
        self.stairCadenceScale = Self.clampedFinite(stairCadenceScale, to: 0...2)
        self.hipSwing = Self.clampedFinite(hipSwing, to: 0...2)
        self.kneeLift = Self.clampedFinite(kneeLift, to: 0...2)
        self.ankleFlex = Self.clampedFinite(ankleFlex, to: 0...1)
        self.shoulderSwing = Self.clampedFinite(shoulderSwing, to: 0...2)
        self.elbowBend = Self.clampedFinite(elbowBend, to: 0...2)
        self.spineLean = Self.clampedFinite(spineLean, to: -1...1)
        self.bobHeight = Self.clampedFinite(bobHeight, to: 0...0.3)
        self.pelvisTwist = Self.clampedFinite(pelvisTwist, to: 0...1)
    }

    init(kind: GaitKind) {
        self = Self.configuration(for: kind)
    }

    /// Visibly distinct, scale-appropriate defaults for each engine gait tag.
    static func configuration(for kind: GaitKind) -> GaitCycle {
        switch kind {
        case .adult, .unknown:
            return GaitCycle(strideLength: 1.10, cadence: 1.55, amplitude: 1.0)
        case .child:
            return GaitCycle(strideLength: 0.72, cadence: 2.15, amplitude: 0.92,
                             hipSwing: 0.62, kneeLift: 0.78,
                             shoulderSwing: 0.52, spineLean: 0.08,
                             bobHeight: 0.038, pelvisTwist: 0.14)
        case .elderly:
            return GaitCycle(strideLength: 0.58, cadence: 1.08, amplitude: 0.58,
                             stairStrideScale: 0.38, stairCadenceScale: 0.68,
                             hipSwing: 0.44, kneeLift: 0.43, ankleFlex: 0.15,
                             shoulderSwing: 0.20, elbowBend: 0.42,
                             spineLean: 0.16, bobHeight: 0.022, pelvisTwist: 0.07)
        case .wheelchair:
            return GaitCycle(strideLength: 1.28, cadence: 1.02, amplitude: 0.88,
                             style: .wheelchair,
                             stairStrideScale: 0.30, stairCadenceScale: 0.55,
                             hipSwing: 0, kneeLift: 0, ankleFlex: 0,
                             shoulderSwing: 0.52, elbowBend: 0.86,
                             spineLean: 0.10, bobHeight: 0.012, pelvisTwist: 0)
        case .pet:
            return GaitCycle(strideLength: 0.54, cadence: 2.55, amplitude: 0.86,
                             style: .quadruped,
                             hipSwing: 0.48, kneeLift: 0.62, ankleFlex: 0.18,
                             shoulderSwing: 0.48, elbowBend: 0.62,
                             spineLean: 0, bobHeight: 0.026, pelvisTwist: 0.10)
        }
    }

    /// The distance covered by one cycle at `groundSpeed`.
    ///
    /// At low speed the stride shortens to `speed / cadence`, preserving the configured rhythm
    /// without foot skating. At high speed it caps at the morphology's nominal stride and the
    /// cadence is allowed to rise. Zero speed always produces zero stride and a planted pose.
    func effectiveStrideLength(for groundSpeed: Double) -> Double {
        guard groundSpeed.isFinite,
              groundSpeed > PathSampler.motionEpsilon,
              strideLength > PathSampler.motionEpsilon,
              cadence > PathSampler.motionEpsilon else { return 0 }
        return min(strideLength, groundSpeed / cadence)
    }

    /// Procedural pose at any phase. `phase` wraps, so negative values and values above one are
    /// valid. Supplying the phase lock's effective stride scales joint reach down for shuffling
    /// or stairs while retaining exact phase continuity.
    func pose(at phase: Double, effectiveStrideLength: Double? = nil) -> GaitPose {
        let p = Self.normalizedPhase(phase)
        let strideScale: Double
        if let effectiveStrideLength {
            guard effectiveStrideLength.isFinite,
                  effectiveStrideLength > PathSampler.motionEpsilon,
                  strideLength > PathSampler.motionEpsilon else {
                return neutralPose(at: p)
            }
            strideScale = min(max(effectiveStrideLength / strideLength, 0), 1.25)
        } else {
            strideScale = 1
        }
        let strength = amplitude * strideScale

        switch style {
        case .biped:
            return bipedPose(phase: p, strength: strength)
        case .wheelchair:
            return wheelchairPose(phase: p, strength: strength)
        case .quadruped:
            return quadrupedPose(phase: p, strength: strength)
        }
    }

    // MARK: - Curves

    private func bipedPose(phase: Double, strength: Double) -> GaitPose {
        let theta = 2 * Double.pi * phase
        let leftStride = cos(theta)
        let rightStride = -leftStride
        let leftSwing = max(0, -leftStride)
        let rightSwing = max(0, -rightStride)
        let bob = bobHeight * strength * (0.5 - 0.5 * cos(2 * theta))
        let pelvis = -pelvisTwist * strength * sin(theta)

        return GaitPose(
            leftHip: hipSwing * strength * leftStride,
            rightHip: hipSwing * strength * rightStride,
            leftKnee: kneeLift * strength * leftSwing,
            rightKnee: kneeLift * strength * rightSwing,
            leftAnkle: -ankleFlex * strength * sin(theta),
            rightAnkle: ankleFlex * strength * sin(theta),
            leftShoulder: -shoulderSwing * strength * leftStride,
            rightShoulder: -shoulderSwing * strength * rightStride,
            leftElbow: elbowBend + 0.16 * strength * max(0, leftStride),
            rightElbow: elbowBend + 0.16 * strength * max(0, rightStride),
            spinePitch: spineLean + 0.025 * strength * sin(2 * theta),
            spineTwist: -0.55 * pelvis,
            torsoBob: bob,
            pelvisCounterRotation: pelvis,
            wheelRotation: 0,
            tailSwing: 0
        )
    }

    private func wheelchairPose(phase: Double, strength: Double) -> GaitPose {
        let theta = 2 * Double.pi * phase
        // Both hands push together through the lower half, then elbows fold for recovery.
        let push = 0.5 - 0.5 * cos(theta)
        let armStrength = min(max(strength, 0), 1.25)
        return GaitPose(
            leftHip: 0, rightHip: 0,
            leftKnee: 0, rightKnee: 0,
            leftAnkle: 0, rightAnkle: 0,
            leftShoulder: shoulderSwing * strength * (0.5 - push),
            rightShoulder: shoulderSwing * strength * (0.5 - push),
            leftElbow: elbowBend * (1 - 0.65 * armStrength * push),
            rightElbow: elbowBend * (1 - 0.65 * armStrength * push),
            spinePitch: spineLean + 0.035 * strength * push,
            spineTwist: 0,
            torsoBob: bobHeight * strength * push,
            pelvisCounterRotation: 0,
            wheelRotation: -2 * .pi * phase,
            tailSwing: 0
        )
    }

    private func quadrupedPose(phase: Double, strength: Double) -> GaitPose {
        let theta = 2 * Double.pi * phase
        let leftHind = cos(theta)
        let rightHind = -leftHind
        // Trot: diagonal fore/hind pairs move together.
        let leftFore = rightHind
        let rightFore = leftHind
        let bob = bobHeight * strength * (0.5 - 0.5 * cos(2 * theta))
        let pelvis = -pelvisTwist * strength * sin(theta)

        return GaitPose(
            leftHip: hipSwing * strength * leftHind,
            rightHip: hipSwing * strength * rightHind,
            leftKnee: kneeLift * strength * max(0, -leftHind),
            rightKnee: kneeLift * strength * max(0, -rightHind),
            leftAnkle: -ankleFlex * strength * sin(theta),
            rightAnkle: ankleFlex * strength * sin(theta),
            leftShoulder: shoulderSwing * strength * leftFore,
            rightShoulder: shoulderSwing * strength * rightFore,
            leftElbow: elbowBend * strength * max(0, -leftFore),
            rightElbow: elbowBend * strength * max(0, -rightFore),
            spinePitch: spineLean,
            spineTwist: -0.45 * pelvis,
            torsoBob: bob,
            pelvisCounterRotation: pelvis,
            wheelRotation: 0,
            tailSwing: 0.30 * strength * sin(theta + .pi / 2)
        )
    }

    private func neutralPose(at phase: Double) -> GaitPose {
        switch style {
        case .biped:
            var pose = GaitPose.zero
            pose.leftElbow = elbowBend
            pose.rightElbow = elbowBend
            pose.spinePitch = spineLean
            return pose
        case .wheelchair:
            var pose = GaitPose.zero
            pose.leftElbow = elbowBend
            pose.rightElbow = elbowBend
            pose.spinePitch = spineLean
            pose.wheelRotation = -2 * .pi * phase
            return pose
        case .quadruped:
            var pose = GaitPose.zero
            pose.spinePitch = spineLean
            return pose
        }
    }

    private static func normalizedPhase(_ phase: Double) -> Double {
        guard phase.isFinite else { return 0 }
        let wrapped = phase - floor(phase)
        return wrapped == -0 ? 0 : wrapped
    }

    private static func clampedFinite(_ value: Double,
                                      to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// What drives phase on the active segment. This makes the deliberate stair exception to
/// horizontal foot locking explicit to the renderer and to tests.
nonisolated enum GaitPhaseSource: Equatable {
    case idle
    case groundDistance
    case floorTransition
}

nonisolated struct GaitPhaseSample: Equatable {
    /// Wrapped to 0..<1 for direct use with GaitCycle.pose.
    var phase: Double
    /// Unwrapped and monotonic across the path; useful for testing and wheel continuity.
    var cycleCount: Double
    var effectiveStrideLength: Double
    var cadence: Double
    var groundSpeed: Double
    var source: GaitPhaseSource

    var isMoving: Bool { source != .idle }
}

/// Stateless-at-sample-time phase locking for deterministic forward playback and scrubbing.
///
/// Level segments advance by `distance / effectiveStrideLength`, where effective stride is
/// derived from actual ground speed. Same-floor dwells freeze. A cross-floor segment instead
/// advances by its supplied duration at reduced stair cadence because its x/y arc length is
/// necessarily zero; this drives a short stepping pose without inventing any route geometry.
nonisolated struct GaitPhaseLock {
    private let sampler: PathSampler
    private let cycle: GaitCycle
    private let cumulativeCycles: [Double]
    private let segmentCycles: [Double]
    private let segmentStrides: [Double]
    private let segmentCadences: [Double]
    private let segmentSources: [GaitPhaseSource]

    init(sampler: PathSampler, cycle: GaitCycle) {
        self.sampler = sampler
        self.cycle = cycle

        var cumulative = [0.0]
        var deltas: [Double] = []
        var strides: [Double] = []
        var cadences: [Double] = []
        var sources: [GaitPhaseSource] = []
        deltas.reserveCapacity(sampler.motionSegments.count)
        strides.reserveCapacity(sampler.motionSegments.count)
        cadences.reserveCapacity(sampler.motionSegments.count)
        sources.reserveCapacity(sampler.motionSegments.count)

        for segment in sampler.motionSegments {
            let delta: Double
            let stride: Double
            let cadence: Double
            let source: GaitPhaseSource

            if segment.isFloorTransition && segment.duration > PathSampler.motionEpsilon {
                stride = cycle.strideLength * cycle.stairStrideScale
                cadence = cycle.cadence * cycle.stairCadenceScale
                delta = segment.duration * cadence
                source = cadence > PathSampler.motionEpsilon ? .floorTransition : .idle
            } else if segment.distance > PathSampler.motionEpsilon {
                let derived = cycle.effectiveStrideLength(for: segment.speed)
                // A zero-duration malformed hop has no speed to derive from. Consume it with
                // nominal stride at the atomic timestamp, preserving finite distance phase.
                stride = derived > PathSampler.motionEpsilon ? derived : cycle.strideLength
                delta = stride > PathSampler.motionEpsilon ? segment.distance / stride : 0
                cadence = segment.duration > PathSampler.motionEpsilon
                    ? delta / segment.duration : 0
                source = delta > PathSampler.motionEpsilon ? .groundDistance : .idle
            } else {
                delta = 0
                stride = 0
                cadence = 0
                source = .idle
            }

            let finiteDelta = delta.isFinite ? max(0, delta) : 0
            deltas.append(finiteDelta)
            strides.append(stride.isFinite ? max(0, stride) : 0)
            cadences.append(cadence.isFinite ? max(0, cadence) : 0)
            sources.append(source)
            let nextCumulative = cumulative[cumulative.count - 1] + finiteDelta
            cumulative.append(nextCumulative.isFinite
                              ? nextCumulative : cumulative[cumulative.count - 1])
        }

        cumulativeCycles = cumulative
        segmentCycles = deltas
        segmentStrides = strides
        segmentCadences = cadences
        segmentSources = sources
    }

    init(steps: [TimedStep], cycle: GaitCycle,
         headingSmoothingFraction: Double = 0.22) {
        self.init(sampler: PathSampler(steps: steps,
                                      headingSmoothingFraction: headingSmoothingFraction),
                  cycle: cycle)
    }

    func sample(at time: Double) -> GaitPhaseSample {
        guard let path = sampler.sample(at: time) else {
            return GaitPhaseSample(phase: 0, cycleCount: 0,
                                   effectiveStrideLength: 0, cadence: 0,
                                   groundSpeed: 0, source: .idle)
        }
        return sample(for: path)
    }

    /// Avoids a second path lookup when the renderer already sampled this lock's PathSampler.
    func sample(for path: PathSample) -> GaitPhaseSample {
        guard let segmentIndex = path.segmentIndex,
              segmentCycles.indices.contains(segmentIndex) else {
            return GaitPhaseSample(phase: 0, cycleCount: 0,
                                   effectiveStrideLength: 0, cadence: 0,
                                   groundSpeed: 0, source: .idle)
        }

        if path.isBeforeStart {
            return GaitPhaseSample(phase: 0, cycleCount: 0,
                                   effectiveStrideLength: 0, cadence: 0,
                                   groundSpeed: 0, source: .idle)
        }

        let terminal = path.hasReachedEnd || path.isAfterEnd
        let cycles = terminal
            ? (cumulativeCycles.last ?? 0)
            : cumulativeCycles[segmentIndex]
                + segmentCycles[segmentIndex] * path.segmentProgress
        let finiteCycles = cycles.isFinite ? max(0, cycles) : 0
        let phase = finiteCycles - floor(finiteCycles)

        return GaitPhaseSample(
            phase: phase,
            cycleCount: finiteCycles,
            effectiveStrideLength: terminal ? 0 : segmentStrides[segmentIndex],
            cadence: terminal ? 0 : segmentCadences[segmentIndex],
            groundSpeed: terminal ? 0 : path.groundSpeed,
            source: terminal ? .idle : segmentSources[segmentIndex]
        )
    }

    func phase(at time: Double) -> Double { sample(at: time).phase }
}
