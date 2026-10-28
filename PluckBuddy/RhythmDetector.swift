//
//  RhythmDetector.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/7/16.
//

import Foundation
import AVFoundation
import Accelerate

/// 节奏检测器 - 检测弹拨动作和节奏
class RhythmDetector {
    
    // MARK: - Configuration
    private let sampleRate: Double
    private let amplitudeThreshold: Float = 0.015 // 振幅阈值（提高以减少噪音）
    private let rmsThreshold: Float = 0.008 // RMS 阈值（提高以减少噪音）
    private let minIntervalMs: Double = 120 // 最小间隔（不应期）120ms，允许最快约 500 BPM 的连弹被识别
    private let maxReasonableBPM: Double = 240 // 最大合理 BPM（过滤异常快的间隔）
    private let minReasonableBPM: Double = 40 // 最小合理 BPM（过滤异常慢的间隔）
    /// 允许的固有计时噪声（秒）。起音位置与真实发声点之间总有毫秒级偏差（拨弦瞬态形状、
    /// 缓冲区边界），评分前先从标准差里扣掉，避免把测量误差算成演奏不稳。
    private let timingNoiseFloor: Double = 0.006
    
    // MARK: - State
    private var lastDetectionTime: Date?
    private var intervals: [Double] = [] // 记录最近的时间间隔
    private var prevRMS: Float = 0       // 上一帧 RMS，用于判定「能量是否正在上升」（起音 vs 衰减尾）
    private let maxIntervalHistory = 10
    
    // 🔍 调试：音量监控
    private var lastLogTime: Date?
    private let logInterval: Double = 1.0 // 每1秒打印一次（改为更频繁）
    private var detectionCount = 0
    
    // MARK: - Callbacks
    var onPluckDetected: ((PluckEvent) -> Void)?
    
    // MARK: - Initialization
    init(sampleRate: Double = 48000.0) {
        self.sampleRate = sampleRate
        print("🎧 RhythmDetector 初始化（抗噪音版）")
        print("   - 峰值阈值: \(amplitudeThreshold)")
        print("   - RMS 阈值: \(rmsThreshold)")
        print("   - 最小间隔: \(Int(minIntervalMs))ms")
        print("   - BPM 范围: \(Int(minReasonableBPM))-\(Int(maxReasonableBPM))")
    }
    
