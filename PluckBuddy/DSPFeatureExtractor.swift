//
//  DSPFeatureExtractor.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/10/1.
//
//  基于 PipaDetection 方案的 DSP 特征提取器
//  提取琵琶声特征：基频、谐波比、频谱质心、起音检测、包络衰减
//

import Foundation
import AVFoundation
import Accelerate

/// DSP 特征提取器
class DSPFeatureExtractor {
    
    // MARK: - Configuration
    private let fftSize: Int
    private var sampleRate: Float // ✅ 改为可变，从音频缓冲区读取
    
    // FFT Setup
    private let fftSetup: vDSP_DFT_Setup
    private var realBuffer: [Float]
    private var imagBuffer: [Float]
    private var magnitudes: [Float]
    
    // 历史数据（用于频谱通量）
    private var previousMagnitudes: [Float]?
    
    // MARK: - Initialization
    init(fftSize: Int = 4096) {
        self.fftSize = fftSize
        self.sampleRate = 48000.0 // ✅ 默认值，会在首次处理时更新
        
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
    
    // MARK: - Feature Extraction
    
    /// 处理音频缓冲区,提取所有特征 - 优化版（增加低音预处理）
    func process(buffer: AVAudioPCMBuffer) -> DSPFeatures {
        guard let channelData = buffer.floatChannelData?[0] else {
            return DSPFeatures()
        }
        
        // ✅ 从缓冲区读取实际采样率
        let actualSampleRate = Float(buffer.format.sampleRate)
        if actualSampleRate != sampleRate {
            sampleRate = actualSampleRate
            print("✅ DSP 采样率已更新: \(sampleRate) Hz")
        }
        
        let frameLength = Int(buffer.frameLength)
        guard frameLength >= fftSize else {
            return DSPFeatures()
        }
        
        // 1. 计算 RMS
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        
        // 静音检测（降低阈值以支持低音弦）
        guard rms > 0.003 else { // 从 0.005 降到 0.003
            return DSPFeatures(rms: rms)
        }
        
        // 2. 自相关法检测基频（比 FFT 更准确）
        let pitchHz = detectPitchAutocorrelation(channelData: channelData, frameLength: frameLength)
        
        // 3. FFT 分析
        performFFT(channelData: channelData)
        
        // 4. 谐波能量比
        let harmonicRatio = calculateHarmonicRatio(fundamentalHz: pitchHz)
        
        // 5. 频谱质心
        let spectralCentroid = calculateSpectralCentroid()
        
        // 6. 频谱通量（起音检测）
        let spectralFlux = calculateSpectralFlux()
        
        // 7. 包络衰减特征
        let envelope = calculateEnvelope(channelData: channelData, frameLength: frameLength)
        
        return DSPFeatures(
            rms: rms,
            pitchHz: pitchHz,
            harmonicRatio: harmonicRatio,
            spectralCentroid: spectralCentroid,
            spectralFlux: spectralFlux,
            attackRatio: envelope.attackRatio,
            decaySlope: envelope.decaySlope
        )
    }
    
    /// 计算琵琶声分数（0-1）- 优化版，对低音弦（A弦110Hz）更友好
    func pipaScore(_ features: DSPFeatures) -> Float {
        var score: Float = 0.0
        var weights: Float = 0.0
        
        // 1. RMS 能量检查（降低阈值，A弦能量可能较弱）
        if features.rms > 0.01 { // 从 0.015 降到 0.01
            score += 0.15
        }
        weights += 0.15
        
        // 2. 基频范围检查 - 优化版（针对琵琶四弦：A=110, d=147, e=165, a=220）
        if features.pitchHz > 0 {
            let freq = features.pitchHz
            
            // 精确匹配琵琶四弦的标准音高（±15Hz容差）
            let pipaStrings = [110.0, 146.83, 164.81, 220.0]
            var bestMatch: Float = 0.0
            
            for standardFreq in pipaStrings {
                let deviation = abs(freq - Float(standardFreq))
                if deviation < 15.0 {
                    // 越接近标准音，分数越高
                    bestMatch = max(bestMatch, 1.0 - deviation / 15.0)
                }
            }
            
            if bestMatch > 0.5 {
                score += 0.25 * bestMatch // 精确匹配标准音
            } else if freq >= 90 && freq <= 250 {
                score += 0.15 // 在合理范围内
            } else if freq >= 80 && freq <= 400 {
                score += 0.08 // 扩展范围
            }
        }
        weights += 0.25
        
        // 3. 谐波能量比（低音弦谐波可能较弱，降低阈值）
        if features.harmonicRatio > 0.2 { // 从 0.3 降到 0.2
            score += 0.2 * min(1.0, features.harmonicRatio / 0.5) // 从 0.6 降到 0.5
        }
        weights += 0.2
        
        // 4. 频谱质心（琵琶声能量集中在低频，对低音弦更宽容）
        if features.spectralCentroid < 1000 { // 从 800 提高到 1000
            score += 0.15 * (1.0 - features.spectralCentroid / 2000) // 从 1600 提高到 2000
        }
        weights += 0.15
        
        // 5. 起音特征（琵琶有明显弹拨起音，降低阈值）
        if features.spectralFlux > 0.12 { // 从 0.18 降到 0.12
            score += 0.1 * min(1.0, features.spectralFlux / 0.25)
        }
        weights += 0.1
        
        // 6. 包络特征（快速攻击 + 缓慢衰减，对低音弦更宽容）
        if features.attackRatio < 0.35 && features.decaySlope < -0.05 { // 放宽条件
            score += 0.15
        } else if features.attackRatio < 0.4 { // 至少要有快速攻击
            score += 0.08
        }
        weights += 0.15
        
        return min(1.0, score / weights)
    }
    
    // MARK: - Private Methods
    
    /// YIN 算法检测基频（专业调音器级别的精度，±0.05-0.2 Hz）
    /// 优化版：对低音（A弦110Hz）更敏感
    private func detectPitchAutocorrelation(channelData: UnsafePointer<Float>, frameLength: Int) -> Float {
        let halfLength = frameLength / 2
        let minPeriod = Int(sampleRate / 1700) // 最高 1700Hz
        let maxPeriod = min(Int(sampleRate / 80), halfLength) // 降低到 80Hz，更好支持A弦
        let threshold: Float = 0.15 // 从 0.1 提高到 0.15，对低音更宽容
        
        // 1️⃣ 计算差分函数（Difference Function）
        var difference = [Float](repeating: 0, count: halfLength)
        for tau in 0..<halfLength {
            var sum: Float = 0.0
            for i in 0..<halfLength {
                if i + tau < frameLength {
                    let delta = channelData[i] - channelData[i + tau]
                    sum += delta * delta
                }
            }
            difference[tau] = sum
        }
        
        // 2️⃣ 累积平均归一化（Cumulative Mean Normalized Difference）
        var cumulativeSum: Float = 0.0
        var normalizedDifference = [Float](repeating: 1.0, count: halfLength)
        normalizedDifference[0] = 1.0
        
        for tau in 1..<halfLength {
            cumulativeSum += difference[tau]
            if cumulativeSum > 0 {
                normalizedDifference[tau] = difference[tau] * Float(tau) / cumulativeSum
            }
        }
        
        // 3️⃣ 在有效范围内找到第一个低于阈值的谷（最小值）
        var tau = minPeriod
        while tau < maxPeriod {
            if normalizedDifference[tau] < threshold {
                // 找到局部最小值
                while tau + 1 < maxPeriod && normalizedDifference[tau + 1] < normalizedDifference[tau] {
                    tau += 1
                }
                break
            }
            tau += 1
        }
        
        // 如果没找到有效的周期
        guard tau < maxPeriod else { return 0 }
        
        // 4️⃣ 抛物线插值（Parabolic Interpolation）提高精度
        if tau > 0 && tau < halfLength - 1 {
            let alpha = normalizedDifference[tau - 1]
            let beta = normalizedDifference[tau]
            let gamma = normalizedDifference[tau + 1]
            
            // 防止除零
            let denominator = 2.0 * (alpha - 2.0 * beta + gamma)
            if abs(denominator) > 0.00001 {
                let offset = (alpha - gamma) / denominator
                let refinedTau = Float(tau) + offset
                
                // 验证结果合理性
                if refinedTau > Float(minPeriod) && refinedTau < Float(maxPeriod) {
                    return sampleRate / refinedTau
                }
            }
        }
        
        return sampleRate / Float(tau)
    }
    
    /// 执行 FFT
    private func performFFT(channelData: UnsafePointer<Float>) {
        // 应用汉明窗
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hamm_window(&window, vDSP_Length(fftSize), 0)
        
        var windowedSignal = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(channelData, 1, window, 1, &windowedSignal, 1, vDSP_Length(fftSize))
        
        // FFT
        realBuffer = windowedSignal
        imagBuffer = [Float](repeating: 0, count: fftSize)
        
        vDSP_DFT_Execute(fftSetup, &realBuffer, &imagBuffer, &realBuffer, &imagBuffer)
        
        // 计算幅度
        for i in 0..<(fftSize / 2) {
            let real = realBuffer[i]
            let imag = imagBuffer[i]
            magnitudes[i] = sqrt(real * real + imag * imag)
        }
    }
    
    /// 计算谐波能量比 - 优化版（对低音弦更友好）
    private func calculateHarmonicRatio(fundamentalHz: Float) -> Float {
        guard fundamentalHz > 0 else { return 0 }
        
        let freqResolution = sampleRate / Float(fftSize)
        let f0Bin = Int(fundamentalHz / freqResolution)
        
        guard f0Bin > 0 && f0Bin < magnitudes.count else { return 0 }
        
        // 提取基频和前 4 个谐波的能量
        var harmonicEnergy: Float = 0.0
        var totalEnergy: Float = 0.0
        
        for i in 0..<magnitudes.count {
            totalEnergy += magnitudes[i] * magnitudes[i]
        }
        
        // 对低音（A弦110Hz）增加容差范围
        let binTolerance = fundamentalHz < 130 ? 3 : 2 // A弦用±3，其他用±2
        
        // 基频及谐波（动态调整容差）
        for h in 1...5 {
            let hBin = f0Bin * h
            if hBin < magnitudes.count {
                let start = max(0, hBin - binTolerance)
                let end = min(magnitudes.count - 1, hBin + binTolerance)
                for i in start...end {
                    harmonicEnergy += magnitudes[i] * magnitudes[i]
                }
            }
        }
        
        return totalEnergy > 0 ? harmonicEnergy / totalEnergy : 0
    }
    
    /// 计算频谱质心（Hz）
    private func calculateSpectralCentroid() -> Float {
        var weightedSum: Float = 0.0
        var magnitudeSum: Float = 0.0
        
        let freqResolution = sampleRate / Float(fftSize)
        
        for i in 0..<magnitudes.count {
            let freq = Float(i) * freqResolution
            weightedSum += freq * magnitudes[i]
            magnitudeSum += magnitudes[i]
        }
        
        return magnitudeSum > 0 ? weightedSum / magnitudeSum : 0
    }
    
    /// 计算频谱通量（起音检测）
    private func calculateSpectralFlux() -> Float {
        guard let prev = previousMagnitudes else {
            previousMagnitudes = magnitudes
            return 0
        }
        
        var flux: Float = 0.0
        for i in 0..<min(magnitudes.count, prev.count) {
            let diff = magnitudes[i] - prev[i]
            if diff > 0 {
                flux += diff
            }
        }
        
        previousMagnitudes = magnitudes
        
        // 归一化
        let maxFlux: Float = 100.0
        return min(1.0, flux / maxFlux)
    }
    
    /// 计算包络特征
    private func calculateEnvelope(channelData: UnsafePointer<Float>, frameLength: Int) -> (attackRatio: Float, decaySlope: Float) {
        // 找到峰值位置
        var peakIndex = 0
        var peakValue: Float = 0.0
        
        for i in 0..<frameLength {
            let absValue = abs(channelData[i])
            if absValue > peakValue {
                peakValue = absValue
                peakIndex = i
            }
        }
        
        let attackRatio = Float(peakIndex) / Float(frameLength)
        
        // 计算衰减斜率（峰值后）
        var decaySlope: Float = 0.0
        if peakIndex < frameLength - 100 {
            let decayStart = peakValue
            let decayEnd = abs(channelData[min(peakIndex + 100, frameLength - 1)])
            decaySlope = (decayEnd - decayStart) / Float(100)
        }
        
        return (attackRatio, decaySlope)
    }
}

// MARK: - DSP Features
struct DSPFeatures {
    let rms: Float                    // 均方根能量
    let pitchHz: Float                // 基频（自相关法）
    let harmonicRatio: Float          // 谐波能量比
    let spectralCentroid: Float       // 频谱质心
    let spectralFlux: Float           // 频谱通量（起音强度）
    let attackRatio: Float            // 攻击时间占比
    let decaySlope: Float             // 衰减斜率
    
    init(
        rms: Float = 0,
        pitchHz: Float = 0,
        harmonicRatio: Float = 0,
        spectralCentroid: Float = 0,
        spectralFlux: Float = 0,
        attackRatio: Float = 0,
        decaySlope: Float = 0
    ) {
        self.rms = rms
        self.pitchHz = pitchHz
        self.harmonicRatio = harmonicRatio
        self.spectralCentroid = spectralCentroid
        self.spectralFlux = spectralFlux
        self.attackRatio = attackRatio
        self.decaySlope = decaySlope
    }
}
