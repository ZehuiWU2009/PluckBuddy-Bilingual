//
//  TechniqueEvaluators.swift
//  PluckBuddy
//
//  技法评估器集合
//  Created on 2026/8/29.
//

import Foundation
import CoreGraphics

/// 轮指姿势评估器
class RollPostureEvaluator {
    func evaluate(features: HandMotionFeatures) -> PostureEvaluation {
        var aspects: [EvaluationAspect] = []
        
        // 1. 评估手指顺序性（轮指的核心）
        let sequenceScore = evaluateSequence(pattern: features.sequencePattern)
        aspects.append(EvaluationAspect(
            category: .rhythm,
            score: sequenceScore,
            description: sequenceScore >= 80 ? L("手指顺序清晰") : L("注意手指依次拨弦")
        ))
        
        // 2. 评估手腕稳定性
        let wristSpeed = hypot(Double(features.wristVelocity.dx), Double(features.wristVelocity.dy))
        let wristScore = wristSpeed < 0.2 ? 90 : max(50, 90 - wristSpeed * 100)
        aspects.append(EvaluationAspect(
            category: .wristPosition,
            score: wristScore,
            description: wristScore >= 80 ? L("手腕稳定") : L("手腕晃动过大")
        ))
        
        // 3. 评估虎口角度（拇指与食指之间的张开程度）
        let tigerScore = evaluateTigerMouthAngle(degrees: features.tigerMouthAngle)
        aspects.append(EvaluationAspect(
            category: .tigerMouth,
            score: tigerScore,
            description: tigerScore >= 80 ? L("虎口自然张开") : L("调整虎口打开程度")
        ))
        
        // 4. 评估运动流畅度
        let smoothScore = evaluateMovementSmoothness(velocities: features.fingerVelocities)
        aspects.append(EvaluationAspect(
            category: .relaxation,
            score: smoothScore,
            description: smoothScore >= 80 ? L("动作流畅") : L("动作略显僵硬")
        ))
        
        // 计算总分
        let overallScore = aspects.map { $0.score }.reduce(0, +) / Double(aspects.count)
        
        // 生成建议
        var suggestions: [String] = []
        if sequenceScore < 80 {
            suggestions.append(L("练习手指依次拨弦，保持均匀节奏"))
        }
        if wristScore < 80 {
            suggestions.append(L("放松手腕，保持稳定姿势"))
        }
        if tigerScore < 80 {
            suggestions.append(L("调整虎口打开程度，让拇指与食指自然张开"))
        }
        if smoothScore < 80 {
            suggestions.append(L("放松手部肌肉，让动作更流畅"))
        }
        if suggestions.isEmpty {
            suggestions.append(L("继续保持，轮指技法很标准！"))
        }
        
        return PostureEvaluation(
            overallScore: overallScore,
            aspects: aspects,
            suggestions: suggestions
        )
    }
    
    private func evaluateSequence(pattern: [Int]) -> Double {
        guard pattern.count >= 2 else { return 50 }
        
        // 检查是否为连续递增或递减
        var consecutivePairs = 0
        for i in 1..<pattern.count {
            let diff = abs(pattern[i] - pattern[i-1])
            if diff == 1 {
                consecutivePairs += 1
            }
        }
        
        let ratio = Double(consecutivePairs) / Double(pattern.count - 1)
        return min(100, 50 + ratio * 50)
    }
    
    private func evaluateTigerMouthAngle(degrees: Double) -> Double {
        // 虎口打开程度的连续评分（度数）
        // 理想虎口：拇指与食指之间约 30°-50° 的夹角（手腕为参考点）
        let ideal = 40.0
        let diff = abs(degrees - ideal)

        if degrees < 1 {
            // 数据缺失（识别失败/手指未检出）—— 不参与评分
            return 70
        }
        if diff < 10 { return 100 }   // 30-50° 完美
        if diff < 20 { return 85 }    // 20-60° 可接受
        if diff < 30 { return 70 }    // 10-70° 偏离
        return 50                     // 极端
    }
    
    private func evaluateMovementSmoothness(velocities: [CGVector]) -> Double {
        guard velocities.count > 1 else { return 70 }
        
        // 计算速度变化的标准差（越小越流畅）
        let speeds = velocities.map { hypot(Double($0.dx), Double($0.dy)) }
        let avgSpeed = speeds.reduce(0, +) / Double(speeds.count)
        let variance = speeds.map { pow($0 - avgSpeed, 2) }.reduce(0, +) / Double(speeds.count)
        let stdDev = sqrt(variance)
        
        // 标准差越小，分数越高
        return max(50, 100 - stdDev * 100)
    }
}

