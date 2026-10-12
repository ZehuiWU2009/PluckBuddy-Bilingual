//
//  FlowerPracticeView.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/7/15.
//

import SwiftUI

struct FlowerPracticeView: View {
    @StateObject private var viewModel = FlowerViewModel()
    @State private var showSettings = false  // ✨ 新增：控制设置弹窗
    
    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                colors: [Color.pink.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {  // ✨ 添加 ScrollView 防止内容超出屏幕
                VStack(spacing: 20) {  // ✨ 减小间距从 30 到 20
                    // ✨ 节拍器指示栏（仅在启用时显示）
                    if viewModel.metronome.isEnabled && viewModel.isRunning {
                        MetronomeBar(
                            metronome: viewModel.metronome,
                            targetBPM: Int(viewModel.targetBPM)
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // 顶部统计栏
                    HStack(spacing: 40) {
                        FlowerStatItem(title: L("轮指"), value: "\(viewModel.rollCount)", icon: "hand.tap.fill")
                        FlowerStatItem(title: L("序列"), value: "\(viewModel.sequenceCount)", icon: "rectangle.3.group")
                        FlowerStatItem(title: L("得分"), value: "\(viewModel.score)", icon: "star.fill")
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal)
                    
                    // 时长显示
                    if viewModel.isRunning {
                        HStack(spacing: 12) {
                            Image(systemName: "timer")
                                .foregroundStyle(.secondary)
                            Text(timeDisplay)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            
                            if viewModel.targetDuration > 0 {
                                Text("/ \(targetTimeDisplay)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    
                    //Spacer()  // ✨ 在 ScrollView 中不需要 Spacer
                    
                    // 花朵展示区域
                    ZStack {
                        FlowerView(
                            growth: viewModel.flowerGrowth,
                            petalCount: viewModel.petalCount,
                            brightness: viewModel.flowerBrightness,
                            symmetry: viewModel.flowerSymmetry,
                            isRolling: viewModel.isRolling,
                            pulseCounter: viewModel.pulseCounter // ✨ 传递脉冲计数器
                        )
                        .frame(width: 220, height: 220)  // ✨ 缩小from 250
                        
                        // 序列质量指示器
                        if let quality = viewModel.lastSequenceQuality {
                            VStack {
                                Spacer()
                                HStack(spacing: 6) {
                                    Text(quality.emoji)
                                        .font(.title3)  // ✨ 缩小
                                    Text(quality.description)
                                        .font(.subheadline)  // ✨ 缩小
                                        .foregroundStyle(qualityColor(quality))
                                }
                                .padding(.horizontal, 12)  // ✨ 缩小 padding
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .transition(.scale.combined(with: .opacity))
                            }
                            .frame(height: 220)  // ✨ 匹配花朵大小
                        }
                    }
                    .padding(.horizontal)  // ✨ 减小 padding
                    
                    // 速度和均匀度指示器
                    VStack(spacing: 12) {  // ✨ 减小间距
                        // 速度显示
                        HStack {
                            Image(systemName: "speedometer")
                                .font(.caption)  // ✨ 缩小图标
                                .foregroundStyle(.secondary)
                            Text(String(format: L("速度: %.1f 次/秒"), viewModel.currentSpeed))
                                .font(.subheadline)  // ✨ 缩小字体
                            Spacer()
                            Text(String(format: L("均值: %.1f"), viewModel.averageSpeed))
                                .font(.caption)  // ✨ 缩小字体
                                .foregroundStyle(.secondary)
                        }
                        
                        // 均匀度进度条
                        VStack(alignment: .leading, spacing: 6) {  // ✨ 减小间距
                            HStack {
                                Image(systemName: "waveform.path")
                                    .font(.caption)  // ✨ 缩小图标
                                    .foregroundStyle(.secondary)
                                Text(L("均匀度"))
                                    .font(.subheadline)  // ✨ 缩小字体
                                Spacer()
                                Text("\(Int(viewModel.uniformity * 100))%")
                                    .font(.caption)  // ✨ 缩小字体
                                    .foregroundStyle(uniformityColor)
                            }
                            
                            ProgressView(value: viewModel.uniformity)
                                .tint(uniformityColor)
                                .scaleEffect(y: 1.5)  // ✨ 减小高度
                        }
                    }
                    .padding(.horizontal, 12)  // ✨ 减小 padding
                    .padding(.vertical, 10)  // ✨ 减小 padding
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    
                    // ✅ 琵琶声检测状态行（已回退 DSP 启发式，不再显示）
                    // 状态提示
                    Text(viewModel.statusMessage)
                        .font(.body)  // ✨ 缩小字体
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .frame(minHeight: 50)  // ✨ 减小最小高度
                    
                    // 开始/停止按钮
                    Button(action: togglePractice) {
                        HStack {
                            Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                            Text(viewModel.isRunning ? L("停止练习") : L("开始练习"))
                                .fontWeight(.semibold)
                        }
                        .font(.headline)  // ✨ 缩小字体
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)  // ✨ 减小垂直 padding
                        .background(viewModel.isRunning ? Color.red : Color.pink)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)  // ✨ 确保底部有足够边距
                }
            }  // ScrollView 结束
        }
        .sheet(isPresented: $showSettings) {
            FlowerSettingsSheet(
                targetBPM: $viewModel.targetBPM,
                targetDuration: $viewModel.targetDuration,
                metronomeEnabled: Binding(
                    get: { viewModel.metronomeIsEnabled },
                    set: { viewModel.metronomeIsEnabled = $0 }
                ),
                metronomeSoundType: Binding(
                    get: { viewModel.metronomeSoundType },
                    set: { viewModel.metronomeSoundType = $0 }
                )
            )
        }
        .navigationTitle(L("轮指花开"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    private var uniformityColor: Color {
        if viewModel.uniformity > 0.8 {
            return .green
        } else if viewModel.uniformity > 0.5 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var timeDisplay: String {
        let minutes = Int(viewModel.sessionDuration / 60)
        let seconds = Int(viewModel.sessionDuration.truncatingRemainder(dividingBy: 60))
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
    
    private var targetTimeDisplay: String {
        let minutes = Int(viewModel.targetDuration / 60)
        let seconds = Int(viewModel.targetDuration.truncatingRemainder(dividingBy: 60))
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
    
    private func qualityColor(_ quality: RollSequence.Quality) -> Color {
        switch quality {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .needsImprovement: return .red
        }
    }
    
    // MARK: - Actions
    private func togglePractice() {
        if viewModel.isRunning {
            viewModel.stopPractice()
        } else {
            viewModel.startPractice()
        }
    }
}

// MARK: - Flower View
struct FlowerView: View {
    let growth: Double // 0-1
    let petalCount: Int
    let brightness: Double // 0-1
    let symmetry: Double // 0-1
    let isRolling: Bool // 是否正在轮指
    let pulseCounter: Int // ✨ 新增：脉冲计数器参数
    
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        ZStack {
            // 背景圆圈
            Circle()
                .fill(Color.green.opacity(0.1))
            
            // 花瓣
            ForEach(0..<8) { index in
                if index < petalCount {
                    Petal(
                        rotation: Double(index) * 45 + rotationAngle,
                        scale: growth * symmetry,
                        color: petalColor,
                        pulseCounter: pulseCounter // ✨ 传递脉冲计数器
                    )
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: growth)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: petalCount)
                }
            }
            
            // 花心
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.yellow, Color.orange],
                        center: .center,
                        startRadius: 0,
                        endRadius: 30
                    )
                )
                .frame(width: 60, height: 60)
                .opacity(growth > 0 ? 1 : 0)
                .scaleEffect(growth)
                .scaleEffect(isRolling ? 1.1 : 1.0) // 轮指时轻微放大
                .animation(.spring(response: 0.5), value: growth)
                .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isRolling)
        }
        .rotationEffect(.degrees(rotationAngle))
        .onChange(of: pulseCounter) { oldValue, newValue in
            // ✨ 监听脉冲计数器变化，触发旋转动画
            if newValue > oldValue {
                withAnimation(.easeOut(duration: 0.3)) {
                    rotationAngle += 45 // 每次旋转45度（一个花瓣的角度）
                }
            }
        }
    }
    
    private var petalColor: Color {
        // 根据亮度调整颜色
        let hue = 0.9 // 粉红色调
        let saturation = 0.6 + (brightness * 0.4)
        let lightness = 0.5 + (brightness * 0.2)
        
        return Color(hue: hue, saturation: saturation, brightness: lightness)
    }
}

// MARK: - Petal Shape
struct Petal: View {
    let rotation: Double
    let scale: Double
    let color: Color
    let pulseCounter: Int // ✨ 改用计数器而非布尔值
    
    @State private var pulseScale: Double = 1.0
    
    var body: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 50, height: 100)
            .offset(y: -60)
            .scaleEffect(pulseScale)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
            .onChange(of: pulseCounter) { oldValue, newValue in
                // ✨ 修复：每次计数器变化时触发新的脉冲
                guard newValue > oldValue else { return }
                
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                    pulseScale = 1.2
                }
                
                // 恢复原状
                Task {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            pulseScale = 1.0
                        }
                    }
                }
            }
    }
}

// MARK: - Stat Item (Reuse from RunningPracticeView)
struct FlowerStatItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        FlowerPracticeView()
    }
}

