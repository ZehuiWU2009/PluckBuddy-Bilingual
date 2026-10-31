//
//  PitchDetector.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/7/15.
//

import Foundation
import AVFoundation
import Accelerate

/// 基于 FFT 的音高检测器 - 100% Apple 原生实现
/// 使用 Accelerate 框架进行快速傅里叶变换
class PitchDetector {
    
    // MARK: - Configuration
    private let sampleRate: Double
    private let bufferSize: Int
    
    // MARK: - FFT Setup
    private let fftSetup: vDSP_DFT_Setup
    private let log2n: vDSP_Length
    
    // 工作缓冲区（重用以提高性能）
    private var realBuffer: [Float]
    private var imagBuffer: [Float]
    private var magnitudes: [Float]
    
    // 平滑滤波器（减少抖动）
    private var frequencyHistory: [Double] = []
    private let historySize = 5 // 保存最近 5 次检测结果
    
    // MARK: - Initialization
    init(sampleRate: Double = 48000.0, bufferSize: Int = 4096) {
        self.sampleRate = sampleRate
        self.bufferSize = bufferSize
        
        // 计算 log2(bufferSize)
        self.log2n = vDSP_Length(log2(Float(bufferSize)))
        
        // 创建 FFT setup（DFT 用于实数输入）
        guard let setup = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(bufferSize),
            vDSP_DFT_Direction.FORWARD
        ) else {
            fatalError("Failed to create FFT setup")
        }
        self.fftSetup = setup
        