/// 扫弦姿势评估器
class SweepPostureEvaluator {
    func evaluate(features: HandMotionFeatures) -> PostureEvaluation {
        var aspects: [EvaluationAspect] = []
        
        // 1. 评估整体性（所有手指同时运动）
        let speeds = features.fingerVelocities.map { hypot(Double($0.dx), Double($0.dy)) }
        let avgSpeed = speeds.reduce(0, +) / Double(speeds.count)
        let fastFingers = speeds.filter { $0 > avgSpeed * 0.7 }.count
        let unityScore = Double(fastFingers) / Double(speeds.count) * 100
        aspects.append(EvaluationAspect(
            category: .handShape,
            score: unityScore,
            description: unityScore >= 80 ? L("手指配合协调") : L("注意所有手指同时拨弦")
        ))
        
        // 2. 评估手臂带动
        let wristSpeed = hypot(Double(features.wristVelocity.dx), Double(features.wristVelocity.dy))
        let armScore = wristSpeed > 0.3 ? min(100, wristSpeed * 200) : 50
        aspects.append(EvaluationAspect(
            category: .wristPosition,
            score: armScore,
            description: armScore >= 70 ? L("手臂带动充分") : L("应由手臂带动，而非单纯手指")
        ))
        
        // 3. 评估力度均匀性
        let speedVariance = calculateVariance(speeds)
        let uniformityScore = max(50, 100 - speedVariance * 200)
        aspects.append(EvaluationAspect(
            category: .rhythm,
            score: uniformityScore,
            description: uniformityScore >= 80 ? L("力度均匀") : L("注意保持力度一致")
        ))
        
        // 计算总分
        let overallScore = aspects.map { $0.score }.reduce(0, +) / Double(aspects.count)
        
        // 生成建议
        var suggestions: [String] = []
        if unityScore < 80 {
            suggestions.append(L("让所有手指同时接触琴弦"))
        }
        if armScore < 70 {
            suggestions.append(L("用手臂带动扫弦，而不是单靠手指"))
        }
        if uniformityScore < 80 {
            suggestions.append(L("保持扫弦力度均匀"))
        }
        if suggestions.isEmpty {
            suggestions.append(L("扫弦技法很标准，继续保持！"))
        }
        
        return PostureEvaluation(
            overallScore: overallScore,
            aspects: aspects,
            suggestions: suggestions
        )
    }
    
    private func calculateVariance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let avg = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - avg, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}

/// 弹挑姿势评估器
class PluckPostureEvaluator {
    func evaluate(features: HandMotionFeatures) -> PostureEvaluation {
        var aspects: [EvaluationAspect] = []
        
        // 1. 评估手指独立性（只有1-2个手指活跃）
        let speeds = features.fingerVelocities.map { hypot(Double($0.dx), Double($0.dy)) }
        let activeFingers = speeds.filter { $0 > 0.3 }.count
        let independenceScore = activeFingers <= 2 ? 95 : max(50, 95 - Double(activeFingers - 2) * 15)
        aspects.append(EvaluationAspect(
            category: .handShape,
            score: independenceScore,
            description: independenceScore >= 80 ? L("手指独立性好") : L("注意只用指定手指拨弦")
        ))
        
        // 2. 评估拨弦力度（活跃手指的速度）
        let maxSpeed = speeds.max() ?? 0
        let strengthScore = min(100, maxSpeed * 150)
        aspects.append(EvaluationAspect(
            category: .handShape,
            score: strengthScore,
            description: strengthScore >= 70 ? L("拨弦力度适中") : strengthScore >= 50 ? L("力度偏弱") : L("力度过弱")
        ))
        
        // 3. 评估手腕稳定性
        let wristSpeed = hypot(Double(features.wristVelocity.dx), Double(features.wristVelocity.dy))
        let stabilityScore = wristSpeed < 0.15 ? 95 : max(50, 95 - wristSpeed * 200)
        aspects.append(EvaluationAspect(
            category: .wristPosition,
            score: stabilityScore,
            description: stabilityScore >= 80 ? L("手腕稳定") : L("手腕晃动，应保持稳定")
        ))
        
        // 4. 评估节奏稳定性
        let rhythmScore = evaluateRhythm(frequency: features.movementFrequency)
        aspects.append(EvaluationAspect(
            category: .rhythm,
            score: rhythmScore,
            description: rhythmScore >= 80 ? L("节奏稳定") : L("注意保持节奏均匀")
        ))
        
        // 计算总分
        let overallScore = aspects.map { $0.score }.reduce(0, +) / Double(aspects.count)
        
        // 生成建议
        var suggestions: [String] = []
        if independenceScore < 80 {
            suggestions.append(L("集中使用一根手指，避免其他手指参与"))
        }
        if strengthScore < 70 {
            suggestions.append(L("增加拨弦力度，但不要过于用力"))
        }
        if stabilityScore < 80 {
            suggestions.append(L("保持手腕稳定，动作主要来自手指"))
        }
        if rhythmScore < 80 {
            suggestions.append(L("匀速弹挑，保持节奏感"))
        }
        if suggestions.isEmpty {
            suggestions.append(L("弹挑技法很规范，继续保持！"))
        }
        
        return PostureEvaluation(
            overallScore: overallScore,
            aspects: aspects,
            suggestions: suggestions
        )
    }
    
    private func evaluateRhythm(frequency: Double) -> Double {
        // 理想频率：每秒 2-4 次拨弦
        let idealRange = (0.2...0.4)
        if idealRange.contains(frequency) {
            return 90
        } else if frequency < 0.1 {
            return 60 // 太慢
        } else if frequency > 0.5 {
            return 70 // 太快
        } else {
            return 80
        }
    }
}
