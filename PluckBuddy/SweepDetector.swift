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
    private var sweepHistory: [SweepEvent] = []
    private var lastDirection: SweepDirection? // 上一次判定的方向（走向不明显时按它交替推断）

    // MARK: - 音高走向分析（用于判方向）
    private let fftSize = 1024 // 约 21ms @48k，足够分辨相邻弦发声的先后顺序
    private let fftSetup: vDSP_DFT_Setup
    private var realBuffer: [Float]
    private var imagBuffer: [Float]
    private var magnitudes: [Float]
    /// 判定方向所需的相对走向阈值：质心前后半相对变化超过这个值才采信。
    /// 四根弦的延音互相重叠，走向信号的量级本来就小（合成测试约 0.01~0.07），
    /// 阈值定高了就会频繁失效、退回兜底，所以这里取得较敏感。
    /// 若真机日志显示方向乱跳，把这个值调大（0.05~0.08）。
    private let trendThreshold: Float = 0.02

    // MARK: - Callbacks
    var onSweepDetected: ((SweepEvent) -> Void)?

    // MARK: - Initialization
    init(sampleRate: Double = 48000.0) {
        self.sampleRate = sampleRate
        guard let setup = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            vDSP_DFT_Direction.FORWARD
        ) else {
            fatalError("Failed to create FFT setup")
        }
        self.fftSetup = setup
        self.realBuffer = [Float](repeating: 0, count: fftSize)
        self.imagBuffer = [Float](repeating: 0, count: fftSize)
        self.magnitudes = [Float](repeating: 0, count: fftSize / 2)
    }

    deinit {
        vDSP_DFT_DestroySetup(fftSetup)
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
        
        // 5️⃣ 检测方向：扫弦是四根弦依次发声的琶音，方向体现在「音高的走向」上：
        //     向下扫（扫）由缠弦划向子弦，音高由低到高 → 频谱质心上升；
        //     向上扫（拂）由子弦划向缠弦，音高由高到低 → 频谱质心下降。
        //     旧实现拿「本次峰值 vs 上次峰值」比较，与方向毫无物理关系，是判不准的根因。
        let trend = centroidTrend(in: channelData, count: frameLength)
        let direction: SweepDirection
        let directionReliable: Bool
        if let t = trend, abs(t) > trendThreshold {
            direction = t > 0 ? .down : .up
            directionReliable = true
        } else {
            // 走向不明显时按「扫拂交替」推断。扫弦练习基本都是一扫一拂，
            // 这是很强的先验；旧实现被无意义的峰值比较分支抢占，才几乎全判成向下。
            // 但这种方向不可信，标记出来，计算平衡分时不计入。
            direction = inferDirection()
            directionReliable = false
        }
        lastDirection = direction

        if let trend = trend {
            print("   🧭 音高走向: \(String(format: "%+.3f", trend)) → \(direction == .down ? "向下扫（音高由低到高）" : "向上拂（音高由高到低）")")
        } else {
            print("   🧭 音高走向: 信号太弱无法判定，沿用上次方向")
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

    /// 计算一段样本的频谱质心（Hz）。质心越高说明高频能量占比越大、音高越高。
    private func spectralCentroid(of data: UnsafePointer<Float>) -> Float {
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hamm_window(&window, vDSP_Length(fftSize), 0)

        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(data, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // 输入与输出必须用不同的数组：同一个数组既作 in 又作 out 会触发 Swift 的
        // 独占访问检查（Debug 下运行时崩溃、Release 下直接编译不过）。
        var inputReal = windowed
        var inputImag = [Float](repeating: 0, count: fftSize)
        vDSP_DFT_Execute(fftSetup, &inputReal, &inputImag, &realBuffer, &imagBuffer)

        let half = fftSize / 2
        let resolution = Float(sampleRate) / Float(fftSize)
        var weighted: Float = 0
        var total: Float = 0
        for i in 0..<half {
            let real = realBuffer[i]
            let imag = imagBuffer[i]
            let mag = sqrt(real * real + imag * imag)
            magnitudes[i] = mag
            weighted += Float(i) * resolution * mag
            total += mag
        }
        return total > 0 ? weighted / total : 0
    }

    /// 扫弦窗内的音高走向（相对值）：
    /// >0 表示质心上升（音高由低到高，缠弦→子弦，即向下扫 / 扫）；
    /// <0 表示质心下降（音高由高到低，子弦→缠弦，即向上扫 / 拂）。
    /// 把窗切成若干子块逐块算质心，再比较前后半的均值差。
    private func centroidTrend(in data: UnsafePointer<Float>, count: Int) -> Float? {
        let blockCount = count / fftSize
        let half = blockCount / 2
        guard half >= 1 else { return nil }

        var centroids: [Float] = []
        centroids.reserveCapacity(blockCount)
        for b in 0..<blockCount {
            centroids.append(spectralCentroid(of: data + b * fftSize))
        }

        let first = centroids.prefix(half).reduce(0, +) / Float(half)
        let second = centroids.suffix(half).reduce(0, +) / Float(half)
        let mean = centroids.reduce(0, +) / Float(blockCount)
        guard mean > 80 else { return nil } // 能量太低，走向不可信
        return (second - first) / mean
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

        // 方向平衡：只有音频「音高走向」能可靠判定方向时，交替才有意义。
        // 判不出走向时 inferDirection 会强制交替，若把这种不可信方向也算进去，
        // 序列就一直「看起来完美交替」→ 平衡永远 100%。所以平衡只统计可信判定，
        // 再乘「可信率」：判不出的越多，平衡分越低，彻底杜绝虚高。
        var directionBalance: Double
        let reliable = sweepHistory.filter { $0.directionReliable }
        let rc = reliable.count
        if sweepHistory.count < 2 {
            directionBalance = 0.5
        } else if rc < 2 {
            // 方向大多判不出，不给高分（最多 0.5，且随可判定比例进一步压低）
            directionBalance = 0.5 * Double(rc) / Double(sweepHistory.count)
        } else {
            let rUp = reliable.filter { $0.direction == .up }.count
            let rDown = rc - rUp
            let countBalance = 2.0 * Double(min(rUp, rDown)) / Double(rc)
            var transitions = 0
            for i in 1..<rc {
                if reliable[i].direction != reliable[i - 1].direction {
                    transitions += 1
                }
            }
            let alternation = Double(transitions) / Double(rc - 1)
            let reliability = Double(rc) / Double(sweepHistory.count)
            directionBalance = min(1.0, reliability * countBalance * alternation)
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
    /// 方向是否由音频「音高走向」可靠判定；false 表示退回了「强制交替」兜底，
    /// 该次方向不可信，计算方向平衡时应排除。
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
    /// 方向平衡度（0-1）：只在音频能可靠判定方向时才计分，判不出的次数越多平衡分越低，
    /// 避免「强制交替」兜底把平衡永远顶到 100%。算法见 SweepDetector.getStatistics。
    let directionBalance: Double
}
