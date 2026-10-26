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
///
/// 实现方式：用「快起慢落」的包络跟随抽取每次拨弦的起音（峰值拾取），
/// 每个被确认的波峰计为一次轮指音符。这样连续轮指（音与音之间几乎没有
/// 静音间隔）也能逐拍数出来，速度（次/秒）和均匀度都会随真实演奏变化。
class RollDetector {
    
    // MARK: - Configuration
    private let sampleRate: Double
    /// 绝对下限：保证极轻的拨弦也能被识别（线性幅度，约 -34 dBFS）
    private let baseThreshold: Float = 0.02
    /// 自适应阈值 = 噪声底 × 该倍数，使灵敏度不依赖设备/麦克风增益
    private let noiseMargin: Float = 4.0
    /// 噪声底指数平滑系数（慢速更新，避免被乐音抬高）
    private let noiseFloorAlpha: Float = 0.004
    /// 包络跟随的衰减时间常数（秒）：决定波峰宽度，20ms 既能贴住单次拨弦，
    /// 又能在两次拨弦之间充分回落，把重叠的音头拆成各自独立的波峰。
    private let envTau: Double = 0.02
    /// 波峰确认条件：包络从其峰值回落到该比例以下，即认为这个音已结束。
    private let peakFallRatio: Float = 0.5
    /// 两次有效起音的最小间隔（秒）：低于此值视为同一次拨弦的重复起音，忽略。
    /// 同时作为轮指速度上限（1/0.035 ≈ 28 次/秒）。
    private let minRollInterval: Double = 0.035
    /// 两次起音的最大间隔（秒）：超过即认为一轮轮指结束、开始新序列（≥4 次/秒）。
    private let maxRollInterval: Double = 0.25
    private let rollSequenceMinCount = 4 // 至少连续 4 次才算轮指
    
    // MARK: - State
    private var noiseFloor: Float = 0.01      // 环境噪声底估计
    private var env: Float = 0                 // 包络跟随状态
    private var peakVal: Float = 0             // 当前正在追踪的波峰高度
    private var peakTime: Double = 0           // 当前波峰对应的累计时间（秒）
    private var lastOnsetElapsed: Double = -1  // 上一次起音的累计时间（秒）
    private var elapsed: Double = 0            // 已处理音频的累计时间（秒）
    private var anchorDate: Date?              // 时间基准
    private var anchorElapsed: Double = 0
    private var currentSequence: [RollNote] = [] // 当前轮指序列
    private var rollSpeed: Double = 0          // 轮指速度（次/秒）
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
    /// 检测轮指动作（每个音频缓冲调用一次，内部逐采样做峰值拾取）
    func detectRoll(from buffer: AVAudioPCMBuffer) -> RollEvent? {
        guard let channelData = buffer.floatChannelData?[0] else {
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }
        
        let envDecay = Float(exp(-1.0 / (sampleRate * envTau)))
        let threshold = max(baseThreshold, noiseFloor * noiseMargin)
        lastEffectiveThreshold = threshold
        
        var lastEvent: RollEvent?
        
        for i in 0..<frameLength {
            let a = abs(channelData[i])
            // 包络：瞬间跟上峰值，按 envTau 缓慢回落
            env = max(a, env * envDecay)
            // 仅当信号明显低于阈值时才缓慢更新噪声底，避免被乐音拉高
            if a < threshold * 0.4 {
                noiseFloor = noiseFloor * (1 - noiseFloorAlpha) + a * noiseFloorAlpha
            }
            
            let t = elapsed + Double(i) / sampleRate
            
            // 追踪当前波峰
            if env > peakVal {
                peakVal = env
                peakTime = t
            }
            // 包络从峰值回落到 peakFallRatio 以下 → 确认一个波峰（一次拨弦）
            if peakVal > threshold && env < peakVal * peakFallRatio {
                let candTime = peakTime
                let candAmp = peakVal
                peakVal = env // 重置追踪，准备捕捉下一个波峰
                
                let interval = lastOnsetElapsed < 0 ? 0 : candTime - lastOnsetElapsed
                
                // 若与上一起音间隔过长，先结束旧序列（新音开启一轮新序列）
                if lastOnsetElapsed >= 0, interval > maxRollInterval, !currentSequence.isEmpty {
                    completeCurrentSequence()
                }
                lastOnsetElapsed = candTime
                
                // 过快：已有上一音但间隔过短，疑似同一次拨弦的重复起音，忽略
                // （首个音 interval==0 不在此列，正常计入）
                if lastOnsetElapsed >= 0, interval < minRollInterval {
                    continue
                }
                
                let note = RollNote(
                    timestamp: date(for: candTime),
                    amplitude: candAmp,
                    interval: max(0, interval)
                )
                currentSequence.append(note)
                
                // 计算实时速度（取最近若干间隔的平均）
                if currentSequence.count >= 2 {
                    let intervals = currentSequence.suffix(5).dropFirst().map { $0.interval }
                    let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
                    rollSpeed = avgInterval > 0 ? 1.0 / avgInterval : 0
                }
                
                let event = RollEvent(
                    note: note,
                    sequenceLength: currentSequence.count,
                    currentSpeed: rollSpeed,
                    isValidSequence: currentSequence.count >= rollSequenceMinCount
                )
                onRollDetected?(event)
                lastEvent = event
            }
        }
        
        elapsed += Double(frameLength) / sampleRate
        
        // 缓冲区结束后检查超时：长时间无新起音则结束当前序列
        if !currentSequence.isEmpty,
           elapsed - lastOnsetElapsed > maxRollInterval {
            completeCurrentSequence()
        }
        
        return lastEvent
    }
    
    /// 把累计时间（秒）映射为 Date（首个起音时建立基准）
    private func date(for t: Double) -> Date {
        if anchorDate == nil {
            anchorDate = Date()
            anchorElapsed = t
        }
        return anchorDate!.addingTimeInterval(t - anchorElapsed)
    }
    
    // MARK: - Sequence Management
    
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
        noiseFloor = 0.01
        env = 0
        peakVal = 0
        peakTime = 0
        lastOnsetElapsed = -1
        elapsed = 0
        anchorDate = nil
        anchorElapsed = 0
        currentSequence.removeAll()
        rollSpeed = 0
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
