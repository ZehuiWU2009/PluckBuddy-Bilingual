//
//  SweepDetector.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/7/16.
//

import Foundation
import AVFoundation
import Accelerate

/// 扫弦检测器 - 检测扫弦动作的力度和方向
class SweepDetector {
    
    // MARK: - Configuration
    private let sampleRate: Double
    private let sweepThreshold: Float = 0.2 // 扫弦检测阈值（较高，扫弦力度大）
    private let minSweepInterval: Double = 0.3 // 最小间隔 300ms（防止重复检测）
    
    // MARK: - State
    private var lastDetectionTime: Date?
    private var sweepHistory: [SweepEvent] = []
    private var lastDirection: SweepDirection? // 上一次判定的方向（走向不明显时按它交替推断）

    // MARK: - 方向检测（基于起音基频的自相关）
    /// 扫弦起音最初几毫秒只有最先被拨到的那根弦单独发声：
    /// 下扫（扫）先碰缠弦（≈220Hz），上拂（拂）先碰子弦（≈440Hz）。
    /// 用自相关估出起音基频，低于 330Hz 判向下、高于判向上，干净区分两种方向，
    /// 不受四弦延音重叠与击弦亮度干扰。
    /// 旧实现用全程频谱质心趋势判方向，但四弦在 ~88ms 内全拨完、到窗口中点已一起响，
    /// 前后半窗质心几乎相同，走向信号被淹没，几乎永远判不出方向，导致平衡虚高/虚低。
    private let onsetBlockSize = 1024          // 约 21ms @48k，只含引导弦
    private let onsetMinFreqHz: Double = 160  // 自相关搜索下限
    private let onsetMaxFreqHz: Double = 600  // 自相关搜索上限（含缠/子八度差余量）
    private let onsetConfidenceMin: Float = 0.12 // 低于此置信度视为无法判定，回退交替推断
    private let onsetSplitHz: Double = 330    // 缠弦(220)与子弦(440)的中点，用于二分方向

    // MARK: - Callbacks
    var onSweepDetected: ((SweepEvent) -> Void)?

    // MARK: - Initialization
    init(sampleRate: Double = 48000.0) {
        self.sampleRate = sampleRate
    }

    deinit {
    }
    
    // MARK: - Detection
    /// 检测扫弦动作
    func detectSweep(from buffer: AVAudioPCMBuffer) -> SweepEvent? {
        guard let channelData = buffer.floatChannelData?[0] else {
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }
        
        // 1️⃣ 计算 RMS（均方根能量）
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        
        // 2️⃣ 计算峰值振幅
        var peak: Float = 0.0
        vDSP_maxv(channelData, 1, &peak, vDSP_Length(frameLength))
        
        // 3️⃣ 检查是否超过阈值
        guard peak > sweepThreshold else {
            return nil
        }
        
        // 4️⃣ 检查时间间隔（防抖）
        let now = Date()
        if let lastTime = lastDetectionTime {
            let interval = now.timeIntervalSince(lastTime)
            guard interval >= minSweepInterval else {
                return nil
            }
        }
        
        lastDetectionTime = now
        
        // 5️⃣ 检测方向：用「起音基频」判定。
        //     下扫（扫）拨片先碰缠弦，起音基频≈220Hz；上拂（拂）先碰子弦，起音基频≈440Hz。
        //     取检测窗首块做自相关估基频，低于 330Hz 判向下、高于判向上，干净区分两种方向。
        let onset = onsetPitch(in: channelData, count: frameLength)
        let direction: SweepDirection
        let directionReliable: Bool
        if let (f, c) = onset, c >= onsetConfidenceMin {
            direction = f < onsetSplitHz ? .down : .up
            directionReliable = true
        } else {
            // 起音基频判不出时按「扫拂交替」推断（扫弦练习基本一扫一拂，是很强的先验）。
            direction = inferDirection()
            directionReliable = false
        }
        lastDirection = direction

        if let (f, c) = onset {
            print("   🧭 起音基频: \(String(format: "%.0f", f))Hz 置信\(String(format: "%.2f", c)) → \(direction == .down ? "向下扫（缠弦先响）" : "向上拂（子弦先响）")")
        } else {
            print("   🧭 起音基频无法判定，沿用交替推断")
        }

        // 6️⃣ 计算力度等级（基于归一化后的峰值力度）
        let strength = calculateStrength(peak: peak)
        
        // 7️⃣ 创建扫弦事件
        let event = SweepEvent(
            timestamp: now,
            amplitude: peak,
            rms: rms,
            direction: direction,
            strength: strength,
            directionReliable: directionReliable
        )
        
        // 记录历史
        sweepHistory.append(event)
        if sweepHistory.count > 10 {
            sweepHistory.removeFirst()
        }
        
        onSweepDetected?(event)
        return event
    }
    
