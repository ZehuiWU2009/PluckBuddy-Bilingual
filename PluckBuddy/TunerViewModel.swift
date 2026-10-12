//
//  TunerViewModel.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/7/15.
//

import Foundation
import AVFoundation
import Combine

@MainActor
class TunerViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var detectedNote: String = "—"
    @Published var frequency: Double = 0.0
    @Published var centOffset: Double = 0.0
    @Published var isTuned: Bool = false
    @Published var tuningMessage: String = L("请弹奏琴弦")
    @Published var confidence: Double = 0.0 // 检测置信度
    @Published var waveformData: [Float] = Array(repeating: 0, count: 100) // 波形数据
    @Published var amplitudeLevel: Float = 0.0 // 当前振幅等级（用于可视化）
    @Published var pipaFilterEnabled: Bool = true // ✅ 琵琶声过滤开关（默认开启；通过 CoreML PipaSoundClassifier 做端侧四分类，门控音高判定）
    @Published var pipaSoundDetected: Bool = false // ✅ CoreML 判门最新输出（最近一次推理是否判为琵琶），供界面反馈
    @Published var pipaScoreValue: Double = 0.0 // ✅ CoreML 判门最新输出（pipa 概率，平滑后），供界面反馈
    @Published var pipaGateAvailable: Bool = false // ✅ CoreML 判门是否可用；不可用时界面上明确告诉用户降级为通用模式
    
    // 稳定性控制
    private var stableCount: Int = 0
    private let stableThreshold = 2 // 降低到 2 次，提高响应速度
    
    // 频率显示持久化
    private var lastValidFrequency: Double = 0.0
    private var lastDetectionTime: Date?
    private let displayTimeout: TimeInterval = 3.0 // 3秒后才清除显示
    
    // ✅ 把 pipaGate 的 Published 转播到 ViewModel 上，让 View 不必直接观察 pipaGate
    private var pipaGateCancellables = Set<AnyCancellable>()
    
    // MARK: - Pipa Standard Tuning
    struct PipaString {
        let name: String
        let frequency: Double
    }
    
    /// 按弦号 1 → 4 排列：1 弦（子弦）最细、音最高，4 弦（缠弦）最粗、音最低。
    /// 界面从左到右依次渲染，因此这里的顺序必须和「1弦、2弦、3弦、4弦」一致。
    static let pipaStrings: [PipaString] = [
        PipaString(name: "a", frequency: 220.0),  // 1弦 子弦 a3
        PipaString(name: "e", frequency: 164.81), // 2弦 中弦 e3
        PipaString(name: "d", frequency: 146.83), // 3弦 老弦 d3
        PipaString(name: "A", frequency: 110.0)   // 4弦 缠弦 A2
    ]
    
    // MARK: - Audio Components
    private var audioManager: AudioManager?
    private var pitchDetector: PitchDetector?
    private var dspExtractor: DSPFeatureExtractor? // 保留 DSP 提取器（仅给波形用，不参与门控）
    private let pipaGate = PipaSoundGate() // ✅ CoreML 琵琶声判门（端侧推理，与 AudioManager 共用麦克风源，不另起 AVAudioEngine）
    
    // MARK: - Init
    init() {
        pipaGateAvailable = pipaGate.isAvailable
        // 把判门状态转播到 ViewModel 的 Published（让 View 一次性观察 viewModel 即可）
        pipaGate.$isPipa
            .receive(on: DispatchQueue.main)
            .sink { [weak self] detected in self?.pipaSoundDetected = detected }
            .store(in: &pipaGateCancellables)
        pipaGate.$pipaProb
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prob in self?.pipaScoreValue = prob }
            .store(in: &pipaGateCancellables)
    }
    
    // MARK: - Lifecycle
    func startListening() {
        Task { [weak self] in
            guard let self = self else { return }
            // 请求麦克风权限
            audioManager = AudioManager.shared
            guard let manager = audioManager else { return }
            
            let hasPermission = await manager.requestMicrophonePermission()
            guard hasPermission else {
                tuningMessage = L("需要麦克风权限来检测音高")
                return
            }
            
            // 初始化音高检测器
            pitchDetector = PitchDetector(sampleRate: 48000.0, bufferSize: 4096)
            
            // ✅ 初始化专业琵琶声检测器
            dspExtractor = DSPFeatureExtractor(fftSize: 4096)
            
            // 启动音频输入
            do {
                try manager.startListening { [weak self] buffer, _ in
                    guard let self = self,
                          let detector = self.pitchDetector else { return }
                    
                    // 更新波形数据
                    Task { @MainActor in
                        self.updateWaveform(from: buffer)
                    }
                    
                    // ✅ 把缓冲同时喂给 CoreML 判门（异步：降采样+累积+推理都在后台队列，不阻塞音频回调）
                    self.pipaGate.feed(buffer: buffer)
                    
                    // 计算频谱特征（仅用于音高检测）
                    guard let dsp = self.dspExtractor else { return }
                    let features = dsp.process(buffer: buffer)
                    
                    // ✅ 门控：开「琵琶模式」时，要求 CoreML 在最近 0.5 秒内判定为「琵琶声」；
                    //           关「琵琶模式」或模型加载失败时 → 全放行（与原来行为一致）。
                    let gatePassed = self.pipaFilterEnabled ? self.pipaGate.isPipaRecent(within: 0.5) : true
                    
                    // RMS 能量 + 音高范围过滤明显噪声
                    let shouldProcess = gatePassed && features.rms > 0.008 && features.pitchHz > 80
                    
                    // 反馈：开了过滤但当前帧不在「最近 0.5s 判为琵琶」的窗口内 → 给个等待提示
                    if self.pipaFilterEnabled && !self.pipaGate.isPipaRecent(within: 0.5) && features.rms > 0.008 {
                        Task { @MainActor in
                            self.tuningMessage = L("正在聆听…请弹奏琵琶")
                        }
                    }
                    
                    guard shouldProcess else {
                        Task { @MainActor in
                            self.checkDisplayTimeout()
                        }
                        return
                    }
                    
                    // 优先使用 DSP 检测的基频（更准确）
                    let frequency = features.pitchHz > 0 ? Double(features.pitchHz) : nil
                    
                    if let freq = frequency {
                        Task { @MainActor in
                            self.processPitch(freq)
                        }
                    } else {
                        // DSP 没检测到，尝试 FFT 方法
                        if let freq = detector.detectPitch(from: buffer) {
                            Task { @MainActor in
                                self.processPitch(freq)
                            }
                        } else {
                            Task { @MainActor in
                                self.checkDisplayTimeout()
                            }
                        }
                    }
                }
            } catch {
                tuningMessage = L("音频引擎启动失败")
                print("Audio error: \(error.localizedDescription)")
            }
        }
    }
    
    func stopListening() {
        audioManager?.stopListening()
        pipaGate.reset() // ✅ 清掉 CoreML 判门的累积和「最近判定」标记
        resetDisplay()
    }
    
    // MARK: - Pitch Processing
    private func processPitch(_ detectedFreq: Double) {
        guard detectedFreq > 0 else {
            return
        }
        
        // 更新检测时间
        lastDetectionTime = Date()
        lastValidFrequency = detectedFreq
        
        frequency = detectedFreq
        
        // 找到最接近的琵琶弦音
        guard let closestString = findClosestString(for: detectedFreq) else {
            return
        }
        
        detectedNote = closestString.name
        
        // 计算音分偏差 (cents)
        // cents = 1200 * log2(detectedFreq / targetFreq)
        centOffset = 1200 * log2(detectedFreq / closestString.frequency)
        
        // 判断是否准确（±10 cents 内算准）
        isTuned = abs(centOffset) < 10
        
        // 更新提示信息
        updateTuningMessage()
    }
    
    /// 检查显示超时（只有在长时间没有检测到声音时才清除）
    private func checkDisplayTimeout() {
        guard let lastTime = lastDetectionTime else { return }
        
        let timeSinceLastDetection = Date().timeIntervalSince(lastTime)
        if timeSinceLastDetection > displayTimeout {
            resetDisplay()
        }
    }
    
    private func findClosestString(for freq: Double) -> PipaString? {
        // 只在合理范围内查找（±100 Hz）
        let candidates = Self.pipaStrings.filter { abs($0.frequency - freq) < 100 }
        return candidates.min(by: { abs($0.frequency - freq) < abs($1.frequency - freq) })
    }
    
    private func updateTuningMessage() {
        if isTuned {
            tuningMessage = L("✓ 音准很好！")
        } else if centOffset > 10 {
            tuningMessage = L("再调低一点 ↓")
        } else if centOffset < -10 {
            tuningMessage = L("再调高一点 ↑")
        } else {
            tuningMessage = L("请弹奏琴弦")
        }
    }
    
    private func resetDisplay() {
        detectedNote = "—"
        frequency = 0.0
        centOffset = 0.0
        isTuned = false
        confidence = 0.0
        tuningMessage = L("请弹奏琴弦")
    }
    
    // MARK: - Waveform Update
    
    /// 更新波形数据（优化版，只对琵琶声响应）
    private func updateWaveform(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        
        // 计算 RMS 振幅等级
        var sum: Float = 0.0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        amplitudeLevel = sqrt(sum / Float(frameLength))
        
        // 琵琶声检测阈值（过滤微弱声音和噪声）
        guard amplitudeLevel > 0.02 else {
            // 能量太低，逐渐衰减波形而不是突然清零
            waveformData = waveformData.map { $0 * 0.8 }
            return
        }
        
        // 计算峰值因子（琵琶声的特征）
        var peak: Float = 0.0
        for i in 0..<frameLength {
            let abs = abs(channelData[i])
            if abs > peak {
                peak = abs
            }
        }
        let peakFactor = peak / (amplitudeLevel + 0.0001)
        
        // 峰值因子检测：琵琶声通常在 3-10 之间
        guard peakFactor > 2.5 && peakFactor < 15.0 else {
            // 不是琵琶声，逐渐衰减
            waveformData = waveformData.map { $0 * 0.85 }
            return
        }
        
        // 降采样到 100 个点（用于波形显示）
        let step = max(1, frameLength / 100)
        var newWaveform: [Float] = []
        
        // 找出最大振幅用于归一化
        var maxAmp: Float = 0.0001 // 避免除零
        for i in stride(from: 0, to: frameLength, by: step) {
            if i < frameLength {
                let amp = abs(channelData[i])
                if amp > maxAmp {
                    maxAmp = amp
                }
            }
        }
        
        // 归一化并采样（降低放大倍数，减少闪烁）
        for i in stride(from: 0, to: frameLength, by: step) {
            if i < frameLength {
                // 归一化到 -1.0 到 1.0 范围，放大 1.5 倍（之前是 2.0）
                let normalized = (channelData[i] / maxAmp) * 1.5
                newWaveform.append(min(1.0, max(-1.0, normalized)))
            }
        }
        
        // 确保正好 100 个点
        while newWaveform.count < 100 {
            newWaveform.append(0)
        }
        if newWaveform.count > 100 {
            newWaveform = Array(newWaveform.prefix(100))
        }
        
        // 平滑处理：与之前的波形混合（减少闪烁）
        if waveformData.count == newWaveform.count {
            for i in 0..<waveformData.count {
                waveformData[i] = waveformData[i] * 0.6 + newWaveform[i] * 0.4
            }
        } else {
            waveformData = newWaveform
        }
    }
    
    // MARK: - Pipa Sound Detection
    
    /// 判断是否为琵琶声（核心识别算法）
    private func isPipaSound(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData?[0] else { return false }
        let frameLength = Int(buffer.frameLength)
        
        // 1️⃣ 计算 RMS 能量
        var sum: Float = 0.0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(frameLength))
        
        // 能量阈值：过滤太微弱的声音
        guard rms > 0.015 else { return false }
        
        // 2️⃣ 计算峰值因子（Crest Factor）
        var peak: Float = 0.0
        for i in 0..<frameLength {
            let absValue = abs(channelData[i])
            if absValue > peak {
                peak = absValue
            }
        }
        let crestFactor = peak / (rms + 0.0001) // 避免除零
        
        // 琵琶声的峰值因子特征：3-12
        // - 说话声：< 3（能量分布均匀）
        // - 琵琶声：3-12（有明显的攻击峰值）
        // - 噪声/爆破音：> 15（瞬间峰值过大）
        guard crestFactor >= 2.8 && crestFactor <= 15.0 else {
            return false
        }
        
        // 3️⃣ 过零率检测（Zero-Crossing Rate）
        // 琵琶声的过零率相对稳定
        var zeroCrossings = 0
        for i in 1..<frameLength {
            if (channelData[i] >= 0 && channelData[i-1] < 0) ||
               (channelData[i] < 0 && channelData[i-1] >= 0) {
                zeroCrossings += 1
            }
        }
        let zcr = Float(zeroCrossings) / Float(frameLength)
        
        // 过零率范围：0.05-0.3（琵琶音调较低，过零率不会太高）
        // - 说话声：0.1-0.5（变化大）
        // - 琵琶声：0.05-0.25（相对稳定）
        // - 噪声：> 0.4（过零频繁）
        guard zcr >= 0.03 && zcr <= 0.35 else {
            return false
        }
        
        // 4️⃣ 频谱集中度检测
        // 琵琶声能量集中在低频（100-300Hz 范围）
        // 使用简单的频段能量比较
        
        // 分段计算能量（低频/中频/高频）
        let segment = frameLength / 3
        
        var lowEnergy: Float = 0.0
        for i in 0..<segment {
            lowEnergy += channelData[i] * channelData[i]
        }
        
        var midEnergy: Float = 0.0
        for i in segment..<(segment * 2) {
            midEnergy += channelData[i] * channelData[i]
        }
        
        var highEnergy: Float = 0.0
        for i in (segment * 2)..<frameLength {
            highEnergy += channelData[i] * channelData[i]
        }
        
        let totalEnergy = lowEnergy + midEnergy + highEnergy + 0.0001
        let lowRatio = lowEnergy / totalEnergy
        
        // 琵琶声特征：低频能量占比 > 25%
        // 说话声和噪声的低频占比通常较小
        guard lowRatio > 0.2 else {
            return false
        }
        
        // 5️⃣ 衰减特征检测（Attack-Decay）
        // 琵琶声有明显的快速攻击和缓慢衰减
        
        // 找到最大振幅位置
        var peakIndex = 0
        var peakValue: Float = 0.0
        for i in 0..<frameLength {
            let absValue = abs(channelData[i])
            if absValue > peakValue {
                peakValue = absValue
                peakIndex = i
            }
        }
        
        // 计算攻击时间占比（从开始到峰值）
        let attackRatio = Float(peakIndex) / Float(frameLength)
        
        // 琵琶声特征：攻击阶段很短（< 30%），然后是长衰减
        // 说话声：攻击分布较均匀
        guard attackRatio < 0.4 else {
            return false
        }
        
        // ✅ 通过所有检测，判定为琵琶声
        return true
    }
}