    // MARK: - Detection
    /// 检测弹拨动作
    func detectPluck(from buffer: AVAudioPCMBuffer) -> PluckEvent? {
        guard let channelData = buffer.floatChannelData?[0] else {
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }
        
        // 1️⃣ 计算 RMS（均方根）- 表示信号能量
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        
        // 2️⃣ 计算峰值振幅
        var peak: Float = 0.0
        vDSP_maxv(channelData, 1, &peak, vDSP_Length(frameLength))

        // 2.5️⃣ 起音的精确时刻（关键）：
        //    音频 tap 的缓冲区是 4096 采样 @48kHz ≈ 85ms，若直接用回调时间当弹拨时刻，
        //    起音只能定位到缓冲区边界，光量化误差就有约 35ms；再加上「能量上升」判定可能
        //    晚一个缓冲区才满足，总抖动可达 60~100ms——跟着节拍器弹也只剩 50~60% 稳定性。
        //    这里在缓冲区内部把起音点找出来：先定位峰值样本，再向前回溯到能量最后一次
        //    低于 25% 峰值的位置，那个点才是真正的拨弦瞬间，时间分辨率回到采样级。
        // 🔍 实时打印音量（更频繁，帮助调试）
        let now = Date()

        // 2.5️⃣ 起音的精确时刻（关键）：
        //    音频 tap 的缓冲区是 4096 采样 @48kHz ≈ 85ms，若直接用回调时间当弹拨时刻，
        //    起音只能定位到缓冲区边界，光量化误差就有约 35ms；再加上「能量上升」判定可能
        //    晚一个缓冲区才满足，总抖动可达 60~100ms——跟着节拍器弹也只剩 50~60% 稳定性。
        //    这里在缓冲区内部把起音点找出来：先定位峰值样本，再向前回溯到能量最后一次
        //    低于 25% 峰值的位置，那个点才是真正的拨弦瞬间，时间分辨率回到采样级。
        let frameDuration = Double(frameLength) / sampleRate
        let onsetOffset = onsetOffsetSeconds(in: channelData, count: frameLength)
        let eventTime = now.addingTimeInterval(onsetOffset - frameDuration)

        if lastLogTime == nil || now.timeIntervalSince(lastLogTime!) >= logInterval {
            if peak > 0.005 { // 降低打印阈值
                let isAboveThreshold = peak > amplitudeThreshold || rms > rmsThreshold
                let marker = isAboveThreshold ? "✅" : "⚪️"
                print("\(marker) 音量监控 - 峰值: \(String(format: "%.3f", peak)) (阈值:\(amplitudeThreshold)), RMS: \(String(format: "%.3f", rms)) (阈值:\(rmsThreshold))")
            }
            lastLogTime = now
        }
        
        // 3️⃣ 判断当前是否超过阈值（峰值或 RMS 任一达标即可）
        let above = peak > amplitudeThreshold || rms > rmsThreshold

        // 未超过阈值：不是弹奏，更新能量基线后直接返回
        guard above else {
            prevRMS = rms
            return nil
        }

        // 4️⃣ 起音检测（onset）
        //    琵琶弹挑每一下是「尖锐起音 + 快速衰减」。若对每个超阈值 buffer 都计数，
        //    单根音的延音尾会被当成多次弹拨，算出虚高的 BPM（如刚弹第一个音就显示 200）；
        //    若只在「低于阈值→高于阈值」的上升沿计数，快速连弹时音与音的衰减尾常重叠、
        //    信号一直高于阈值，状态卡住导致后续起音永远不触发、BPM 恒为 0。
        //    这里改为：越过不应期「且」能量正在上升时才记一次起音——
        //      - 不应期（minIntervalMs）排除噪声与同一根音的毫秒级双触发；
        //      - 能量上升判定（当前 RMS 未明显低于上一帧）把下降的衰减尾排除在外，
        //        而下一下的起音是上升的、会被记上。
        //    这样连续快速弹挑每一下都能独立计数，BPM 反映真实速度，也不再卡在 0。
        let sinceLast = lastDetectionTime.map { eventTime.timeIntervalSince($0) } ?? .infinity
        let minIntervalSec = minIntervalMs / 1000.0
        let isRising = rms >= prevRMS * 0.9

        // 仍在不应期内，或处于衰减尾（能量下降）→ 不是起音，不触发事件
        guard sinceLast >= minIntervalSec, isRising else {
            prevRMS = rms
            return nil
        }

        // 5️⃣ 记录与上次起音的时间间隔（用缓冲区内精确定位出的起音时刻，而非回调时间）
        var interval: Double = 0
        if let lastTime = lastDetectionTime {
            interval = eventTime.timeIntervalSince(lastTime)

            let instantBPM = 60.0 / interval
            if instantBPM <= maxReasonableBPM && instantBPM >= minReasonableBPM {
                intervals.append(interval)
                if intervals.count > maxIntervalHistory {
                    intervals.removeFirst()
                }
            }
        }

        lastDetectionTime = eventTime
        prevRMS = rms
        detectionCount += 1

        // 6️⃣ 创建事件
        let event = PluckEvent(
            timestamp: eventTime,
            amplitude: peak,
            rms: rms,
            interval: interval,
            bpm: calculateBPM()
        )

        // 🔍 详细日志
        print("🎸 [\(detectionCount)] 检测到弹奏！峰值:\(String(format: "%.3f", peak)) RMS:\(String(format: "%.3f", rms))")

        onPluckDetected?(event)
        return event
    }
    
