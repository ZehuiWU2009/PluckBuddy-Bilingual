//
//  RunningViewModel.swift
//  PluckBuddy
//
//  Created by Zehui Wu on 2026/7/16.
//

import Foundation
import AVFoundation
import Combine
import SwiftUI

@MainActor
class RunningViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRunning = false
    @Published var distance: Double = 0.0 // 跑步距离（米）
    @Published var pluckCount: Int = 0 // 弹拨次数
    @Published var currentBPM: Double = 0 // 当前速度
    @Published var stability: Double = 0 // 稳定性 0-1（最近窗口的瞬时值）
    @Published var averageStability: Double = 0 // 本次练习稳定性的平均值（停止后展示）
    @Published var score: Int = 0 // 得分
    @Published var statusMessage = L("准备开始")
    @Published var targetBPM: Double = 120 // 目标速度
    @Published var sessionDuration: TimeInterval = 0 // 当前练习时长（秒）
    @Published var targetDuration: TimeInterval = 300 // 目标时长（默认5分钟）

    // 角色动画状态
    @Published var characterPosition: Double = 0.0 // 角色位置（0-1）- 已废弃，改用跑道移动
    @Published var isCharacterRunning = false
    @Published var isPlucking: Bool = false // 是否正在弹奏（控制动画）
    
    // 跑道动画状态
    @Published var trackOffset: Double = 0.0 // 跑道偏移量（用于滚动效果）
    @Published var runningSpeed: Double = 0.0 // 跑步速度（像素/秒）
    
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
    private var rhythmDetector: RhythmDetector?
    private var startTime: Date?
    private var durationTimer: Timer? // 用于更新实时时长
    private var idleWorkItem: DispatchWorkItem? // 用于检测空闲（无弹奏）
    private var cancellables = Set<AnyCancellable>() // ✨ Combine 订阅
    private var stabilitySum: Double = 0 // 本次练习稳定性采样值之和
    private var stabilitySampleCount: Int = 0 // 有效采样个数（用于算平均）
    
    // MARK: - Constants
    private let distancePerPluck: Double = 1.0 // 每次弹拨前进 1 米
    private let scorePerPluck: Int = 10 // 每次弹拨得分
    private let bonusThreshold: Double = 0.8 // 稳定性奖励阈值
    private let idleTimeout: TimeInterval = 2.0 // 空闲超时：2秒无弹奏视为停止
    
    // MARK: - Initialization
    init() {
        print("🏃 RunningViewModel init() 开始")
        // ✨ 设置初始节拍器速度（同步，因为只是赋值）
        metronome.bpm = Int(targetBPM)
        print("🏃 RunningViewModel - 节拍器速度已设置")
        
        // ✨ 延迟设置订阅，避免阻塞初始化
        DispatchQueue.main.async {
            print("🏃 RunningViewModel - 开始设置 BPM 同步")
            self.setupBPMSync()
        }
        print("🏃 RunningViewModel init() 完成")
    }
    
    // ✨ 设置 BPM 同步（延迟调用）
    private func setupBPMSync() {
        // 监听 targetBPM 变化，自动同步节拍器
        $targetBPM
            .dropFirst() // 跳过初始值，避免重复设置
            .sink { [weak self] newBPM in
                self?.metronome.bpm = Int(newBPM)
                print("🎯 目标速度已更改为 \(Int(newBPM)) BPM，节拍器已同步")
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Lifecycle
    func startPractice() {
        Task { [weak self] in
            guard let self = self else { return }
            print("🎵 开始练习...")
            
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
                statusMessage = L("需要麦克风权限")
                return
            }
            print("✅ 麦克风权限已授予")
            
            // 初始化节奏检测器
            rhythmDetector = RhythmDetector(sampleRate: 48000.0)
            rhythmDetector?.onPluckDetected = { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handlePluckEvent(event)
                }
            }
            print("✅ 节奏检测器已初始化")
            
            // 重置状态
            resetSession()
            
            // 启动音频监听
            do {
                print("🎧 启动音频监听...")
                try manager.startListening { [weak self] buffer, _ in
                    guard let self = self,
                          let detector = self.rhythmDetector else { return }
                    
                    // ✅ DSP 启发式门控已回退（实测效果不稳），直接交给节奏检测器处理
                    _ = detector.detectPluck(from: buffer)
                }
                
                print("✅ 音频监听已启动")
                isRunning = true
                startTime = Date()
                statusMessage = L("开始弹奏吧！")
                
                // ✨ 如果节拍器已启用，自动启动
                if metronome.isEnabled {
                    metronome.start()
                    print("🎵 节拍器已自动启动")
                }
                
                // 启动时长计时器
                startDurationTimer()
                
            } catch {
                print("❌ 音频启动失败: \(error.localizedDescription)")
                statusMessage = L("音频启动失败")
            }
        }
    }
    
    func stopPractice() {
        audioManager?.stopListening()
        isRunning = false
        isCharacterRunning = false
        isPlucking = false // 重置弹奏状态
        
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
            if pluckCount > 0 {
                PracticeDataManager.shared.saveRunningSession(
                    duration: sessionDuration,
                    pluckCount: pluckCount,
                    averageBPM: currentBPM,
                    stability: averageStability, // 存整场平均，而非停止瞬间的最后一次瞬时值
                    distance: distance,
                    score: score
                )
            }
        }
        
        updateStatusMessage()
    }
    
    // MARK: - Event Handling
    private func handlePluckEvent(_ event: PluckEvent) {
        guard isRunning else { return }
        // 🔍 添加调试日志
        print("🎸 检测到弹奏！")
        print("   - BPM: \(String(format: "%.1f", event.bpm))")
        print("   - 强度: \(String(format: "%.2f", event.amplitude))")
        print("   - RMS: \(String(format: "%.2f", event.rms))")
        print("   - 间隔: \(String(format: "%.3f", event.interval))s")
        print("   - 弹奏次数: \(pluckCount + 1)")
        print("   - 当前状态：isPlucking=\(isPlucking), currentBPM=\(String(format: "%.1f", currentBPM))")
        
        // 设置为正在弹奏
        isPlucking = true
        print("   ✓ 设置 isPlucking = true")
        
        // 重置空闲计时器
        resetIdleTimer()
        
        // 更新统计
        pluckCount += 1
        distance += distancePerPluck
        
        // 更新速度和稳定性
        let oldBPM = currentBPM
        currentBPM = event.bpm
        print("   ✓ 更新 currentBPM: \(String(format: "%.1f", oldBPM)) → \(String(format: "%.1f", currentBPM))")
        
        stability = rhythmDetector?.calculateStability() ?? 0

        // 累计本次练习的稳定性平均值：只有检测器真正算出值（>0）的采样才计入，
        // 否则开头几个音的 0 会把整场平均值拉低，读起来像「练得很差」。
        if stability > 0 {
            stabilitySum += stability
            stabilitySampleCount += 1
            averageStability = stabilitySum / Double(stabilitySampleCount)
        }

        print("   - 当前稳定性: \(Int(stability * 100))%")
        print("   - 平均稳定性: \(Int(averageStability * 100))%（样本 \(stabilitySampleCount) 个）")
        
        // 计算得分
        var points = scorePerPluck
        
        // 稳定性奖励
        if stability > bonusThreshold {
            points += Int(Double(scorePerPluck) * 0.5) // +50% 奖励
        }
        
        // 速度匹配奖励
        let bpmDiff = abs(currentBPM - targetBPM)
        if bpmDiff < 5 {
            points += Int(Double(scorePerPluck) * 0.3) // +30% 奖励
        }
        
        score += points
        
        // 更新角色动画
        triggerCharacterStep()
        
        // 更新提示信息
        updateStatusMessage()
    }
    
    // MARK: - Idle Timer Management
    
    /// 重置空闲计时器（每次弹奏时调用）
    private func resetIdleTimer() {
        // 取消现有任务
        idleWorkItem?.cancel()
        
        // 创建新任务
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            print("⏸️ 空闲超时（\(self.idleTimeout)秒无弹奏），停止动画")
            print("   - 当前状态：isPlucking=\(self.isPlucking), BPM=\(self.currentBPM)")
            
            self.isPlucking = false
            self.currentBPM = 0
            
            // ✅ 重置节奏检测器，清除历史记录
            print("   - 重置 RhythmDetector 历史记录")
            self.rhythmDetector?.reset()
            
            print("   - 新状态：isPlucking=\(self.isPlucking), BPM=\(self.currentBPM)")
        }
        
        idleWorkItem = workItem
        
        // 在主线程延迟执行
        DispatchQueue.main.asyncAfter(deadline: .now() + idleTimeout, execute: workItem)
    }
    
    // MARK: - Animation
    private func triggerCharacterStep() {
        isCharacterRunning = true
        
        // 计算跑步速度（基于 BPM）
        // BPM 60 -> 50 像素/秒
        // BPM 180 -> 300 像素/秒
        let speedMultiplier = currentBPM / 60.0
        runningSpeed = 50.0 * speedMultiplier
        
        // 短暂延迟后停止跑步动画（手脚摆动会持续）
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 秒
            await MainActor.run {
                isCharacterRunning = false
            }
        }
    }
    
    // MARK: - UI Updates
    private func updateStatusMessage() {
        if !isRunning {
            statusMessage = generateSummary()
            return
        }
        
        if pluckCount == 0 {
            statusMessage = L("开始弹奏吧！")
            return
        }
        
        // 根据稳定性给出反馈
        if stability > 0.9 {
            statusMessage = L("🎉 节奏非常稳定！")
        } else if stability > 0.7 {
            statusMessage = L("👍 节奏不错，保持！")
        } else if stability > 0.5 {
            statusMessage = L("💪 继续练习，更稳定一些")
        } else {
            statusMessage = L("🎵 试着保持匀速弹奏")
        }
        
        // 速度提示
        let bpmDiff = currentBPM - targetBPM
        if abs(bpmDiff) > 20 {
            if bpmDiff > 0 {
                statusMessage += L(" (稍慢一点)")
            } else {
                statusMessage += L(" (可以快一点)")
            }
        }
    }
    
    private func generateSummary() -> String {
        guard pluckCount > 0 else {
            return L("准备开始")
        }
        
        let minutes = Int(sessionDuration / 60)
        let seconds = Int(sessionDuration.truncatingRemainder(dividingBy: 60))
        
        var summary = L("练习结束！\n")
        summary += String(format: L("时长: %d:%02d\n"), minutes, seconds)
        summary += String(format: L("弹奏: %d 次\n"), pluckCount)
        summary += String(format: L("距离: %d 米\n"), Int(distance))
        summary += String(format: L("稳定性: %d%%\n"), Int(averageStability * 100))
        summary += String(format: L("得分: %d"), score)
        
        return summary
    }
    
    // MARK: - Reset
    private func resetSession() {
        distance = 0
        pluckCount = 0
        currentBPM = 0
        stability = 0
        averageStability = 0
        stabilitySum = 0
        stabilitySampleCount = 0
        score = 0
        characterPosition = 0
        trackOffset = 0
        runningSpeed = 0
        sessionDuration = 0
        rhythmDetector?.reset()
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
    func setTargetBPM(_ bpm: Double) {
        targetBPM = max(60, min(Double(MetronomeManager.maximumBPM), bpm)) // 上限与节拍器一致
    }
}
