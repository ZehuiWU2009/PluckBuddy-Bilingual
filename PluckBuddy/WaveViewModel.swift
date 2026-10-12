//
//  WaveViewModel.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/7/16.
//

import Foundation
import AVFoundation
import Combine
import SwiftUI

@MainActor
class WaveViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRunning = false
    @Published var sweepCount: Int = 0 // 扫弦次数
    @Published var upCount: Int = 0 // 向上扫次数
    @Published var downCount: Int = 0 // 向下扫次数
    @Published var averageStrength: Double = 0 // 平均力度
    @Published var directionBalance: Double = 0.5 // 方向平衡度
    @Published var score: Int = 0 // 得分
    @Published var statusMessage = L("准备开始")
    @Published var sessionDuration: TimeInterval = 0 // 当前练习时长（秒）
    @Published var targetDuration: TimeInterval = 300 // 目标时长（默认5分钟）
    @Published var targetBPM: Double = 60 // ✨ 新增：目标速度（BPM，扫弦通常较慢）

    // 水波状态
    @Published var waves: [WaveRipple] = [] // 当前的水波
    @Published var waterColor: Color = .blue // 水面颜色
    @Published var isSweeping: Bool = false // ✨ 新增：是否正在扫弦（控制动画）
    
    // ✨ 新增：节拍器
    let metronome = MetronomeManager()
    
    // ✨ 计算属性：提供节拍器设置的绑定接口
    var metronomeIsEnabled: Bool {
        get { metronome.isEnabled }
        set { metronome.isEnabled = newValue }
    }
    
    var metronomeSoundType: MetronomeSoundType {
        get { metronome.soundType }
        set { metronome.soundType = newValue }
    }
    
    // MARK: - Private Properties
    private var audioManager: AudioManager?
    private var sweepDetector: SweepDetector?
    private var startTime: Date?
    private var durationTimer: Timer? // 用于更新实时时长
    private var waveIdCounter: Int = 0
    private var idleWorkItem: DispatchWorkItem? // ✨ 用于检测空闲（无扫弦）
    
    // MARK: - Constants
    private let idleTimeout: TimeInterval = 2.0 // ✨ 空闲超时：2秒无扫弦视为停止
    private let scorePerSweep: Int = 10 // 每次扫弦得分
    private let maxWaves = 5 // 屏幕上最多同时显示的水波数
    
    // MARK: - Lifecycle
    func startPractice() {
        Task { [weak self] in
            guard let self = self else { return }
            // 请求麦克风权限
            audioManager = AudioManager.shared
            guard let manager = audioManager else { return }
            
            let hasPermission = await manager.requestMicrophonePermission()
            guard hasPermission else {
                statusMessage = L("需要麦克风权限")
                return
            }
            
            // 初始化扫弦检测器
            sweepDetector = SweepDetector(sampleRate: 48000.0)
            
            sweepDetector?.onSweepDetected = { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleSweepEvent(event)
                }
            }
            
            // 重置状态
            resetSession()
            
            // ✨ 启动节拍器（如果启用）
            if metronome.isEnabled {
                metronome.bpm = Int(targetBPM)
                metronome.start()
            }
            
            // 启动音频监听
            do {
                try manager.startListening { [weak self] buffer, _ in
                    guard let self = self,
                          let detector = self.sweepDetector else { return }
                    
                    // ✅ DSP 启发式门控已回退（实测效果不稳），直接交给扫弦检测器处理
                    _ = detector.detectSweep(from: buffer)
                }
                
                isRunning = true
                startTime = Date()
                statusMessage = L("开始扫弦吧！")
                
                // ✨ 启动时长计时器
                startDurationTimer()
                
            } catch {
                statusMessage = L("音频启动失败")
                print("Audio error: \(error.localizedDescription)")
            }
        }
    }
    
    func stopPractice() {
        audioManager?.stopListening()
        isRunning = false
        isSweeping = false // ✨ 重置扫弦状态
        
        // ✨ 停止节拍器
        if metronome.isPlaying {
            metronome.stop()
        }
        
        // ✨ 停止时长计时器
        durationTimer?.invalidate()
        durationTimer = nil
        
        // ✨ 取消空闲任务
        idleWorkItem?.cancel()
        idleWorkItem = nil
        
        if let start = startTime {
            sessionDuration = Date().timeIntervalSince(start)
            
            // 保存练习记录
            if sweepCount > 0 {
                print("💾 保存扫弦练习记录...")
                print("   - 时长: \(String(format: "%.1f", sessionDuration))秒")
                print("   - 扫弦次数: \(sweepCount)")
                print("   - 平均力度: \(String(format: "%.1f", averageStrength * 100))%")
                print("   - 得分: \(score)")
                
                PracticeDataManager.shared.saveWaveSession(
                    duration: sessionDuration,
                    sweepCount: sweepCount,
                    averageStrength: averageStrength,
                    score: score
                )
            }
        }
        
        updateStatusMessage()
    }
    
    // MARK: - Event Handling
    private func handleSweepEvent(_ event: SweepEvent) {
        guard isRunning else { return }
        
        // 🔍 添加调试日志
        print("🌊 检测到扫弦！")
        print("   - 方向: \(event.direction.description) \(event.direction.arrow)")
        print("   - 力度: \(event.strength.description)")
        print("   - 振幅: \(String(format: "%.2f", event.amplitude))")
        print("   - RMS: \(String(format: "%.2f", event.rms))")
        
        // ✨ 设置为正在扫弦
        let wasSweeping = isSweeping
        isSweeping = true
        
        if !wasSweeping {
            print("   ✓ 开始新的扫弦动作：isSweeping = true")
        }
        
        // ✨ 重置空闲计时器
        resetIdleTimer()
        
        // 更新统计
        sweepCount += 1
        
        switch event.direction {
        case .up:
            upCount += 1
        case .down:
            downCount += 1
        }
        
        // 更新平均力度
        if let detector = sweepDetector {
            let stats = detector.getStatistics()
            averageStrength = stats.averageStrength
            directionBalance = stats.directionBalance
            
            print("   - 累计平均力度: \(String(format: "%.1f", averageStrength * 100))%")
            print("   - 方向平衡: \(String(format: "%.1f", directionBalance * 100))%")
        }
        
        // 计算得分
        var points = scorePerSweep
        
        // 力度奖励
        switch event.strength {
        case .veryStrong:
            points += 10 // +100%
            print("   💪 很重！奖励: +10分")
        case .strong:
            points += 5 // +50%
            print("   👍 重！奖励: +5分")
        case .medium:
            points += 2 // +20%
            print("   👌 中等！奖励: +2分")
        case .weak:
            points += 0
            print("   💪 轻，继续加油！")
        }
        
        // 方向平衡奖励（两个方向都练习）
        if directionBalance > 0.4 {
            points += 5
            print("   ⚖️ 方向平衡！奖励: +5分")
        }
        
        score += points
        print("   ✓ 本次得分: \(points)，总分: \(score)")
        
        // 创建水波
        createWave(from: event)
        
        // 更新水面颜色（基于平均力度）
        updateWaterColor()
        
        // 更新提示信息
        updateStatusMessage()
    }
    
    // MARK: - Wave Animation
    private func createWave(from event: SweepEvent) {
        // 限制最大水波数
        if waves.count >= maxWaves {
            waves.removeFirst()
        }
        
        waveIdCounter += 1
        
        let wave = WaveRipple(
            id: waveIdCounter,
            center: CGPoint(x: 0.5, y: 0.5), // 中心位置
            maxRadius: CGFloat(event.normalizedStrength * 0.8 + 0.2), // 0.2 - 1.0
            color: event.direction == .up ? Color.blue : Color.cyan,
            strength: event.normalizedStrength,
            direction: event.direction
        )
        
        waves.append(wave)
        
        // 水波扩散后自动移除
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 秒
            await MainActor.run {
                if let index = waves.firstIndex(where: { $0.id == wave.id }) {
                    waves.remove(at: index)
                }
            }
        }
    }
    
    private func updateWaterColor() {
        // 根据平均力度调整水面颜色
        let hue = 0.55 // 蓝色基调
        let saturation = 0.5 + (averageStrength * 0.5)
        let brightness = 0.6 + (averageStrength * 0.4)
        
        withAnimation(.easeInOut(duration: 0.5)) {
            waterColor = Color(hue: hue, saturation: saturation, brightness: brightness)
        }
    }
    
    // MARK: - UI Updates
    private func updateStatusMessage() {
        if !isRunning {
            statusMessage = generateSummary()
            return
        }
        
        if sweepCount == 0 {
            statusMessage = L("开始扫弦吧！")
            return
        }
        
        // 根据力度给出反馈
        if averageStrength > 0.7 {
            statusMessage = L("💪 力度很好！")
        } else if averageStrength > 0.5 {
            statusMessage = L("👍 力度不错！")
        } else if averageStrength > 0.3 {
            statusMessage = L("👌 可以再用力一点")
        } else {
            statusMessage = L("🎵 试着加大力度")
        }
        
        // 方向平衡提示
        if sweepCount >= 5 {
            if directionBalance < 0.2 {
                statusMessage += L("\n尝试两个方向都练习")
            } else if directionBalance > 0.4 {
                statusMessage += L("\n方向平衡很好！")
            }
        }
    }
    
    private func generateSummary() -> String {
        guard sweepCount > 0 else {
            return L("准备开始")
        }
        
        let minutes = Int(sessionDuration / 60)
        let seconds = Int(sessionDuration.truncatingRemainder(dividingBy: 60))
        
        var summary = L("练习结束！\n")
        summary += String(format: L("时长: %d:%02d\n"), minutes, seconds)
        summary += String(format: L("扫弦: %d 次\n"), sweepCount)
        summary += String(format: L("向上: %d 次 | 向下: %d 次\n"), upCount, downCount)
        summary += String(format: L("平均力度: %.1f%%\n"), averageStrength * 100)
        summary += String(format: L("得分: %d"), score)
        
        return summary
    }
    
    // MARK: - Reset
    private func resetSession() {
        sweepCount = 0
        upCount = 0
        downCount = 0
        averageStrength = 0
        directionBalance = 0.5
        score = 0
        waves.removeAll()
        waterColor = .blue
        sessionDuration = 0
        waveIdCounter = 0
        isSweeping = false // ✨ 重置扫弦状态
        sweepDetector?.reset()
    }
    
    // MARK: - Idle Timer Management
    
    /// ✨ 重置空闲计时器（每次扫弦时调用）
    private func resetIdleTimer() {
        // 取消现有任务
        idleWorkItem?.cancel()
        
        // 创建新任务
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            print("⏸️ 空闲超时（\(self.idleTimeout)秒无扫弦），停止动画")
            print("   - 当前状态：isSweeping=\(self.isSweeping)")
            
            self.isSweeping = false
            
            // ✅ 重置扫弦检测器，清除历史记录
            print("   - 重置 SweepDetector 历史记录")
            self.sweepDetector?.reset()
            
            print("   - 新状态：isSweeping=\(self.isSweeping)")
        }
        
        idleWorkItem = workItem
        
        // 在主线程延迟执行
        DispatchQueue.main.asyncAfter(deadline: .now() + idleTimeout, execute: workItem)
    }
    
    // MARK: - Timer
    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.startTime else { return }
                self.sessionDuration = Date().timeIntervalSince(start)
                
                // ✨ 检查是否达到目标时长
                if self.targetDuration > 0 && self.sessionDuration >= self.targetDuration {
                    self.stopPractice()
                    self.statusMessage = L("🎉 完成目标时长！")
                }
            }
        }
    }
}

// MARK: - WaveRipple
/// 水波纹数据模型
class WaveRipple: Identifiable, ObservableObject {
    let id: Int
    let center: CGPoint // 归一化坐标 (0-1)
    let maxRadius: CGFloat // 最大半径（归一化）
    let color: Color
    let strength: Double
    let direction: SweepDirection
    let createdAt: Date // ✨ 新增：创建时间
    
    /// ✨ 当前扩散进度 (0-1)，基于时间计算
    var progress: Double {
        let elapsed = Date().timeIntervalSince(createdAt)
        let duration = 2.0 // 2秒完成扩散
        return min(1.0, elapsed / duration)
    }
    
    /// ✨ 透明度（随进度递减）
    var opacity: Double {
        return max(0, 1.0 - progress)
    }
    
    init(id: Int, center: CGPoint, maxRadius: CGFloat, color: Color, strength: Double, direction: SweepDirection) {
        self.id = id
        self.center = center
        self.maxRadius = maxRadius
        self.color = color
        self.strength = strength
        self.direction = direction
        self.createdAt = Date()
    }
}