    // MARK: - Analysis

    /// 估起音基频：对检测窗首块做自相关，在 [onsetMinFreqHz, onsetMaxFreqHz] 对应 lag 区间取峰值。
    /// 返回 (基频Hz, 置信度)。置信度 = 峰值自相关 / 零延迟能量，越高说明起音周期性越强、判定越可信。
    /// 不依赖 FFT（App 内 vDSP_DFT 用法算出的频谱有偏差），纯时域计算，稳定可靠。
    private func onsetPitch(in data: UnsafePointer<Float>, count: Int) -> (freq: Double, confidence: Float)? {
        let block = min(onsetBlockSize, count)
        guard block > 64 else { return nil }

        var x = [Float](repeating: 0, count: block)
        for i in 0..<block { x[i] = data[i] }

        var energy: Float = 0
        for i in 0..<block { energy += x[i] * x[i] }
        guard energy > 1e-4 else { return nil }

        let minLag = max(1, Int(Double(sampleRate) / onsetMaxFreqHz))
        let maxLag = min(block - 1, Int(Double(sampleRate) / onsetMinFreqHz))
        guard maxLag > minLag else { return nil }

        var bestLag = minLag
        var bestACF: Float = -1
        for lag in minLag...maxLag {
            var sum: Float = 0
            for i in 0..<(block - lag) { sum += x[i] * x[i + lag] }
            if sum > bestACF { bestACF = sum; bestLag = lag }
        }
        guard bestLag > 0, bestACF > 0 else { return nil }

        let freq = Double(sampleRate) / Double(bestLag)
        let confidence = bestACF / energy
        return (freq, confidence)
    }

    /// 走向不明显时的兜底：按「一扫一拂」交替推断。
    /// 旧实现要求历史至少 2 条才交替，开头的几次一律判成向下，方向序列从一开始就歪了。
    private func inferDirection() -> SweepDirection {
        guard let last = lastDirection else {
            return .down // 第一次默认向下
        }
        return last == .down ? .up : .down
    }

    /// 计算力度等级（基于归一化后的力度，阈值与用户看到的百分比一致）
    private func calculateStrength(peak: Float) -> StrengthLevel {
        let n = normalizedSweepStrength(amplitude: peak)

        if n >= 0.80 {
            return .veryStrong
        } else if n >= 0.55 {
            return .strong
        } else if n >= 0.25 {
            return .medium
        } else {
            return .weak
        }
    }

    /// 获取平均力度
    func getAverageStrength() -> Double {
        guard !sweepHistory.isEmpty else { return 0 }

        let totalStrength = sweepHistory.reduce(0.0) { $0 + $1.normalizedStrength }
        return totalStrength / Double(sweepHistory.count)
    }
    
