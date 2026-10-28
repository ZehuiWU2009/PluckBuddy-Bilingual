//
//  PluckBuddyTests.swift
//  PluckBuddyTests
//
//  Created by 吴泽荟 on 2026/7/15.
//

import Testing
import CoreGraphics
@testable import PluckBuddy

struct PluckBuddyTests {

    @Test func pluckAlternationIsNotClassifiedAsRoll() {
        let classifier = TechniqueClassifier()
        let features = makeFeatures(
            speeds: [0.45, 0.40, 0.05, 0.04, 0.03],
            pattern: [0, 1, 0, 1]
        )

        #expect(classifier.classify(features: features) == .pluck)
    }

    @Test func fullFingerSequenceIsClassifiedAsRoll() {
        let classifier = TechniqueClassifier()
        let features = makeFeatures(
            speeds: [0.45, 0.44, 0.43, 0.42, 0.10],
            pattern: [0, 1, 2, 3]
        )

        #expect(classifier.classify(features: features) == .roll)
    }

    @Test func ambiguousMotionStaysUnknown() {
        let classifier = TechniqueClassifier()
        let features = makeFeatures(
            speeds: [0.20, 0.20, 0.20, 0.20, 0.20],
            pattern: [0, 2]
        )

        #expect(classifier.classify(features: features) == .unknown)
    }

    @Test func evenRollScoresHighDespiteSingleMissedOnset() {
        let score = RollUniformityScorer.score(
            intervals: [0.100, 0.102, 0.098, 0.101, 0.200, 0.099, 0.101]
        )

        #expect(score > 0.95)
    }

    @Test func genuinelyUnevenRollScoresLower() {
        let score = RollUniformityScorer.score(
            intervals: [0.060, 0.140, 0.075, 0.125, 0.090, 0.115]
        )

        #expect(score < 0.90)
    }

    private func makeFeatures(speeds: [Double], pattern: [Int]) -> HandMotionFeatures {
        HandMotionFeatures(
            fingerTipPositions: Array(repeating: .zero, count: 5),
            wristPosition: .zero,
            fingerVelocities: speeds.map { CGVector(dx: $0, dy: 0) },
            wristVelocity: .zero,
            tigerMouthAngle: 40,
            wristAngle: 0,
            movementFrequency: 0.2,
            sequencePattern: pattern
        )
    }

}