        // 预分配缓冲区
        self.realBuffer = [Float](repeating: 0, count: bufferSize)
        self.imagBuffer = [Float](repeating: 0, count: bufferSize)
        self.magnitudes = [Float](repeating: 0, count: bufferSize / 2)
    }
    
    deinit {
        vDSP_DFT_DestroySetup(fftSetup)
    }
    
    // MARK: - Pitch Detection
    /// 从音频缓冲区检测音高（Hz）
    /// - Parameter buffer: PCM 音频缓冲区
    /// - Returns: 检测到的频率（Hz），如果无法检测返回 nil
    func detectPitch(from buffer: AVAudioPCMBuffer) -> Double? {
        guard let channelData = buffer.floatChannelData?[0] else {
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        guard frameLength >= bufferSize else { return nil }
        
        // 1️⃣ 计算 RMS 检查信号能量
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        
        // 能量阈值（避免检测噪声）
        guard rms > 0.01 else { return nil }
        
        // 2️⃣ 应用汉明窗（减少频谱泄漏）
        var windowedSignal = [Float](repeating: 0, count: bufferSize)
        vDSP_vmul(
            channelData, 1,
            createHammingWindow(), 1,
            &windowedSignal, 1,
            vDSP_Length(bufferSize)
        )
        
        // 3️⃣ 执行 FFT
        realBuffer = windowedSignal
        imagBuffer = [Float](repeating: 0, count: bufferSize)
        
        vDSP_DFT_Execute(
            fftSetup,
            &realBuffer,
            &imagBuffer,
            &realBuffer,
            &imagBuffer
        )
        
        // 4️⃣ 计算幅度谱（magnitude spectrum）
        // magnitude = sqrt(real^2 + imag^2)
        for i in 0..<(bufferSize / 2) {
            let real = realBuffer[i]
            let imag = imagBuffer[i]
            magnitudes[i] = sqrt(real * real + imag * imag)
        }
        
        // 5️⃣ 找到最强的频率峰值
        guard let peakFrequency = findPeakFrequency() else {
            return nil
        }
        
        // 6️⃣ 应用移动平均滤波（减少抖动）
        let smoothedFrequency = smoothFrequency(peakFrequency)
        
        return smoothedFrequency
    }
    
    // MARK: - Helper Methods
    
    /// 平滑频率（移动平均滤波）
    private func smoothFrequency(_ newFrequency: Double) -> Double {
        frequencyHistory.append(newFrequency)
        
        // 限制历史记录大小
        if frequencyHistory.count > historySize {
            frequencyHistory.removeFirst()
        }
        
        // 如果历史记录少于 3 个，直接返回新值
        guard frequencyHistory.count >= 3 else {
            return newFrequency
        }
        
        // 计算中位数（比平均值更能抵抗异常值）
        let sorted = frequencyHistory.sorted()
        let midIndex = sorted.count / 2
        
        if sorted.count % 2 == 0 {
            return (sorted[midIndex - 1] + sorted[midIndex]) / 2.0
        } else {
            return sorted[midIndex]
        }
    }
    
    /// 创建汉明窗
    private func createHammingWindow() -> [Float] {
        var window = [Float](repeating: 0, count: bufferSize)
        vDSP_hamm_window(&window, vDSP_Length(bufferSize), 0)
        return window
    }
    
    /// 找到频谱中的峰值频率（优化版，提高琵琶弦识别准确率）
    private func findPeakFrequency() -> Double? {
        // 琵琶四弦标准频率
        let pipaFreqs = [110.0, 146.83, 164.81, 220.0]
        
        // 为每根弦设置搜索窗口（±20Hz，更精确）
        let searchWindows: [(Double, Double)] = pipaFreqs.map { freq in
            (freq - 20.0, freq + 20.0)
        }
        
        // 频率分辨率
        let freqResolution = sampleRate / Double(bufferSize)
        
        // 在每个窗口中查找峰值
        var candidates: [(frequency: Double, magnitude: Float, windowIndex: Int)] = []
        
        for (windowIndex, window) in searchWindows.enumerated() {
            let minBin = Int(window.0 / freqResolution)
            let maxBin = min(Int(window.1 / freqResolution), bufferSize / 2 - 1)
            
            guard minBin < maxBin else { continue }
            
            // 在窗口内找最大值
            var maxMagnitude: Float = 0.0
            var maxIndex = 0
            
            for i in minBin...maxBin {
                if magnitudes[i] > maxMagnitude {
                    maxMagnitude = magnitudes[i]
                    maxIndex = i
                }
            }
            
            // 抛物线插值提高精度
            let refinedIndex = parabolicInterpolation(index: maxIndex, magnitudes: magnitudes)
            let frequency = refinedIndex * freqResolution
            
            candidates.append((frequency, maxMagnitude, windowIndex))
        }
        
        // 过滤掉幅度太小的候选（提高阈值到 0.2）
        let validCandidates = candidates.filter { $0.magnitude > 0.2 }
        
        guard !validCandidates.isEmpty else { return nil }
        
        // 选择幅度最大的候选
        let best = validCandidates.max(by: { $0.magnitude < $1.magnitude })!
        
        // 额外验证：检查是否有明显的泛音干扰
        if hasHarmonicInterference(frequency: best.frequency, magnitude: best.magnitude) {
            // 如果检测到泛音干扰，尝试找到基频
            if let fundamental = findFundamental(from: best.frequency) {
                return fundamental
            }
        }
        
        return best.frequency
    }
    
    /// 检测泛音干扰
    private func hasHarmonicInterference(frequency: Double, magnitude: Float) -> Bool {
        let freqResolution = sampleRate / Double(bufferSize)
        
        // 检查是否存在强度相近的低频分量（可能是基频）
        let halfFreqBin = Int((frequency / 2.0) / freqResolution)
        
        guard halfFreqBin > 0 && halfFreqBin < magnitudes.count else {
            return false
        }
        
        // 如果半频率处的幅度超过当前幅度的 60%，可能是泛音
        return magnitudes[halfFreqBin] > magnitude * 0.6
    }
    
    /// 从泛音频率找到基频
    private func findFundamental(from harmonic: Double) -> Double? {
        let freqResolution = sampleRate / Double(bufferSize)
        let pipaFreqs = [110.0, 146.83, 164.81, 220.0]
        
        // 尝试除以 2、3 来找基频
        for divisor in 2...3 {
            let possibleFundamental = harmonic / Double(divisor)
            
            // 检查是否接近琵琶标准音
            for standardFreq in pipaFreqs {
                if abs(possibleFundamental - standardFreq) < 10.0 {
                    // 验证这个基频确实存在于频谱中
                    let bin = Int(possibleFundamental / freqResolution)
                    if bin > 0 && bin < magnitudes.count && magnitudes[bin] > 0.1 {
                        return possibleFundamental
                    }
                }
            }
        }
        
        return nil
    }
    
    /// 抛物线插值（提高频率估计精度）
    /// 使用峰值点及其左右邻点拟合抛物线
    private func parabolicInterpolation(index: Int, magnitudes: [Float]) -> Double {
        guard index > 0 && index < magnitudes.count - 1 else {
            return Double(index)
        }
        
        let alpha = magnitudes[index - 1]
        let beta = magnitudes[index]
        let gamma = magnitudes[index + 1]
        
        // 抛物线顶点偏移量
        let offset = 0.5 * (alpha - gamma) / (alpha - 2.0 * beta + gamma)
        
        // 返回精确的 bin 位置（可以是小数）
        return Double(index) + Double(offset)
    }
}

// MARK: - 扩展：频率到音名转换（供调试使用）
extension PitchDetector {
    /// 将频率转换为最接近的音名（用于调试）
    static func frequencyToNote(_ frequency: Double) -> String {
        // A4 = 440Hz 作为参考
        let a4Frequency = 440.0
        
        // 计算与 A4 的半音差
        let semitonesFromA4 = 12.0 * log2(frequency / a4Frequency)
        let roundedSemitones = round(semitonesFromA4)
        
        // 音名数组（从 A 开始）
        let noteNames = ["A", "A#", "B", "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#"]
        
        let noteIndex = (Int(roundedSemitones) + 12 * 10) % 12 // +120 确保正数
        let octave = 4 + Int((roundedSemitones + 0.5) / 12.0)
        
        return "\(noteNames[noteIndex])\(octave)"
    }
}
