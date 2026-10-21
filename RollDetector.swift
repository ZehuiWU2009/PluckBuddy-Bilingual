//
//  RollDetector.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/7/16.
//

import Foundation
import AVFoundation
import Accelerate

/// 轮指检测器 - 检测连续快速的弹拨动作
class RollDetector {
    
    // MARK: - Configuration
    private let sampleRate: Double
    /// 绝对下限：保证极轻的拨弦也能被识别（线性幅度，约 -34 dBFS）
    private let baseThreshold: Float = 0.02
    /// 自适应阈值 = 噪声底 × 该倍数，使灵敏度不依赖设备/麦克风增益
    private let noiseMargin: Float = 4.0
    /// 噪声底指数平滑系数（慢速更新，避免被乐音抬高）
    private let noiseFloorAlpha: Float = 0.004
    /// 释放迟滞：电平须回落到阈值的该比例以下才允许下一次触发，避免单个衰减音被重复计数
    private let releaseHysteresis: Float = 0.4
    private let minRollInterval: Double = 0.05 // 最小间隔 50ms（20 次/秒）
    private let maxRollInterval: Double = 0.15 // 最大间隔 150ms（6.7 次/秒）
    private let rollSequenceMinCount = 4 // 至少连续 4 次才算轮指
    
    // MARK: - State
    private var noiseFloor: Float = 0.01 // 环境噪声底估计
    private var armed: Bool = true // Schmitt 触发：是否允许下一次音符检测
    private var lastDetectionTime: Date?
    private var currentSequence: [RollNote] = [] // 当前轮指序列
    private var rollSpeed: Double = 0 // 轮指速度（次/秒）
    /// 最近一次有效阈值（调试用）
    private(set) var lastEffectiveThreshold: Float = 0.02
    
    // MARK: - Callbacks
    var onRollDetected: ((RollEvent) -> Void)?
    var onRollSequenceComplete: ((RollSequence) -> Void)?
    
    // MARK: - Initialization
    init(sampleRate: Double = 48000.0) {
        self.sampleRate = sampleRate
    }
    
    // MARK: - Detection
    /// 检测轮指动作
    func detectRoll(from buffer: AVAudioPCMBuffer) -> RollEvent? {
        guard let channelData = buffer.floatChannelData?[0] else {
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }
        
        // 1️⃣ 计算峰值振幅
        var peak: Float = 0.0
        vDSP_maxv(channelData, 1, &peak, vDSP_Length(frameLength))
        
        // 自适应阈值：噪声底随环境缓慢更新；有效阈值 = max(绝对下限, 噪声底 × 倍数)
        let threshold = max(baseThreshold, noiseFloor * noiseMargin)
        lastEffectiveThreshold = threshold
        // 仅当信号明显低于阈值时更新噪声底，避免被乐音拉高
        if peak < threshold * 0.4 {
            noiseFloor = noiseFloor * (1 - noiseFloorAlpha) + peak * noiseFloorAlpha
        }
        
        // 释放迟滞：电平回落到阈值以下后才重新“武装”，避免同一衰减音被重复计数
        if peak < threshold * releaseHysteresis {
            armed = true
        }
        
        // 2️⃣ 阈值判定（带 Schmitt 触发）
        guard peak > threshold, armed else {
            // 一段时间没有检测到，结束当前序列
            checkSequenceTimeout()
            return nil
        }
        armed = false
        
        // 3️⃣ 检查时间间隔
        let now = Date()
        var interval: Double = 0
        
        if let lastTime = lastDetectionTime {
            interval = now.timeIntervalSince(lastTime)
            
            // 间隔太短或太长，都不是有效轮指
            guard interval >= minRollInterval && interval <= maxRollInterval else {
                if interval > maxRollInterval {
                    // 间隔太长，结束序列
                    completeCurrentSequence()
                }
                return nil
            }
        }
        
        lastDetectionTime = now
        
        // 4️⃣ 创建轮指音符
        let note = RollNote(
            timestamp: now,
            amplitude: peak,
            interval: interval
        )
        
        // 5️⃣ 添加到当前序列
        currentSequence.append(note)
        
        // 6️⃣ 计算轮指速度
        if currentSequence.count >= 2 {
            let intervals = currentSequence.suffix(5).dropFirst().map { $0.interval }
            let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
            rollSpeed = avgInterval > 0 ? 1.0 / avgInterval : 0
        }
        
        // 7️⃣ 创建事件
        let event = RollEvent(
            note: note,
            sequenceLength: currentSequence.count,
            currentSpeed: rollSpeed,
            isValidSequence: currentSequence.count >= rollSequenceMinCount
        )
        
        onRollDetected?(event)
        return event
    }
    
