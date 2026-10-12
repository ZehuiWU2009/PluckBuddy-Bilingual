//
//  SweepDetector.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/7/16.
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
    private var lastAmplitude: Float = 0
    private var sweepHistory: [SweepEvent] = []
    
    // MARK: - Callbacks
    var onSweepDetected: ((SweepEvent) -> Void)?
    
    // MARK: - Initialization
    init(sampleRate: Double = 48000.0) {
        self.sampleRate = sampleRate
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
            lastAmplitude = peak
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
        
        // 5️⃣ 检测方向（基于振幅变化趋势）
        let direction: SweepDirection
        if peak > lastAmplitude * 1.2 {
            // 振幅明显增大，可能是向下扫
            direction = .down
        } else if peak < lastAmplitude * 0.8 {
            // 振幅明显减小，可能是向上扫
            direction = .up
        } else {
            // 振幅变化不大，根据历史推断
            direction = inferDirection()
        }
        
        lastAmplitude = peak
        
        // 6️⃣ 计算力度等级（基于峰值）
        let strength = calculateStrength(peak: peak, rms: rms)
        
        // 7️⃣ 创建扫弦事件
        let event = SweepEvent(
            timestamp: now,
            amplitude: peak,
            rms: rms,
            direction: direction,
            strength: strength
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
    
    /// 根据历史推断方向
    private func inferDirection() -> SweepDirection {
        guard sweepHistory.count >= 2 else {
            return .down // 默认向下
        }
        
        // 取最近若干次记录用于方向判定
        let recentDirections = sweepHistory.suffix(5)
        
        // 倾向于交替方向
        let lastDirection = recentDirections.last?.direction ?? .down
        return lastDirection == .down ? .up : .down
    }
    
    /// 计算力度等级
    private func calculateStrength(peak: Float, rms: Float) -> StrengthLevel {
        // 综合考虑峰值和 RMS
        let combinedStrength = (peak * 0.7 + rms * 0.3)
        
        if combinedStrength > 0.7 {
            return .veryStrong
        } else if combinedStrength > 0.5 {
            return .strong
        } else if combinedStrength > 0.3 {
            return .medium
        } else {
            return .weak
        }
    }
    
    /// 获取平均力度
    func getAverageStrength() -> Double {
        guard !sweepHistory.isEmpty else { return 0 }
        
        let totalStrength = sweepHistory.reduce(0.0) { $0 + Double($1.amplitude) }
        return totalStrength / Double(sweepHistory.count)
    }
    
    /// 获取扫弦统计
    func getStatistics() -> SweepStatistics {
        let upCount = sweepHistory.filter { $0.direction == .up }.count
        let downCount = sweepHistory.filter { $0.direction == .down }.count
        let avgStrength = getAverageStrength()
        
        return SweepStatistics(
            totalCount: sweepHistory.count,
            upCount: upCount,
            downCount: downCount,
            averageStrength: avgStrength
        )
    }
    
    /// 重置检测器
    func reset() {
        lastDetectionTime = nil
        lastAmplitude = 0
        sweepHistory.removeAll()
    }
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
    
    /// 归一化的力度值 (0-1)
    var normalizedStrength: Double {
        return Double(amplitude)
    }
}

// MARK: - SweepStatistics
/// 扫弦统计
struct SweepStatistics {
    let totalCount: Int
    let upCount: Int
    let downCount: Int
    let averageStrength: Double
    
    /// 方向平衡度（越接近 0.5 越平衡）
    var directionBalance: Double {
        guard totalCount > 0 else { return 0.5 }
        return Double(min(upCount, downCount)) / Double(totalCount)
    }
}
