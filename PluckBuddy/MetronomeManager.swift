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
    
    var id: String { rawValue }

    /// 本地化显示名（rawValue 仍作持久化 key，不能改）
    var displayName: String { L(rawValue) }
    
    var icon: String {
        switch self {
        case .tick: return "metronome"
        case .woodblock: return "circle.fill"
        case .drum: return "drums.fill"
        }
    }
}

/// 节拍器管理器（优化版）
@MainActor
class MetronomeManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var bpm: Int = 120 {
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
    @Published var soundType: MetronomeSoundType = .tick {
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
        
        let amplitude: Float = 0.8 // ✨ 提高音量（从 0.25 增加到 0.8）
        
        // ✨ 为所有声道生成相同的正弦波
        for channel in 0..<Int(channelCount) {
            let data = channelData[channel]
            
            // 生成正弦波 + 淡入淡出
            for frame in 0..<Int(frameCount) {
                let time = Float(frame) / Float(sampleRate)
                let value = amplitude * sin(2.0 * Float.pi * frequency * time)
                
                // 添加包络，避免爆音
                let fadeLength = min(Int(sampleRate * 0.005), Int(frameCount) / 4)
                var envelope: Float = 1.0
                
                if frame < fadeLength {
                    envelope = Float(frame) / Float(fadeLength)
                } else if frame > Int(frameCount) - fadeLength {
                    envelope = Float(Int(frameCount) - frame) / Float(fadeLength)
                }
                
                data[frame] = value * envelope
            }
        }
        
        print("✅ 创建音频缓冲区：\(channelCount) 声道，\(frameCount) 帧，频率 \(frequency) Hz")
        return buffer
    }
    
    private func loadSettings() {
        print("📖 开始加载设置")
        if let savedBPM = UserDefaults.standard.object(forKey: "metronome_bpm") as? Int {
            print("📖 加载保存的 BPM: \(savedBPM)")
            bpm = savedBPM
        }
        
        if let savedSound = UserDefaults.standard.string(forKey: "metronome_sound"),
           let soundType = MetronomeSoundType(rawValue: savedSound) {
            print("📖 加载保存的音色: \(savedSound)")
            self.soundType = soundType
        }
        print("📖 设置加载完成")
    }
    
    func saveSettings() {
        print("💾 保存设置: BPM=\(bpm), 音色=\(soundType.rawValue)")
        UserDefaults.standard.set(bpm, forKey: "metronome_bpm")
        UserDefaults.standard.set(soundType.rawValue, forKey: "metronome_sound")
        print("💾 设置已保存")
    }
}

// MARK: - 便捷方法

extension MetronomeManager {
    func setCommonBPM(_ bpm: Int) {
        self.bpm = bpm
    }
}