    // MARK: - Sequence Management
    
    /// 检查序列是否超时
    private func checkSequenceTimeout() {
        guard let lastTime = lastDetectionTime else { return }
        
        let timeSinceLastNote = Date().timeIntervalSince(lastTime)
        if timeSinceLastNote > maxRollInterval {
            completeCurrentSequence()
        }
    }
    
    /// 完成当前轮指序列
    private func completeCurrentSequence() {
        guard currentSequence.count >= rollSequenceMinCount else {
            currentSequence.removeAll()
            return
        }
        
        let sequence = RollSequence(
            notes: currentSequence,
            startTime: currentSequence.first!.timestamp,
            endTime: currentSequence.last!.timestamp,
            averageSpeed: calculateAverageSpeed(),
            uniformity: calculateUniformity()
        )
        
        onRollSequenceComplete?(sequence)
        currentSequence.removeAll()
    }
    
    /// 手动结束序列（练习结束时调用）
    func finishSequence() {
        completeCurrentSequence()
    }
    
    // MARK: - Analysis
    
    /// 计算平均速度（次/秒）
    private func calculateAverageSpeed() -> Double {
        guard currentSequence.count >= 2 else { return 0 }
        
        let totalDuration = currentSequence.last!.timestamp.timeIntervalSince(currentSequence.first!.timestamp)
        return Double(currentSequence.count - 1) / totalDuration
    }
    
    /// 计算均匀度（0-1，1 表示完美均匀）
    private func calculateUniformity() -> Double {
        guard currentSequence.count >= 3 else { return 0 }
        
        let intervals = currentSequence.dropFirst().map { $0.interval }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        
        guard mean > 0 else { return 0 }
        
        let variance = intervals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(intervals.count)
        let stdDev = sqrt(variance)
        
        // 变异系数（越小越均匀）
        let cv = stdDev / mean
        
        // 转换为 0-1 分数
        return max(0, min(1, 1.0 - cv * 3))
    }
    
    /// 重置检测器
    func reset() {
        lastDetectionTime = nil
        currentSequence.removeAll()
        rollSpeed = 0
        armed = true
    }
}

// MARK: - RollNote
/// 单个轮指音符
struct RollNote {
    let timestamp: Date
    let amplitude: Float
    let interval: Double // 与上一个音符的间隔（秒）
}

// MARK: - RollEvent
/// 轮指事件（每次检测到轮指音符）
struct RollEvent {
    let note: RollNote
    let sequenceLength: Int // 当前序列长度
    let currentSpeed: Double // 当前速度（次/秒）
    let isValidSequence: Bool // 是否构成有效轮指
}

// MARK: - RollSequence
/// 完整的轮指序列
struct RollSequence {
    let notes: [RollNote]
    let startTime: Date
    let endTime: Date
    let averageSpeed: Double // 平均速度（次/秒）
    let uniformity: Double // 均匀度（0-1）
    
    /// 序列时长
    var duration: TimeInterval {
        return endTime.timeIntervalSince(startTime)
    }
    
    /// 音符数量
    var noteCount: Int {
        return notes.count
    }
    
    /// 质量评级
    var quality: Quality {
        if uniformity > 0.85 && averageSpeed >= 10 {
            return .excellent
        } else if uniformity > 0.7 && averageSpeed >= 8 {
            return .good
        } else if uniformity > 0.5 && averageSpeed >= 6 {
            return .fair
        } else {
            return .needsImprovement
        }
    }
    
    enum Quality {
        case excellent      // 优秀
        case good          // 良好
        case fair          // 一般
        case needsImprovement // 需要改进
        
        var description: String {
            switch self {
            case .excellent: return "优秀"
            case .good: return "良好"
            case .fair: return "一般"
            case .needsImprovement: return "需要改进"
            }
        }
        
        var emoji: String {
            switch self {
            case .excellent: return "🌟"
            case .good: return "👍"
            case .fair: return "👌"
            case .needsImprovement: return "💪"
            }
        }
    }
}
