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
    private let stableThreshold = 2 // 连续两次判到同一根弦才高亮，避免谐波误判时闪烁
    private var lastCandidateName: String?

    // 频率显示持久化
    private var lastValidFrequency: Double = 0.0
    private var lastDetectionTime: Date?
    private let displayTimeout: TimeInterval = 3.0 // 3秒后才清除显示

    // ✅ 把 pipaGate 的 Published 转播到 ViewModel 上，让 View 不必直接观察 pipaGate
    private var pipaGateCancellables = Set<AnyCancellable>()

    // MARK: - 分析管线常量
    /// 音高分析窗长。tap 下发的缓冲帧数不保证等于请求值（可能更小），
    /// 因此先把样本累积满一个固定窗口再分析，避免按原始缓冲直接分析时
    /// 「帧数不足 → DSP 与备用检测器同时静默返回空」导致调音毫无反馈。
    private let analysisWindowSize = 4096
    /// 有声判定门限（RMS）。真琵琶近手机弹奏约 0.05~0.3，留了很大余量。
    private let soundFloor: Float = 0.004
    /// 判门有效期。判门推理节拍约 0.5s 一次，窗口给到 0.8s 容忍推理耗时与派发抖动。
    private let gateValidityWindow: TimeInterval = 0.8
    /// 音分匹配上限：超出 ±700 音分视为「不是这四根弦」。
    private let maxCentsDeviation: Double = 700
    /// 八度候选的罚分：同分时优先原频率匹配，只有八度误判明显更准时才改判。
    private let octavePenalty: Double = 2.0

    // MARK: - 运行期状态
    /// 尚未凑满一个分析窗的样本累积区（只在音频回调线程访问）
    private var pendingSamples: [Float] = []
    /// 最近一次从缓冲读到的采样率（分析时按它重建 AVAudioPCMBuffer）
    private var lastSampleRate: Double = 48000.0
    /// 分析计数，仅用于诊断日志节流
    private var analysisCounter: Int = 0

    // MARK: - Pipa Standard Tuning
    struct PipaString {
        /// 音名，用于与检测结果匹配
        let name: String
        /// 传统弦名，界面直接显示
        let traditionalName: String
        let frequency: Double
    }

    /// 按音高由高到低排列：子弦最细、音最高，缠弦最粗、音最低。
    /// 界面从左到右依次渲染，与「子弦、中弦、老弦、缠弦」的传统称谓顺序一致。
    static let pipaStrings: [PipaString] = [
        PipaString(name: "a", traditionalName: "子弦", frequency: 220.0),  // a3
        PipaString(name: "e", traditionalName: "中弦", frequency: 164.81), // e3
        PipaString(name: "d", traditionalName: "老弦", frequency: 146.83), // d3
        PipaString(name: "A", traditionalName: "缠弦", frequency: 110.0)   // A2
    ]

    /// 弦匹配结果：命中的弦、按八度校正后的目标频率、以及相对该目标的音分偏差
    private struct StringMatch {
        let string: PipaString
        let targetFrequency: Double
        let cents: Double
        let score: Double
    }

    // MARK: - Audio Components
    private var audioManager: AudioManager?
    private var dspExtractor: DSPFeatureExtractor? // 持久化的特征提取器（FFT 设置较重，每窗重建太浪费）
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

            // 初始化特征提取器（持久化，避免每个分析窗重建 FFT 设置）
            dspExtractor = DSPFeatureExtractor(fftSize: analysisWindowSize)

            let hasPermission = await manager.requestMicrophonePermission()
            guard hasPermission else {
                tuningMessage = L("需要麦克风权限来检测音高")
                return
            }

            // 启动音频输入
            do {
                try manager.startListening { [weak self] buffer, _ in
                    guard let self = self else { return }

                    // ✅ 判门喂料放在最前（它自带格式适配，即使后续解析失败也不影响判门工作）
                    self.pipaGate.feed(buffer: buffer)

                    // 样本立即拷贝：AVAudioPCMBuffer 只在回调内存活，
                    // 原先把 buffer 带进 Task 晚读属于 use-after-free，改为传副本
                    guard let samples = TunerViewModel.monoSamples(from: buffer) else { return }

                    Task { @MainActor in
                        self.updateWaveform(samples: samples)
                    }

                    // 累积到固定窗长再测音高（详见 analysisWindowSize 注释）
                    self.ingest(samples: samples, sampleRate: buffer.format.sampleRate)
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
        dspExtractor = nil // 释放 FFT 设置
        pendingSamples.removeAll()
        lastCandidateName = nil
        stableCount = 0
        analysisCounter = 0
        resetDisplay()
    }

    // MARK: - 样本累积与音高分析

    /// 把回调样本追加进累积区，凑满一个分析窗就跑一次音高检测
    private func ingest(samples: [Float], sampleRate: Double) {
        if sampleRate > 0 { lastSampleRate = sampleRate }
        pendingSamples.append(contentsOf: samples)
        guard pendingSamples.count >= analysisWindowSize else { return }

        let window = Array(pendingSamples.prefix(analysisWindowSize))
        pendingSamples.removeFirst(analysisWindowSize)
        // 防止极端情况下积压（回调远快于分析时）
        if pendingSamples.count > analysisWindowSize * 4 {
            pendingSamples.removeFirst(pendingSamples.count - analysisWindowSize)
        }
        analyzeWindow(window)
    }

    /// 在音频回调线程上同步执行（与旧实现同线程，不新增并发面）
    private func analyzeWindow(_ window: [Float]) {
        guard let buffer = Self.makePCMBuffer(samples: window, sampleRate: lastSampleRate) else { return }
        guard let dsp = dspExtractor else { return }

        let features = dsp.process(buffer: buffer)

        let gatePassed = pipaFilterEnabled ? pipaGate.isPipaRecent(within: gateValidityWindow) : true
        let pipaProb = pipaScoreValue
        let hasSound = features.rms > soundFloor

        // 诊断日志（节流到约每秒一条）：真机排障时在 Xcode 控制台即可看完整链路状态
        analysisCounter += 1
        if analysisCounter % 12 == 1 {
            print("🎚 [Tuner] #\(analysisCounter) rms=\(String(format: "%.4f", features.rms)) gate=\(gatePassed ? "✅" : "❌") pipa=\(String(format: "%.2f", pipaProb)) pitch=\(String(format: "%.1f", features.pitchHz)) filter=\(pipaFilterEnabled ? "on" : "off")")
        }

        // 1️⃣ 安静：不产生任何反馈，交给显示超时清理
        guard hasSound else {
            Task { @MainActor in self.checkDisplayTimeout() }
            return
        }

        // 2️⃣ 有声但不是琵琶声（判门未过）：提示继续聆听
        guard gatePassed else {
            Task { @MainActor in
                self.tuningMessage = L("正在聆听…请弹奏琵琶")
                self.checkDisplayTimeout()
            }
            return
        }

        // 3️⃣ 判门通过但测不到音高：与「没听到声音」区分开，便于定位问题
        var detected: Double? = features.pitchHz > 0 ? Double(features.pitchHz) : nil
        if detected == nil {
            let detector = PitchDetector(sampleRate: lastSampleRate, bufferSize: analysisWindowSize)
            detected = detector.detectPitch(from: buffer)
        }
        guard let freq = detected else {
            Task { @MainActor in
                self.tuningMessage = pipaProb >= 0.35 ? L("已检测到琵琶声，正在分析音高…") : L("正在聆听…请弹奏琵琶")
            }
            return
        }

        Task { @MainActor in
            self.processPitch(freq)
        }
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

        // 找到最接近的琵琶弦音（含八度容错）
        guard let match = matchString(for: detectedFreq) else {
            // 音高落在四弦可解释范围之外：只显示频率，不高亮任何弦
            detectedNote = "—"
            centOffset = 0
            isTuned = false
            tuningMessage = L("请弹奏琴弦")
            return
        }

        // 同一根弦连续命中 stableThreshold 次才切换高亮，抑制谐波/八度抖动
        let stable = match.string.name == lastCandidateName ? stableCount + 1 : 1
        stableCount = stable
        lastCandidateName = match.string.name

        guard stable >= stableThreshold else { return }

        detectedNote = match.string.name

        // 计算音分偏差 (cents)
        // cents = 1200 * log2(detectedFreq / targetFreq)
        // 注意 targetFreq 用八度校正后的目标，八度误判时音分才不会飞出量程
        centOffset = match.cents

        // 判断是否准确（±10 cents 内算准）
        isTuned = abs(centOffset) < 10

        // 置信度：越接近标准音越高（驱动界面三颗圆点）
        confidence = max(0, min(1, 1 - abs(centOffset) / 50))

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

    /// 在四根弦里找最接近的匹配。依次考察原频率、低八度、高八度三种目标：
    /// 拨弦声谐波丰富，自相关偶发八度误判，八度候选保证误判时仍落到正确的弦上。
    private func matchString(for freq: Double) -> StringMatch? {
        var best: StringMatch?
        for string in Self.pipaStrings {
            for multiplier in [1.0, 0.5, 2.0] {
                let target = string.frequency * multiplier
                let cents = 1200 * log2(freq / target)
                guard abs(cents) <= maxCentsDeviation else { continue }
                let score = abs(cents) + (multiplier == 1.0 ? 0 : octavePenalty)
                if best == nil || score < best!.score {
                    best = StringMatch(string: string, targetFrequency: target, cents: cents, score: score)
                }
            }
        }
        return best
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
        lastCandidateName = nil
        stableCount = 0
        tuningMessage = L("请弹奏琴弦")
    }

    // MARK: - Waveform Update

    /// 更新波形数据（入参为回调内拷贝的单声道样本，不再直接读 AVAudioPCMBuffer）
    private func updateWaveform(samples: [Float]) {
        let frameLength = samples.count
        guard frameLength > 0 else { return }

        // 计算 RMS 振幅等级
        var sum: Float = 0.0
        for s in samples {
            sum += s * s
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
        for s in samples {
            let absValue = abs(s)
            if absValue > peak {
                peak = absValue
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

        // 找出最大振幅用于归一化
        var maxAmp: Float = 0.0001 // 避免除零
        for i in stride(from: 0, to: frameLength, by: step) {
            let amp = abs(samples[i])
            if amp > maxAmp {
                maxAmp = amp
            }
        }

        // 归一化并采样（降低放大倍数，减少闪烁）
        var newWaveform: [Float] = []
        newWaveform.reserveCapacity(100)
        for i in stride(from: 0, to: frameLength, by: step) {
            // 归一化到 -1.0 到 1.0 范围，放大 1.5 倍（之前是 2.0）
            let normalized = (samples[i] / maxAmp) * 1.5
            newWaveform.append(min(1.0, max(-1.0, normalized)))
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

    // MARK: - 工具：缓冲 → 单声道样本 / 样本 → 缓冲

    /// 把任意 PCM 缓冲混合成单声道 Float 样本（float32 / int16 / int32 通吃）
    private nonisolated static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }

        let channelCount = max(Int(buffer.format.channelCount), 1)
        var mono = [Float](repeating: 0, count: frameCount)

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let data = buffer.floatChannelData else { return nil }
            for channel in 0..<channelCount {
                let source = data[channel]
                for i in 0..<frameCount { mono[i] += source[i] }
            }
        case .pcmFormatInt16:
            guard let data = buffer.int16ChannelData else { return nil }
            for channel in 0..<channelCount {
                let source = data[channel]
                for i in 0..<frameCount { mono[i] += Float(source[i]) / 32768 }
            }
        case .pcmFormatInt32:
            guard let data = buffer.int32ChannelData else { return nil }
            for channel in 0..<channelCount {
                let source = data[channel]
                for i in 0..<frameCount { mono[i] += Float(source[i]) / 2147483648 }
            }
        default:
            return nil
        }

        if channelCount > 1 {
            let scale = 1 / Float(channelCount)
            for i in 0..<frameCount { mono[i] *= scale }
        }
        return mono
    }

    /// 用固定窗长的样本重建一个标准格式的 AVAudioPCMBuffer，供现有检测器使用
    private nonisolated static func makePCMBuffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        let rate = sampleRate > 0 ? sampleRate : 48000.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let destination = buffer.floatChannelData?[0] else { return nil }
        for (index, sample) in samples.enumerated() {
            destination[index] = sample
        }
        return buffer
    }
}