    /// 获取扫弦统计
    func getStatistics() -> SweepStatistics {
        let upCount = sweepHistory.filter { $0.direction == .up }.count
        let downCount = sweepHistory.filter { $0.direction == .down }.count
        let avgStrength = getAverageStrength()

        // 方向平衡：统计整段真实方向序列的「数量均衡 × 交替质量」。
        // 现在方向由起音基频可靠判定（见 detectSweep），不再用「强制交替」兜底去压低分数，
        // 所以直接按全序列计算：数量越接近 1:1、交替越整齐，分数越高；
        // 偏重一侧或连弹同向，分数自然下降。均衡且整齐时接近 1.0（这是真实练习的正常结果），
        // 不再被不可信率乘子压到接近 0。
        var directionBalance: Double
        if sweepHistory.count < 2 {
            directionBalance = 0.5
        } else {
            let countBalance = 2.0 * Double(min(upCount, downCount)) / Double(sweepHistory.count)
            var transitions = 0
            for i in 1..<sweepHistory.count {
                if sweepHistory[i].direction != sweepHistory[i - 1].direction {
                    transitions += 1
                }
            }
            let alternation = Double(transitions) / Double(sweepHistory.count - 1)
            directionBalance = min(1.0, countBalance * alternation)
        }

        return SweepStatistics(
            totalCount: sweepHistory.count,
            upCount: upCount,
            downCount: downCount,
            averageStrength: avgStrength,
            directionBalance: directionBalance
        )
    }
    
    /// 重置检测器
    func reset() {
        lastDetectionTime = nil
        lastDirection = nil
        sweepHistory.removeAll()
    }
}

// MARK: - 力度归一化
/// 麦克风前正常扫弦的峰值大多落在 0.15~0.40（实测「使劲弹」峰值约 0.40）。
/// 过去上限取了 0.60，导致再用力也过不了 70%；先后调到 0.45、0.40，
/// 每次把曲线整体抬高约 10 个百分点。想要更难拿高分就把 strengthCeilAmplitude 调高。
private let strengthFloorAmplitude: Double = 0.10
private let strengthCeilAmplitude: Double = 0.40

/// 把峰值振幅映射成 0~1 的力度
func normalizedSweepStrength(amplitude: Float) -> Double {
    let span = strengthCeilAmplitude - strengthFloorAmplitude
    guard span > 0 else { return 0 }
    let n = (Double(amplitude) - strengthFloorAmplitude) / span
    return min(1.0, max(0.0, n))
}

// MARK: - SweepDirection
/// 扫弦方向
enum SweepDirection {
    case up     // 向上扫
    case down   // 向下扫
    
    var description: String {
        switch self {
        case .up: return L("向上")
        case .down: return L("向下")
        }
    }
    
    var arrow: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        }
    }
}

// MARK: - StrengthLevel
/// 力度等级
enum StrengthLevel {
    case weak
    case medium
    case strong
    case veryStrong
    
    var description: String {
        switch self {
        case .weak: return L("轻")
        case .medium: return L("中")
        case .strong: return L("重")
        case .veryStrong: return L("很重")
        }
    }
    
    var value: Double {
        switch self {
        case .weak: return 0.25
        case .medium: return 0.5
        case .strong: return 0.75
        case .veryStrong: return 1.0
        }
    }
}

// MARK: - SweepEvent
/// 扫弦事件
struct SweepEvent {
    let timestamp: Date
    let amplitude: Float
    let rms: Float
    let direction: SweepDirection
    let strength: StrengthLevel
    /// 方向是否由「起音基频」可靠判定；false 表示起音基频判不出、退回了「交替推断」兜底。
    /// 仅用于日志与调试，计算方向平衡时不再排除（见 getStatistics）。
    let directionReliable: Bool
    
    /// 归一化的力度值 (0-1)
    var normalizedStrength: Double {
        return normalizedSweepStrength(amplitude: amplitude)
    }
}

// MARK: - SweepStatistics
/// 扫弦统计
struct SweepStatistics {
    let totalCount: Int
    let upCount: Int
    let downCount: Int
    let averageStrength: Double
    /// 方向平衡度（0-1）：统计整段真实方向序列的「数量均衡 × 交替质量」，
    /// 方向由起音基频可靠判定（见 SweepDetector.detectSweep / getStatistics）。
    let directionBalance: Double
}
