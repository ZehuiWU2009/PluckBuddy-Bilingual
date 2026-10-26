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
    /// RMS 包络的平滑截止频率（Hz）。取约 30Hz：足以把 220Hz 载波纹波完全平均掉，
    /// 又足够快以保留每次起音造成的包络上升沿，从而能在长余震（音与音之间不归零）
    /// 的轮指里把每个音头拆成各自独立的起音。
    private let envelopeHz: Double = 30.0
    /// 前视延迟窗（秒）：用「当前 RMS 包络 − 该窗之前的 RMS 包络」算正向能量跳变(flux)。
    /// 约 12ms，正好覆盖一次起音的上升段、又不越过其后的衰减段。
    private let delayWindow: Double = 0.012
    /// 起音确认条件：正向 flux 超过 fluxRatio × 当前包络，即认为一次新拨弦开始。
    /// 长余震时两音之间包络单调衰减(flux 为负)，只有每次起音处 flux 才明显为正，
    /// 因此该判据能把重叠的轮指逐拍分离，而不是像旧版「等包络回落到峰值的 50%」那样
    /// 在余震不归零时把整段合并成一个波峰。
    private let fluxRatio: Float = 0.05
    /// 两次有效起音的最小间隔（秒）：低于此值视为同一次拨弦的重复起音，忽略。
    /// 同时作为轮指速度上限（1/0.035 ≈ 28 次/秒）。
    private let minRollInterval: Double = 0.035
    /// 两次起音的最大间隔（秒）：超过即认为一轮轮指结束、开始新序列（≥4 次/秒）。
    private let maxRollInterval: Double = 0.25
    private let rollSequenceMinCount = 4 // 至少连续 4 次才算轮指
    
    // MARK: - State
    private var noiseFloor: Float = 0.01      // 环境噪声底估计
    private var sqState: Float = 0             // RMS 包络的平方积分状态（env = sqrt(sqState)）
    private var delayBuffer: [Float] = []      // 延迟包络环形缓冲（用于算 flux）
    private var delayIndex: Int = 0           // 环形缓冲写指针
    private var lockUntil: Double = -1         // 不应期：在此之前不再确认新起音
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
        let delaySamples = max(1, Int(delayWindow * sampleRate))
        delayBuffer = [Float](repeating: 0, count: delaySamples)
    }
    
    // MARK: - Detection
    /// 检测轮指动作（每个音频缓冲调用一次，内部逐采样做正向 flux 起音拾取）
    ///
    /// 实现方式：用约 30Hz 的 RMS 包络把载波纹波平均掉；长余震时包络在两次
    /// 拨弦之间单调衰减，只有每次起音处出现一次清晰的正向能量跳变(flux)。
    /// 因此用「当前包络 − 前视窗口前的包络 > fluxRatio×包络」来逐拍确认起音，
    /// 即使音与音之间几乎不归零也能分离，速度（次/秒）与均匀度随真实演奏变化。
    func detectRoll(from buffer: AVAudioPCMBuffer) -> RollEvent? {
        guard let channelData = buffer.floatChannelData?[0] else {
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }
        
        // RMS 包络平滑系数（一阶低通，截止 envelopeHz）
        let envAlpha = Float(1.0 - exp(-2.0 * .pi * envelopeHz / sampleRate))
        let threshold = max(baseThreshold, noiseFloor * noiseMargin)
        lastEffectiveThreshold = threshold
        
        var lastEvent: RollEvent?
        
        for i in 0..<frameLength {
            let a = abs(channelData[i])
            // RMS 包络：env = sqrt(LPF(a²))，30Hz 平滑足以抹平载波纹波
            sqState = sqState + envAlpha * (a * a - sqState)
            let env = sqrt(max(sqState, 0))
            // 仅当信号明显低于阈值时才缓慢更新噪声底，避免被乐音拉高
            if a < threshold * 0.4 {
                noiseFloor = noiseFloor * (1 - noiseFloorAlpha) + a * noiseFloorAlpha
            }
            
            // 前视窗口的延迟包络（环形缓冲）
            let delayed = delayBuffer[delayIndex]
            delayBuffer[delayIndex] = env
            delayIndex = (delayIndex + 1) % delayBuffer.count
            
            let t = elapsed + Double(i) / sampleRate
            
            // 不应期内跳过，避免同一次起音的上升段重复触发
            if t < lockUntil {
                continue
            }
            
            // 正向 flux：长余震下两音之间包络衰减(flux<0)，起音处才为正
            let flux = env - delayed
            if env > threshold && flux > fluxRatio * env {
                let onsetTime = t
                let interval = lastOnsetElapsed < 0 ? 0 : onsetTime - lastOnsetElapsed
                
                // 若与上一音间隔过长，先结束旧序列（新音开启一轮新序列）
                if lastOnsetElapsed >= 0, interval > maxRollInterval, !currentSequence.isEmpty {
                    completeCurrentSequence()
                }
                
                // 首个音(interval==0)正常计入；过快则视为重复起音，忽略
                // （不更新 lastOnsetElapsed，使下一次有效起音仍相对上一次有效起音计时）
                if lastOnsetElapsed >= 0, interval < minRollInterval {
                    continue
                }
                
                let note = RollNote(
                    timestamp: date(for: onsetTime),
                    amplitude: env,
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
                
                lastOnsetElapsed = onsetTime
                lockUntil = t + minRollInterval
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
        guard !intervals.isEmpty else { return 0 }
        
        // 稳健变异系数：剔除两端各 15% 的极端间隔后再算 cv。
        // 个别起音误判（偶尔多/漏一拍）会产生离群间隔，原始 cv 会被这些离群值
        // 严重拉高，使均匀度近乎清零；剔除极端值后能更真实反映整体手法。
        let core = trimmedCore(intervals, trimFraction: 0.15)
        let mean = core.reduce(0, +) / Double(core.count)
        
        guard mean > 0 else { return 0 }
        
        let variance = core.map { pow($0 - mean, 2) }.reduce(0, +) / Double(core.count)
        let stdDev = sqrt(variance)
        
        // 变异系数（越小越均匀）
        let cv = stdDev / mean
        
        // 转换为 0-1 分数。系数从 3.0 放宽到 2.0：
        // 真实轮指间隔波动约 10%-25%（cv 0.1-0.25），对应分数 0.5-0.8，
        // 让认真练习就能稳定拿到 good～excellent，而不是几乎永远卡在低分。
        return max(0, min(1, 1.0 - cv * 2.0))
    }
    
    /// 返回剔除两端各 trimFraction 比例的极端值后的核心样本（样本数过少则原样返回）
    private func trimmedCore(_ values: [Double], trimFraction: Double) -> [Double] {
        guard values.count >= 6 else { return values }
        let sorted = values.sorted()
        let k = max(1, Int((Double(sorted.count) * trimFraction).rounded(.down)))
        let lo = min(k, sorted.count - 1)
        let hi = max(0, sorted.count - k)
        guard hi > lo else { return values }
        return Array(sorted[lo..<hi])
    }
    
    /// 重置检测器
    func reset() {
        noiseFloor = 0.01
        sqState = 0
        delayBuffer = [Float](repeating: 0, count: max(1, Int(delayWindow * sampleRate)))
        delayIndex = 0
        lockUntil = -1
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
        // 阈值同步放宽：速度门槛下调、均匀度门槛下调，
        // 让「速度不慢 + 间隔基本均匀」的认真练习就能拿到高分。
        if uniformity > 0.7 && averageSpeed >= 8 {
            return .excellent
        } else if uniformity > 0.55 && averageSpeed >= 6 {
            return .good
        } else if uniformity > 0.4 && averageSpeed >= 4 {
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
