//
//  LottieRunnerView.swift
//  PluckBuddy
//
//  Lottie 跑步动画视图
//

import SwiftUI
import Lottie

struct LottieRunnerView: View {
    let isRunning: Bool  // 是否正在弹奏（控制动画）
    let currentBPM: Double
    
    @State private var animationPhase: Double = 0
    
    // 根据 BPM 计算播放速度
    private var animationSpeed: CGFloat {
        guard currentBPM > 0 else { return 1.0 }
        return CGFloat(currentBPM / 120.0)
    }
    
    var body: some View {
        ZStack {
            // 尝试加载 Lottie 动画
            if let animation = LottieAnimation.named("running_man") {
                // 使用 Lottie 动画
                LottieViewWrapper(
                    animation: animation,
                    isRunning: isRunning,
                    speed: animationSpeed
                )
                .frame(width: 200, height: 200)
            } else {
                // 备用方案：使用 SF Symbol
                VStack(spacing: 8) {
                    Image(systemName: isRunning ? "figure.run" : "figure.stand")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .rotationEffect(.degrees(isRunning ? animationPhase * 10 : 0))
                        .offset(y: isRunning ? sin(animationPhase * .pi * 2) * 5 : 0)
                    
                    // 提示信息
                    Text(isRunning ? L("运行中...") : L("等待中..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            print("✅ LottieRunnerView 加载")
            checkAnimation()
        }
        // 监听弹奏状态变化
        .onChange(of: isRunning) { _, newValue in
            print("🎬 LottieRunnerView.isRunning: \(newValue), BPM: \(currentBPM)")
            
            if newValue {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
        // 监听速度变化
        .onChange(of: currentBPM) { oldValue, newValue in
            print("🎵 LottieRunnerView.currentBPM: \(String(format: "%.1f", oldValue)) → \(String(format: "%.1f", newValue)), isRunning: \(isRunning)")
            
            if isRunning && newValue > 0 {
                print("   → 重启动画")
                startAnimation()
            } else if isRunning && newValue == 0 {
                print("   ⚠️ isRunning=true 但 BPM=0")
            }
        }
    }
    
    private func startAnimation() {
        guard currentBPM > 0 else {
            print("   ⚠️ BPM=0，跳过动画")
            return
        }
        
        let duration = max(0.3, 60.0 / currentBPM)
        print("   ✓ 准备启动动画，周期: \(String(format: "%.2f", duration))秒，当前phase: \(String(format: "%.2f", animationPhase))")
        
        // 先彻底停止现有动画
        withAnimation(.linear(duration: 0)) {
            animationPhase = 0
        }
        
        // 等待SwiftUI清理动画（关键！）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            print("   → 延迟后启动，BPM: \(String(format: "%.1f", self.currentBPM))")
            guard self.currentBPM > 0 else {
                print("   ⚠️ 延迟后BPM=0，取消启动")
                return
            }
            
            let newDuration = max(0.3, 60.0 / self.currentBPM)
            withAnimation(.linear(duration: newDuration).repeatForever(autoreverses: false)) {
                self.animationPhase = 1.0
            }
            print("   ✓ 动画已启动！")
        }
    }
    
    // 停止动画
    private func stopAnimation() {
        print("   ✓ 停止动画")
        
        // 明确停止 repeatForever 动画
        withAnimation(.linear(duration: 0)) {
            animationPhase = 0
        }
    }
    
    private func checkAnimation() {
        if LottieAnimation.named("running_man") == nil {
            print("⚠️ 警告：找不到 running_man.json 动画文件，使用备用图标")
        } else {
            print("✅ 成功加载 Lottie 动画")
        }
    }
}

// MARK: - Lottie View Wrapper (使用 UIViewRepresentable)
struct LottieViewWrapper: UIViewRepresentable {
    let animation: LottieAnimation
    let isRunning: Bool
    let speed: CGFloat
    
    // 使用 Coordinator 来跟踪状态变化
    class Coordinator {
        var lastIsRunning: Bool = false
        var lastSpeed: CGFloat = 0
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> LottieAnimationView {
        let animationView = LottieAnimationView(animation: animation)
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = .loop
        animationView.backgroundBehavior = .pauseAndRestore
        
        // 设置透明背景（适用于透明背景的动画）
        animationView.backgroundColor = .clear
        
        return animationView
    }
    
    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        let coordinator = context.coordinator
        let wasRunning = coordinator.lastIsRunning
        let speedChanged = abs(coordinator.lastSpeed - speed) > 0.1
        
        print("      🎬 LottieViewWrapper.updateUIView - isRunning:\(wasRunning)→\(isRunning), speed:\(String(format: "%.1f", speed)), isPlaying:\(uiView.isAnimationPlaying), progress:\(String(format: "%.2f", uiView.currentProgress))")
        
        // 更新播放速度
        let newSpeed = max(0.5, min(3.0, speed))
        if abs(uiView.animationSpeed - newSpeed) > 0.01 {
            print("      → 更新速度: \(uiView.animationSpeed) → \(newSpeed)")
            uiView.animationSpeed = newSpeed
        }
        
        // 根据弹奏状态控制播放
        if isRunning {
            // 检测从停止到运行的转换（关键！）
            if !wasRunning {
                print("      → Lottie 从停止状态恢复，强制完全重置并播放")
                // 完全停止
                uiView.stop()
                // 重置到开始
                uiView.currentProgress = 0
                // 重新播放
                uiView.play(fromProgress: 0, toProgress: 1, loopMode: .loop) { finished in
                    if !finished {
                        print("      ⚠️ Lottie 播放被中断")
                    }
                }
                print("      ✓ Lottie play() 已调用")
            } else if !uiView.isAnimationPlaying {
                print("      → Lottie 未在播放，启动播放")
                uiView.play()
            } else if speedChanged {
                print("      → Lottie 速度变化 \(String(format: "%.1f", coordinator.lastSpeed)) → \(String(format: "%.1f", speed))，重新播放")
                uiView.stop()
                uiView.currentProgress = 0
                uiView.play()
            } else {
                print("      → Lottie 正常播放中")
            }
        } else {
            // 停止并回到第一帧
            if uiView.isAnimationPlaying || uiView.currentProgress > 0 {
                print("      → Lottie 停止并重置")
                uiView.stop()
                uiView.currentProgress = 0
            }
        }
        
        // 更新记录的状态
        coordinator.lastIsRunning = isRunning
        coordinator.lastSpeed = speed
    }
}

#Preview {
    LottieRunnerView(isRunning: true, currentBPM: 120)
        .frame(width: 300, height: 300)
        .background(Color.gray.opacity(0.2))
}
