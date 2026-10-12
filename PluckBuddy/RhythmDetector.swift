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
    private let minIntervalMs: Double = 200 // 最小间隔 200ms（防止噪音和重复检测）
    private let maxReasonableBPM: Double = 240 // 最大合理 BPM（过滤异常快的间隔）
    private let minReasonableBPM: Double = 40 // 最小合理 BPM（过滤异常慢的间隔）
    
    // MARK: - State
    private var lastDetectionTime: Date?
    private var intervals: [Double] = [] // 记录最近的时间间隔
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
        
        // 🔍 实时打印音量（更频繁，帮助调试）
        let now = Date()
        if lastLogTime == nil || now.timeIntervalSince(lastLogTime!) >= logInterval {
            if peak > 0.005 { // 降低打印阈值
                let isAboveThreshold = peak > amplitudeThreshold || rms > rmsThreshold
                let marker = isAboveThreshold ? "✅" : "⚪️"
                print("\(marker) 音量监控 - 峰值: \(String(format: "%.3f", peak)) (阈值:\(amplitudeThreshold)), RMS: \(String(format: "%.3f", rms)) (阈值:\(rmsThreshold))")
            }
            lastLogTime = now
        }
        
        // 3️⃣ 检查是否超过阈值（使用 OR 逻辑，峰值或 RMS 任一达标即可）
        guard peak > amplitudeThreshold || rms > rmsThreshold else {
            return nil
        }
        
        // 4️⃣ 检查时间间隔（防抖）
        if let lastTime = lastDetectionTime {
            let intervalMs = now.timeIntervalSince(lastTime) * 1000
            guard intervalMs >= minIntervalMs else {
                return nil // 太快，忽略
            }
        }
        
        // 5️⃣ 记录时间间隔
        var interval: Double = 0
        if let lastTime = lastDetectionTime {
            interval = now.timeIntervalSince(lastTime)
            
            // 🔍 过滤不合理的间隔（太快或太慢）
            let instantBPM = 60.0 / interval
            if instantBPM > maxReasonableBPM {
                print("⚠️ 间隔过短 (\(String(format: "%.3f", interval))s, BPM:\(String(format: "%.0f", instantBPM))) - 可能是噪音，忽略")
                return nil // 太快，可能是噪音
            }
            if instantBPM < minReasonableBPM {
                print("⚠️ 间隔过长 (\(String(format: "%.3f", interval))s, BPM:\(String(format: "%.0f", instantBPM))) - 可能是停顿，忽略")
                return nil // 太慢，可能是停顿
            }
            
            intervals.append(interval)
            
            // 限制历史记录大小
            if intervals.count > maxIntervalHistory {
                intervals.removeFirst()
            }
        }
        
        lastDetectionTime = now
        detectionCount += 1
        
        // 6️⃣ 创建事件
        let event = PluckEvent(
            timestamp: now,
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
        guard intervals.count >= 3 else { return 0 }
        
        // 计算平均间隔
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        
        // 转换为 BPM
        guard avgInterval > 0 else { return 0 }
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
        
        // 变异系数（CV）= 标准差 / 平均值
        let cv = stdDev / mean
        
        // 转换为稳定性分数（CV 越小越稳定）
        // CV < 0.05 → 稳定性 100%
        // CV < 0.1  → 稳定性 90%
        // CV < 0.2  → 稳定性 80%
        // CV < 0.3  → 稳定性 70%
        let stability = max(0, min(1, 1.0 - cv * 3)) // 调整系数从 5 降到 3
        
        print("📊 稳定性计算: intervals=\(intervals.count), mean=\(String(format: "%.3f", mean)), stdDev=\(String(format: "%.3f", stdDev)), CV=\(String(format: "%.3f", cv)), stability=\(String(format: "%.1f", stability * 100))%")
        
        return stability
    }
    
    /// 重置检测状态
    func reset() {
        lastDetectionTime = nil
        intervals.removeAll()
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