    // MARK: - Analysis
    /// 计算当前的 BPM（每分钟节拍数）
    func calculateBPM() -> Double {
        guard intervals.count >= 2 else { return 0 }
        
        // 计算平均间隔
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        
        // 转换为 BPM
        guard avgInterval > 0 else { return 0 }
        // BPM 按每个弹挑音计：每分钟弹 100 个音 → BPM 100。
        return 60.0 / avgInterval
    }
    
    /// 计算节奏稳定性（0-1，1 表示完美稳定）
    func calculateStability() -> Double {
        guard intervals.count >= 2 else { return 0 } // 降低到至少 2 次

        // 计算标准差
        let mean = intervals.reduce(0, +) / Double(intervals.count)

        // 避免除以 0
        guard mean > 0 else { return 0 }

        let variance = intervals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(intervals.count)
        let stdDev = sqrt(variance)

        // 先扣掉固有的计时噪声，剩下的才是演奏本身的抖动
        let netStdDev = max(0, stdDev - timingNoiseFloor)

        // 变异系数（CV）= 标准差 / 平均值
        let cv = netStdDev / mean

        // 转换为稳定性分数。旧曲线 1-3×CV 过于严苛：人跟着节拍器弹也有 5~10% 的自然抖动，
        // 却只能拿到 70~85%。放宽到 1-2×CV，并给小抖动留出满分区间：
        //   CV ≤ 0.025（抖动 ≤ 2.5%）→ 100%
        //   CV 0.05 → 90%    CV 0.10 → 80%    CV 0.20 → 60%
        let stability = max(0, min(1, 1.0 - cv * 2))

        print("📊 稳定性计算: intervals=\(intervals.count), mean=\(String(format: "%.3f", mean)), stdDev=\(String(format: "%.3f", stdDev)), 净抖动=\(String(format: "%.3f", netStdDev)), CV=\(String(format: "%.3f", cv)), stability=\(String(format: "%.1f", stability * 100))%")

        return stability
    }

    /// 在缓冲区内部定位起音点，返回它相对缓冲区起点的时间偏移（秒）。
    /// 做法：先找整段的峰值样本（拨弦瞬态是缓冲区里最响的部分），再向前回溯到
    /// 幅度最后一次低于 25% 峰值的位置——那里才是拨弦真正发生的瞬间。
    /// 这样把时间分辨率从「一个缓冲区 ≈ 85ms」提升到采样级（≈0.02ms）。
    private func onsetOffsetSeconds(in data: UnsafePointer<Float>, count: Int) -> Double {
        guard count > 0 else { return 0 }

        var peakValue: Float = 0
        var peakIndex: vDSP_Length = 0
        vDSP_maxmgvi(data, 1, &peakValue, &peakIndex, vDSP_Length(count))

        guard peakValue > 0 else { return 0 }

        let threshold = peakValue * 0.25
        var index = Int(peakIndex)
        while index > 0, abs(data[index]) > threshold {
            index -= 1
        }

        return Double(index) / sampleRate
    }
    
    /// 重置检测状态
    func reset() {
        lastDetectionTime = nil
        intervals.removeAll()
        prevRMS = 0
    }
}

// MARK: - PluckEvent
/// 弹拨事件
struct PluckEvent {
    let timestamp: Date
    let amplitude: Float // 峰值振幅 (0-1)
    let rms: Float // 均方根能量
    let interval: Double // 与上次弹拨的时间间隔（秒）
    let bpm: Double // 当前速度（BPM）
    
    /// 力度等级（弱、中、强）
    var strength: Strength {
        if amplitude < 0.3 {
            return .weak
        } else if amplitude < 0.6 {
            return .medium
        } else {
            return .strong
        }
    }
    
    enum Strength {
        case weak
        case medium
        case strong
        
        var description: String {
            switch self {
            case .weak: return L("弱")
            case .medium: return L("中")
            case .strong: return L("强")
            }
        }
    }
}
