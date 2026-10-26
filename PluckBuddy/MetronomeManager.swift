//
//  MetronomeManager.swift
//  PluckBuddy
//
//  节拍器管理器 - 优化版（修复声音和性能问题）
//  Created on 2026/8/29.
//

import Foundation
import AVFoundation
import Combine

/// 节拍器音色类型
enum MetronomeSoundType: String, CaseIterable, Identifiable {
    case tick = "滴答"
    case woodblock = "木鱼"
    case drum = "鼓声"
    case mechanical = "机械"
    
    var id: String { rawValue }

    /// 本地化显示名（rawValue 仍作持久化 key，不能改）
    var displayName: String { L(rawValue) }
    
    var icon: String {
        switch self {
        case .tick: return "metronome"
        case .woodblock: return "circle.fill"
        case .drum: return "circle.hexagongrid.fill" // 系统符号库里没有鼓类符号，用鼓面网格替代
        case .mechanical: return "waveform"
        }
    }
}

/// 节拍器管理器（优化版）
@MainActor
class MetronomeManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var bpm: Int = 108 {
        didSet {
            print("🎵 bpm didSet 触发: \(bpm), isPlaying: \(isPlaying)")
            // ✨ 避免无限循环：只在值改变时才修改
            let clampedBPM = max(minBPM, min(maxBPM, bpm))
            if bpm != clampedBPM {
                bpm = clampedBPM
                return // 会再次触发 didSet，所以直接返回
            }
            
            // ✨ 修复：播放时不重启，只更新定时器间隔
            if isPlaying {
                updateTimerInterval()
            }
            print("🎵 bpm didSet 完成")
        }
    }
    
    @Published var isPlaying: Bool = false
    @Published var currentBeat: Int = 0
    @Published var soundType: MetronomeSoundType = .mechanical {
        didSet {
            print("🎨 soundType didSet 触发: \(soundType.rawValue), isAudioEngineReady: \(isAudioEngineReady)")
            // ✨ 只有在音频引擎就绪时才更新声音
            if isAudioEngineReady {
                setupSoundForType(soundType)
            }
            saveSettings()
            print("🎨 soundType didSet 完成")
        }
    }
    @Published var isEnabled: Bool = false
    
    // MARK: - Constants
    
    let minBPM = 36
    let maxBPM = 220
    let beatsPerMeasure = 4
    
    // MARK: - Private Properties
    
    private var timer: Timer?
    private var audioEngine: AVAudioEngine!
    private var playerNode: AVAudioPlayerNode!
    private var tickBuffer: AVAudioPCMBuffer?
    private var tockBuffer: AVAudioPCMBuffer?
    private var isAudioEngineReady = false  // ✨ 标记音频引擎是否就绪
    
    // MARK: - Initialization
    
    init() {
        // ✨ 简化初始化，延迟音频引擎设置到首次使用
        // 避免阻塞主线程
        print("🎵 MetronomeManager init() 开始")
        loadSettings()
        print("🎵 MetronomeManager init() 完成")
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
        playerNode?.stop()
        audioEngine?.stop()
    }
    
    // MARK: - Public Methods
    
    func start() {
        guard !isPlaying else { return }
        
        // ✨ 如果音频引擎未就绪，先尝试初始化
        if !isAudioEngineReady {
            print("⚠️ 音频引擎未就绪，尝试重新初始化...")
            setupAudioEngine()
            setupSoundForType(soundType)  // ✨ 设置当前音色
            isAudioEngineReady = true
            print("✅ 音频引擎初始化完成")
        }
        
        // ✨ 启动音频引擎（如果未运行）
        if audioEngine?.isRunning == false {
            do {
                try audioEngine?.start()
                print("✅ 音频引擎已启动")
            } catch {
                print("❌ 音频引擎启动失败: \(error)")
                return
            }
        }
        
        // ✨ 先启动播放器节点，让它准备好接收缓冲区
        if !playerNode.isPlaying {
            playerNode.play()
            print("✅ 播放器节点已启动")
        }
        
        isPlaying = true
        currentBeat = 0
        
        let interval = 60.0 / Double(bpm)
        
        // ✨ 延迟一小段时间再播放第一个节拍，确保 IO 线程准备好
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            self.playBeat()
            
            // 然后启动定时器
            self.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.playBeat()
                }
            }
        }
        
        print("🎵 节拍器已启动 - BPM: \(bpm)")
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        currentBeat = 0
        playerNode?.stop()
        print("⏹️ 节拍器已停止")
    }
    
    func toggle() {
        isPlaying ? stop() : start()
    }
    
    func increaseBPM() {
        if bpm < maxBPM { bpm += 1 }
    }
    
    func decreaseBPM() {
        if bpm > minBPM { bpm -= 1 }
    }
    
    func setBPM(_ newBPM: Int) {
        bpm = max(minBPM, min(maxBPM, newBPM))
    }
    
    // MARK: - Private Methods
    
    private func setupAudioEngine() {
        // ✨ 不再配置音频会话，因为 AudioManager 已经配置为 .playAndRecord
        // 这样避免了两个管理器之间的冲突
        
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        audioEngine.attach(playerNode)
        
        let mixer = audioEngine.mainMixerNode
        // ✨ 关键修复：使用引擎的输出格式（通常是立体声）
        let outputFormat = mixer.outputFormat(forBus: 0)
        audioEngine.connect(playerNode, to: mixer, format: outputFormat)
        
        audioEngine.prepare()
        print("✅ 音频引擎初始化完成")
        print("   输出格式：\(outputFormat.channelCount) 声道，采样率 \(outputFormat.sampleRate) Hz")
    }
    
    private func playBeat() {
        currentBeat = (currentBeat % beatsPerMeasure) + 1
        
        let buffer = (currentBeat == 1) ? tockBuffer : tickBuffer
        guard let buffer = buffer else { return }
        
        // ✨ 直接调度缓冲区（AVAudioPlayerNode 内部是线程安全的）
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }
    
    private func restart() {
        stop()
        start()
    }
    
    /// ✨ 更新定时器间隔（不重启）
    private func updateTimerInterval() {
        guard isPlaying else { return }
        
        print("🔄 更新定时器间隔 - 新 BPM: \(bpm)")
        // 重新创建定时器，使用新的间隔
        timer?.invalidate()
        let interval = 60.0 / Double(bpm)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.playBeat()
            }
        }
        print("🔄 节拍器速度已更新 - 新 BPM: \(bpm)")
    }
    
    private func setupSoundForType(_ type: MetronomeSoundType) {
        switch type {
        case .tick:
            tickBuffer = createBeepBuffer(frequency: 1000, duration: 0.05)
            tockBuffer = createBeepBuffer(frequency: 1200, duration: 0.05)
        case .woodblock:
            tickBuffer = createBeepBuffer(frequency: 800, duration: 0.08)
            tockBuffer = createBeepBuffer(frequency: 1000, duration: 0.1)
        case .drum:
            tickBuffer = createBeepBuffer(frequency: 400, duration: 0.1)
            tockBuffer = createBeepBuffer(frequency: 300, duration: 0.12)
        case .mechanical:
            // 重拍（tick）更亮更高，其余拍（tock）略低，模拟机械节拍器 tick-tock
            tickBuffer = createMechanicalBuffer(frequency: 2600, duration: 0.05)
            tockBuffer = createMechanicalBuffer(frequency: 1900, duration: 0.06)
        }
    }
    
    private func createBeepBuffer(frequency: Float, duration: TimeInterval) -> AVAudioPCMBuffer? {
        let outputFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate
        let channelCount = outputFormat.channelCount  // ✨ 使用输出格式的声道数
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        
        // ✨ 使用与引擎匹配的声道数创建格式
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("❌ 创建音频缓冲区失败")
            return nil
        }
        
        buffer.frameLength = frameCount
        
        guard let channelData = buffer.floatChannelData else {
            print("❌ 获取声道数据失败")
            return nil
        }
        
        // ✨ 音量增益：相对原 0.8 约翻倍。浮点 PCM 上限是 ±1.0，超过会硬削波失真，
        // 因此用 tanh 软削波把峰值压回 ±1 内，更响但不刺耳。
        let gain: Float = 2.5
        
        // ✨ 为所有声道生成相同的正弦波
        for channel in 0..<Int(channelCount) {
            let data = channelData[channel]
            
            // 生成正弦波 + 软削波 + 淡入淡出
            for frame in 0..<Int(frameCount) {
                let time = Float(frame) / Float(sampleRate)
                // 2 倍增益后用 tanh 软削波，峰值被压回 ±1 内，避免数字硬削波失真
                let shaped = tanh(gain * sin(2.0 * Float.pi * frequency * time))
                
                // 添加包络，避免爆音
                let fadeLength = min(Int(sampleRate * 0.005), Int(frameCount) / 4)
                var envelope: Float = 1.0
                
                if frame < fadeLength {
                    envelope = Float(frame) / Float(fadeLength)
                } else if frame > Int(frameCount) - fadeLength {
                    envelope = Float(Int(frameCount) - frame) / Float(fadeLength)
                }
                
                data[frame] = shaped * envelope
            }
        }
        
        print("✅ 创建音频缓冲区：\(channelCount) 声道，\(frameCount) 帧，频率 \(frequency) Hz")
        return buffer
    }
    
    /// 机械节拍器「咔哒」声：高频阻尼正弦（机械「丁」声主体）+ 开头极短噪声瞬态（撞击感），
    /// 经 tanh 软削波压在 ±1 内，明亮、宽带、穿透力强，比纯正弦「滴答」更易听清。
    private func createMechanicalBuffer(frequency: Float, duration: TimeInterval) -> AVAudioPCMBuffer? {
        let outputFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate
        let channelCount = outputFormat.channelCount
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("❌ 创建音频缓冲区失败")
            return nil
        }
        buffer.frameLength = frameCount
        
        guard let channelData = buffer.floatChannelData else {
            print("❌ 获取声道数据失败")
            return nil
        }
        
        let tau: Float = 0.020          // 衰减时间常数 ~20ms，机械咔哒是短促瞬态但留一点余韵
        let attackDur: Float = 0.005    // 仅开头 5ms 含噪声瞬态（机械撞击感）
        let gain: Float = 3.2          // 软削波前增益，确保够响（峰值压在 ±1 内）
        
        for channel in 0..<Int(channelCount) {
            let data = channelData[channel]
            for frame in 0..<Int(frameCount) {
                let time = Float(frame) / Float(sampleRate)
                let env = exp(-time / tau)  // 指数衰减包络
                let sine = sin(2.0 * Float.pi * frequency * time)        // 高频阻尼正弦
                let noiseEnv: Float = time < attackDur ? (1.0 - time / attackDur) : 0.0
                let noise = Float.random(in: -1...1) * noiseEnv * 0.7   // 机械撞击瞬态
                let raw = (sine * 0.9 + noise) * env
                let shaped = tanh(raw * gain)  // 软削波，峰值压回 ±1 内
                
                // 缓冲首尾淡入淡出，避免边界爆音
                let fadeLength = min(Int(sampleRate * 0.002), Int(frameCount) / 4)
                var edge: Float = 1.0
                if frame < fadeLength {
                    edge = Float(frame) / Float(fadeLength)
                } else if frame > Int(frameCount) - fadeLength {
                    edge = Float(Int(frameCount) - frame) / Float(fadeLength)
                }
                data[frame] = shaped * edge
            }
        }
        print("✅ 创建机械咔哒缓冲区：\(channelCount) 声道，\(frameCount) 帧，频率 \(frequency) Hz")
        return buffer
    }
    
    private func loadSettings() {
        print("📖 开始加载设置")
        // ✨ 使用 v2 key：丢弃旧版存过的 120 BPM / 电子滴答，让新默认（108 / 机械）生效
        if let savedBPM = UserDefaults.standard.object(forKey: "metronome_bpm_v2") as? Int {
            print("📖 加载保存的 BPM: \(savedBPM)")
            bpm = savedBPM
        }
        
        if let savedSound = UserDefaults.standard.string(forKey: "metronome_sound_v2"),
           let soundType = MetronomeSoundType(rawValue: savedSound) {
            print("📖 加载保存的音色: \(savedSound)")
            self.soundType = soundType
        }
        print("📖 设置加载完成")
    }
    
    func saveSettings() {
        print("💾 保存设置: BPM=\(bpm), 音色=\(soundType.rawValue)")
        UserDefaults.standard.set(bpm, forKey: "metronome_bpm_v2")
        UserDefaults.standard.set(soundType.rawValue, forKey: "metronome_sound_v2")
        print("💾 设置已保存")
    }
}

// MARK: - 便捷方法

extension MetronomeManager {
    func setCommonBPM(_ bpm: Int) {
        self.bpm = bpm
    }
}
