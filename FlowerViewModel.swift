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
    @Published var isStageResting: Bool = false // 是否正处于「长出一圈→停顿一下」的台阶停顿（供视图做呼吸动画）
    @Published var bloomFlashCounter: Int = 0 // 优秀序列触发的金色光晕计数（每 +1 闪一次）
    @Published var excellentStreak: Int = 0 // 连续「优秀」的序列数（中断即清零）
    @Published var flowerLayers: Int = 1 // 花层数：连续优秀累积成重瓣，1~3 层
    @Published var petalCloseCount: Int = 0 // 满花后已收拢的花瓣数（依次收拢用，0 表示未开始）
    @Published var isClosing: Bool = false // 是否正处于「花瓣依次收拢」阶段

    // MARK: - 速度达标（供视图把花色转金）
    /// 当前轮指速度的等效 BPM = 次/秒 × 60 ÷ 每拍音数。
    /// currentSpeed 是每秒的轮指音数，而 targetBPM 是节拍器速度，两者靠每拍音数换算。
    var currentSpeedBPM: Double {
        currentSpeed * 60.0 / notesPerBeat
    }

    /// 速度是否达到目标 BPM —— 达标即给出明确的视觉奖励（花色转金）
    var isSpeedTargetMet: Bool {
        currentSpeed > 0 && currentSpeedBPM >= targetBPM
    }

    // 花朵循环状态：每长满一朵即归零重长，形成「生长→绽放→归零」的持续节奏
    private var flowerNotes: Int = 0        // 当前这朵花累计的音符数（区别于全局 rollCount）
    private var flowerBlooming: Bool = false // 是否正处于「绽放-归零」过渡期
    private var stageRestTask: Task<Void, Never>? // 台阶停顿的延时任务（可被停止/重置取消）
    private var closingTask: Task<Void, Never>? // 满花后「花瓣依次收拢」的任务（可被停止/重置取消）
    
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
    /// 每长出一片花瓣所需的音符数，也是控制开花快慢的唯一旋钮。
    /// 长满一朵共需 maxPetals × notesPerPetal 个音符：原为 8×5=40（高速轮指约 3 秒即开满，
    /// 用户反馈太快），现调为 8×14=112，开花过程约为原来的 2.8 倍时长。想再慢就调大这个值。
    private let notesPerPetal = 14
    /// 节拍器每响一下对应的轮指音数（五指轮一轮 5 个音）。用于把「次/秒」换算成等效 BPM
    /// 后与目标 BPM 比较。若按四指轮练习，把这个值改成 4。
    private let notesPerBeat: Double = 5
    private let maxFlowerLayers = 3 // 重瓣最多 3 层
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

        // 取消台阶停顿与花瓣收拢任务，避免停止后画面还在动
        stageRestTask?.cancel()
        stageRestTask = nil
        closingTask?.cancel()
        closingTask = nil
        isStageResting = false
        isClosing = false
        petalCloseCount = 0
        
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
        
        // 按有效间隔数量加权；长而可靠的序列应比刚满 4 音的短序列更有代表性。
        let totalWeight = completedSequences.reduce(0) { $0 + max(1, $1.noteCount - 1) }
        uniformity = completedSequences.reduce(0.0) {
            $0 + $1.uniformity * Double(max(1, $1.noteCount - 1))
        } / Double(totalWeight)
        
        print("   - 累计平均速度: \(String(format: "%.1f", averageSpeed))次/秒")
        print("   - 累计均匀度: \(Int(uniformity * 100))%")
        
        // 连续优秀 → 叠加花层次数（重瓣），把「连续弹得好」累积成看得见的奖励；
        // 一旦评级掉下来就清零，重瓣消失，奖励与表现严格挂钩。
        if sequence.quality == .excellent {
            excellentStreak += 1
            flowerLayers = min(maxFlowerLayers, 1 + excellentStreak / 2)
        } else {
            excellentStreak = 0
            flowerLayers = 1
        }

        // 序列奖励分
        var bonusScore = scorePerSequence
        
        // 质量奖励
        switch sequence.quality {
        case .excellent:
            bonusScore = Int(Double(bonusScore) * 2.0) // 2x
            print("   🌟 优秀！奖励: \(bonusScore)分")
            bloomFlashCounter += 1 // 金色光晕：弹得好的即时正反馈
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
        
        // 更新花朵属性（亮度随速度、对称随均匀度）
        updateFlowerAttributes()
    }
    
    // MARK: - Flower Animation
    private func updateFlowerGrowth() {
        // 统计当前这朵花累计的音符数
        flowerNotes += 1

        // 处于「绽放」或「依次收拢」过渡期时，只累计、不更新显示
        if flowerBlooming || isClosing {
            return
        }

        let total = maxPetals * notesPerPetal // 长满一朵所需音符数（当前 8×14=112）

        // 长满一朵 → 直接绽放，不走台阶停顿
        if flowerNotes >= total {
            petalCount = maxPetals
            flowerGrowth = 1.0
            completeFlower()
            return
        }

        // ⚠️ 停顿期间彻底冻结显示（音符照常累计），这一步必须放在「新长出一圈」判断之前。
        // 旧实现把它写在后面，导致停顿期间一旦累计跨过下一级就立刻长出来并重新开始计时，
        // 停顿等于从未发生——这正是「感觉不到停顿」的根因。
        guard !isStageResting else { return }

        let newPetalCount = min(maxPetals, flowerNotes / notesPerPetal)

        // 新长出一圈：花瓣跳到这一圈的台阶大小，然后停一下再继续长
        if newPetalCount > petalCount {
            petalCount = newPetalCount
            flowerGrowth = Double(newPetalCount) / Double(maxPetals)
            beginStageRest()
            return
        }

        // 同一圈内平滑推进
        flowerGrowth = min(1.0, Double(flowerNotes) / Double(total))
    }

    /// 每长出一圈的停顿时长（秒），与演奏质量挂钩：
    /// 弹得越稳，停顿越短越顺；越不均匀，停顿越久，像花「攒着劲」才肯再长。
    /// 差距刻意拉开（0.25 ~ 1.25 秒，相差 5 倍），让「弹得差」明显更迟滞。
    private var stageRestDuration: TimeInterval {
        if let quality = lastSequenceQuality {
            switch quality {
            case .excellent: return 0.25
            case .good: return 0.55
            case .fair: return 0.90
            case .needsImprovement: return 1.25
            }
        }
        // 尚无任何序列评级时，按当前均匀度折算（最不稳时约 1.2 秒）
        return 0.5 + (1 - uniformity) * 0.7
    }

    private func beginStageRest() {
        isStageResting = true
        stageRestTask?.cancel()
        let duration = stageRestDuration
        stageRestTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self = self else { return }
            self.isStageResting = false
            // 补上停顿期间被冻结的真实生长量，避免花看起来「漏长」。
            // 用 spring 补，视觉上是「憋住了 → 继续长」。
            guard !self.flowerBlooming && !self.isClosing else { return }
            let total = self.maxPetals * self.notesPerPetal
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                self.petalCount = min(self.maxPetals, self.flowerNotes / self.notesPerPetal)
                self.flowerGrowth = min(1.0, Double(self.flowerNotes) / Double(total))
            }
        }
    }
    
    private func updateFlowerAttributes() {
        // 亮度基于速度（速度越快越亮）
        flowerBrightness = min(1.0, max(0.3, currentSpeed / 15.0))
        
        // 对称性基于均匀度
        flowerSymmetry = uniformity
    }
    
    /// 一朵花长满后的绽放 + 延迟归零，形成「生长→绽放→归零→重长」的持续循环。
    /// 旧实现只在 excellent 评级时才归零，而 excellent 几乎不可能触发，导致花长到
    /// 最大后永久定住。改为每长满一朵即归零重长，与轮指练习自然形成节奏感。
    private func completeFlower() {
        flowerBlooming = true

        // 满花绽放时取消尚未结束的台阶停顿，避免绽放期还在「呼吸」
        stageRestTask?.cancel()
        isStageResting = false

        // 绽放：花心与花瓣全开、亮度拉满
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            flowerGrowth = 1.0
            flowerBrightness = 1.0
        }
        
        // 停留约 4 秒让用户看清满花，再依次收拢花瓣、归零长下一朵
        closingTask?.cancel()
        closingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.beginPetalClosing()
        }
    }

    /// 满花后花瓣「依次」收拢，而不是整朵一下子消失——收完再归零长下一朵。
    /// 每片间隔 0.13 秒，8 片约 1 秒收完，视觉上是花瓣一片片合回去。
    private func beginPetalClosing() {
        guard isRunning else {
            // 已停止练习：直接归零，不做收拢动画
            withAnimation(.easeOut(duration: 0.35)) {
                flowerGrowth = 0
                petalCount = 0
                flowerNotes = 0
            }
            petalCloseCount = 0
            isClosing = false
            flowerBlooming = false
            return
        }

        isClosing = true
        petalCloseCount = 0
        let totalPetals = maxPetals

        closingTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            for i in 1...totalPetals {
                try? await Task.sleep(nanoseconds: 130_000_000)
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.24)) {
                    self.petalCloseCount = i
                }
            }

            try? await Task.sleep(nanoseconds: 320_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                self.flowerGrowth = 0
                self.petalCount = 0
                self.flowerNotes = 0
            }

            // 收拢状态稍后再清，避免新花刚发芽就带着「已收拢」的缩放
            try? await Task.sleep(nanoseconds: 420_000_000)
            if Task.isCancelled { return }
            self.petalCloseCount = 0
            self.isClosing = false
            self.flowerBlooming = false
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
                statusMessage = excellentStreak >= 2
                    ? "🌟 连续 \(excellentStreak) 次完美！重瓣 ×\(flowerLayers)"
                    : "🌟 完美轮指！继续保持！"
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
        flowerNotes = 0
        flowerBlooming = false
        stageRestTask?.cancel()
        stageRestTask = nil
        closingTask?.cancel()
        closingTask = nil
        isStageResting = false
        isClosing = false
        petalCloseCount = 0
        bloomFlashCounter = 0
        excellentStreak = 0
        flowerLayers = 1
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
