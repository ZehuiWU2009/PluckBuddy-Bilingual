//
//  FlowerViewModel.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/7/16.
//

import Foundation
import AVFoundation
import Combine
import SwiftUI

@MainActor
class FlowerViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRunning = false
    @Published var rollCount: Int = 0 // 轮指次数
    @Published var sequenceCount: Int = 0 // 完成的轮指序列数
    @Published var currentSpeed: Double = 0 // 当前速度（次/秒）
    @Published var averageSpeed: Double = 0 // 平均速度
    @Published var uniformity: Double = 0 // 均匀度 0-1
    @Published var score: Int = 0 // 得分
    @Published var statusMessage = "准备开始"
    @Published var sessionDuration: TimeInterval = 0 // 当前练习时长（秒）
    @Published var targetDuration: TimeInterval = 300 // 目标时长（默认5分钟）
    @Published var targetBPM: Double = 120 // ✨ 新增：目标速度（BPM）

    // 花朵状态
    @Published var flowerGrowth: Double = 0.0 // 花朵生长进度 0-1
    @Published var petalCount: Int = 0 // 当前花瓣数
    @Published var flowerBrightness: Double = 0.5 // 花朵亮度（基于速度）
    @Published var flowerSymmetry: Double = 1.0 // 花朵对称性（基于均匀度）
    @Published var isRolling: Bool = false // 是否正在轮指（控制动画）
    @Published var lastSequenceQuality: RollSequence.Quality? // 最近完成序列的质量
    @Published var pulseCounter: Int = 0 // ✨ 新增：花瓣脉冲计数器
    
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
    private var rollDetector: RollDetector?
    private var startTime: Date?
    private var durationTimer: Timer? // 用于更新实时时长
    private var idleWorkItem: DispatchWorkItem? // 用于检测空闲（无轮指）
    private var completedSequences: [RollSequence] = []
    
    // MARK: - Constants
    private let maxPetals = 8 // 最多 8 片花瓣
    private let notesPerPetal = 5 // 每 5 个音符长出一片花瓣
    private let scorePerNote: Int = 5 // 每个音符基础分
    private let scorePerSequence: Int = 50 // 每个完整序列奖励分
    private let idleTimeout: TimeInterval = 2.0 // 空闲超时：2秒无轮指视为停止
    
    // MARK: - Lifecycle
    func startPractice() {
        Task { [weak self] in
            guard let self = self else { return }
            print("🌸 开始轮指练习...")
            
            // 请求麦克风权限
            audioManager = AudioManager.shared
            guard let manager = audioManager else {
                print("❌ AudioManager 初始化失败")
                return
            }
            
            print("🎤 请求麦克风权限...")
            let hasPermission = await manager.requestMicrophonePermission()
            guard hasPermission else {
                print("❌ 麦克风权限被拒绝")
                statusMessage = "需要麦克风权限"
                return
            }
            print("✅ 麦克风权限已授予")
            
            // 初始化轮指检测器
            rollDetector = RollDetector(sampleRate: 48000.0)
            
            rollDetector?.onRollDetected = { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleRollEvent(event)
                }
            }
            
            rollDetector?.onRollSequenceComplete = { [weak self] sequence in
                Task { @MainActor [weak self] in
                    self?.handleSequenceComplete(sequence)
                }
            }
            print("✅ 轮指检测器已初始化")
            
            // 重置状态
            resetSession()
            
            // 启动音频监听
            do {
                print("🎧 启动音频监听...")
                try manager.startListening { [weak self] buffer, _ in
                    guard let self = self,
                          let detector = self.rollDetector else { return }
                    
                    // ✅ DSP 启发式门控已回退（实测效果不稳），直接交给轮指检测器处理
                    _ = detector.detectRoll(from: buffer)
                }
                
                print("✅ 音频监听已启动")
                isRunning = true
                startTime = Date()
                statusMessage = "开始轮指吧！"
                
                // ✨ 如果节拍器已启用，自动启动
                if metronome.isEnabled {
                    // 同步节拍器速度到目标 BPM
                    metronome.bpm = Int(targetBPM)
                    metronome.start()
                    print("🎵 节拍器已自动启动")
                }
                
                // 启动时长计时器
                startDurationTimer()
                
            } catch {
                print("❌ 音频启动失败: \(error.localizedDescription)")
                statusMessage = "音频启动失败"
            }
        }
    }
    
    func stopPractice() {
        // 结束当前序列
        rollDetector?.finishSequence()
        
        audioManager?.stopListening()
        isRunning = false
        isRolling = false // 重置轮指状态
        
        // ✨ 停止节拍器
        metronome.stop()
        
        // 停止时长计时器
        stopDurationTimer()
        
        // 取消空闲任务
        idleWorkItem?.cancel()
        idleWorkItem = nil
        
        if let start = startTime {
            sessionDuration = Date().timeIntervalSince(start)
            
            // 保存练习记录
            if rollCount > 0 {
                print("💾 保存练习记录...")
                print("   - 时长: \(String(format: "%.1f", sessionDuration))秒")
                print("   - 轮指次数: \(rollCount)")
                print("   - 平均速度: \(String(format: "%.1f", averageSpeed))次/秒")
                print("   - 得分: \(score)")
                
                PracticeDataManager.shared.saveFlowerSession(
                    duration: sessionDuration,
                    rollCount: rollCount,
                    rollSpeed: averageSpeed,
                    score: score
                )
            }
        }
        
        updateStatusMessage()
    }
    
    // MARK: - Event Handling
    private func handleRollEvent(_ event: RollEvent) {
        guard isRunning else { return }
        
        // 🔍 添加调试日志
        print("🎵 检测到轮指音符！")
        print("   - 序列长度: \(event.sequenceLength)")
        print("   - 当前速度: \(String(format: "%.1f", event.currentSpeed))次/秒")
        print("   - 振幅: \(String(format: "%.2f", event.note.amplitude))")
        print("   - 有效阈值: \(String(format: "%.3f", rollDetector?.lastEffectiveThreshold ?? 0))")
        print("   - 间隔: \(String(format: "%.3f", event.note.interval))秒")
        print("   - 有效序列: \(event.isValidSequence ? "是" : "否")")
        
        // ✨ 修复：设置为正在轮指，并增加脉冲计数器
        let wasRolling = isRolling
        isRolling = true
        
        if !wasRolling {
            print("   ✓ 开始新的轮指动作：isRolling = true")
        }
        
        // ✨ 每次检测到音符都增加脉冲计数器
        pulseCounter += 1
        print("   ✓ 触发花瓣脉冲 #\(pulseCounter)")
        
        // 重置空闲计时器
        resetIdleTimer()
        
        // 更新统计
        rollCount += 1
        let oldSpeed = currentSpeed
        currentSpeed = event.currentSpeed
        print("   ✓ 更新速度: \(String(format: "%.1f", oldSpeed)) → \(String(format: "%.1f", currentSpeed))次/秒")
        
        // 基础得分
        score += scorePerNote
        
        // 更新花朵生长
        updateFlowerGrowth()
        
        // 更新提示信息
        updateStatusMessage()
    }
    
    private func handleSequenceComplete(_ sequence: RollSequence) {
        guard isRunning else { return }
        
        print("🎊 轮指序列完成！")
        print("   - 音符数: \(sequence.noteCount)")
        print("   - 时长: \(String(format: "%.2f", sequence.duration))秒")
        print("   - 平均速度: \(String(format: "%.1f", sequence.averageSpeed))次/秒")
        print("   - 均匀度: \(Int(sequence.uniformity * 100))%")
        print("   - 质量评级: \(sequence.quality.emoji) \(sequence.quality.description)")
        
        // 记录序列
        completedSequences.append(sequence)
        sequenceCount += 1
        lastSequenceQuality = sequence.quality
        
        // 更新平均速度
        averageSpeed = completedSequences.map { $0.averageSpeed }.reduce(0, +) / Double(completedSequences.count)
        
        // 更新均匀度
        uniformity = completedSequences.map { $0.uniformity }.reduce(0, +) / Double(completedSequences.count)
        
        print("   - 累计平均速度: \(String(format: "%.1f", averageSpeed))次/秒")
        print("   - 累计均匀度: \(Int(uniformity * 100))%")
        
        // 序列奖励分
        var bonusScore = scorePerSequence
        
        // 质量奖励
        switch sequence.quality {
        case .excellent:
            bonusScore = Int(Double(bonusScore) * 2.0) // 2x
            print("   🌟 优秀！奖励: \(bonusScore)分")
        case .good:
            bonusScore = Int(Double(bonusScore) * 1.5) // 1.5x
            print("   👍 良好！奖励: \(bonusScore)分")
        case .fair:
            bonusScore = Int(Double(bonusScore) * 1.0) // 1x
            print("   👌 一般！奖励: \(bonusScore)分")
        case .needsImprovement:
            bonusScore = Int(Double(bonusScore) * 0.5) // 0.5x
            print("   💪 继续努力！奖励: \(bonusScore)分")
        }
        
        score += bonusScore
        
        // 更新花朵属性
        updateFlowerAttributes()
        
        // 特殊反馈
        if sequence.quality == .excellent {
            // 优秀的轮指让花朵完全绽放
            print("   ✨ 触发花朵绽放动画！")
            triggerFlowerBloom()
        }
    }
    
    // MARK: - Flower Animation
    private func updateFlowerGrowth() {
        // 每个音符增加生长进度
        let growthPerNote = 1.0 / Double(maxPetals * notesPerPetal)
        flowerGrowth = min(1.0, flowerGrowth + growthPerNote)
        
        // 计算花瓣数
        petalCount = min(maxPetals, rollCount / notesPerPetal)
    }
    
    private func updateFlowerAttributes() {
        // 亮度基于速度（速度越快越亮）
        flowerBrightness = min(1.0, max(0.3, currentSpeed / 15.0))
        
        // 对称性基于均匀度
        flowerSymmetry = uniformity
    }
    
    private func triggerFlowerBloom() {
        // 触发绽放动画
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            flowerGrowth = 1.0
            flowerBrightness = 1.0
        }
        
        // 短暂延迟后重置，准备下一朵花
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 秒
            await MainActor.run {
                if isRunning {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        flowerGrowth = 0.0
                        petalCount = 0
                    }
                }
            }
        }
    }
    
    // MARK: - UI Updates
    private func updateStatusMessage() {
        if !isRunning {
            statusMessage = generateSummary()
            return
        }
        
        if rollCount == 0 {
            statusMessage = "开始轮指吧！"
            return
        }
        
        // 根据最近序列质量给出反馈
        if let quality = lastSequenceQuality {
            switch quality {
            case .excellent:
                statusMessage = "🌟 完美轮指！继续保持！"
            case .good:
                statusMessage = "👍 轮指良好，再快一点更好！"
            case .fair:
                statusMessage = "👌 继续练习，注意均匀度"
            case .needsImprovement:
                statusMessage = "💪 放松手指，保持匀速"
            }
            return
        }
        
        // 根据当前速度给出反馈
        if currentSpeed >= 12 {
            statusMessage = "🚀 速度很快！"
        } else if currentSpeed >= 10 {
            statusMessage = "👍 速度不错！"
        } else if currentSpeed >= 8 {
            statusMessage = "👌 继续保持！"
        } else if currentSpeed >= 6 {
            statusMessage = "💪 可以再快一点"
        } else if currentSpeed > 0 {
            statusMessage = "🎵 试着更快速地轮指"
        } else {
            statusMessage = "等待轮指..."
        }
        
        // 均匀度提示
        if uniformity > 0 && uniformity < 0.5 {
            statusMessage += "\n试着保持每个音符间隔一致"
        }
    }
    
    private func generateSummary() -> String {
        guard rollCount > 0 else {
            return "准备开始"
        }
        
        let minutes = Int(sessionDuration / 60)
        let seconds = Int(sessionDuration.truncatingRemainder(dividingBy: 60))
        
        var summary = "练习结束！\n"
        summary += "时长: \(minutes):\(String(format: "%02d", seconds))\n"
        summary += "轮指: \(rollCount) 次\n"
        summary += "序列: \(sequenceCount) 个\n"
        summary += "平均速度: \(String(format: "%.1f", averageSpeed)) 次/秒\n"
        summary += "得分: \(score)"
        
        return summary
    }
    
    // MARK: - Reset
    private func resetSession() {
        rollCount = 0
        sequenceCount = 0
        currentSpeed = 0
        averageSpeed = 0
        uniformity = 0
        score = 0
        flowerGrowth = 0
        petalCount = 0
        flowerBrightness = 0.5
        flowerSymmetry = 1.0
        sessionDuration = 0
        isRolling = false
        lastSequenceQuality = nil
        pulseCounter = 0 // ✨ 重置脉冲计数器
        completedSequences.removeAll()
        rollDetector?.reset()
    }
    
    // MARK: - Idle Timer Management
    
    /// 重置空闲计时器（每次轮指时调用）
    private func resetIdleTimer() {
        // 取消现有任务
        idleWorkItem?.cancel()
        
        // 创建新任务
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            print("⏸️ 空闲超时（\(self.idleTimeout)秒无轮指），停止动画")
            print("   - 当前状态：isRolling=\(self.isRolling), 速度=\(self.currentSpeed)")
            
            self.isRolling = false
            self.currentSpeed = 0
            
            // ✅ 重置轮指检测器，清除历史记录
            print("   - 重置 RollDetector 历史记录")
            self.rollDetector?.reset()
            
            print("   - 新状态：isRolling=\(self.isRolling), 速度=\(self.currentSpeed)")
        }
        
        idleWorkItem = workItem
        
        // 在主线程延迟执行
        DispatchQueue.main.asyncAfter(deadline: .now() + idleTimeout, execute: workItem)
    }
    
    // MARK: - Timer Management
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.startTime else { return }
                self.sessionDuration = Date().timeIntervalSince(start)
                
                // 检查是否到达目标时长
                if self.sessionDuration >= self.targetDuration {
                    print("⏰ 训练时间到！自动停止")
                    self.stopPractice()
                }
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
    
    // MARK: - Settings
    func setTargetDuration(_ duration: TimeInterval) {
        targetDuration = max(60, min(1800, duration)) // 限制在 1-30 分钟
    }
}
