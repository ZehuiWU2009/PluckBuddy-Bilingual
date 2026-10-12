//
//  WavePracticeView.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/7/15.
//

import SwiftUI

struct WavePracticeView: View {
    @StateObject private var viewModel = WaveViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false  // ✨ 新增：控制设置弹窗
    
    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                colors: [Color.cyan.opacity(0.3), Color.blue.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // ✨ 自定义标题栏（带返回和设置按钮）
                ZStack {
                    // 标题（居中）
                    Text(L("扫弦水波"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.cyan, Color.blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    // 左侧返回按钮，右侧设置按钮
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.cyan)
                                .frame(width: 44, height: 44)
                                .background(Color.cyan.opacity(0.1))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            showSettings = true
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundStyle(.cyan)
                                .frame(width: 44, height: 44)
                                .background(Color.cyan.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // ✨ 节拍器指示栏（仅在启用时显示）
                        if viewModel.metronome.isEnabled && viewModel.isRunning {
                            MetronomeBar(
                                metronome: viewModel.metronome,
                                targetBPM: Int(viewModel.targetBPM)
                            )
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // 顶部统计栏（增加顶部间距）
                        HStack(spacing: 30) {
                            WaveStatItem(title: L("总计"), value: "\(viewModel.sweepCount)", icon: "waveform")
                            WaveStatItem(title: L("向上"), value: "\(viewModel.upCount)", icon: "arrow.up")
                            WaveStatItem(title: L("向下"), value: "\(viewModel.downCount)", icon: "arrow.down")
                            WaveStatItem(title: L("得分"), value: "\(viewModel.score)", icon: "star.fill")
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal)
                        
                        // ✨ 时长显示
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
                        
                        // 水波展示区域
                        ZStack {
                            WaterSurfaceView(
                                waves: viewModel.waves,
                                waterColor: viewModel.waterColor
                            )
                            
                            // ✨ 扫弦状态指示器（中心闪光）
                            if viewModel.isSweeping {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.white.opacity(0.8),
                                                Color.white.opacity(0.3),
                                                Color.clear
                                            ],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 50
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .scaleEffect(viewModel.isSweeping ? 1.2 : 0.8)
                                    .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: viewModel.isSweeping)
                                    .transition(.scale.combined(with: .opacity))
                            }
                            
                            // ✨ 等待提示（未扫弦时显示）
                            if viewModel.isRunning && !viewModel.isSweeping && viewModel.sweepCount == 0 {
                                VStack(spacing: 8) {
                                    Image(systemName: "hand.raised.fill")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.secondary)
                                    Text(L("开始扫弦..."))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .transition(.opacity)
                            }
                        }
                        .frame(width: 280, height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.1), radius: 10)
                        .padding(.horizontal)
                        
                        // 力度和平衡度指示器
                        VStack(spacing: 12) {
                            // 力度显示
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(.secondary)
                                Text(L("平均力度"))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(viewModel.averageStrength * 100))%")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(strengthColor)
                            }
                            
                            ProgressView(value: viewModel.averageStrength)
                                .tint(strengthColor)
                                .scaleEffect(y: 1.5)
                            
                            // 方向平衡度
                            HStack {
                                Image(systemName: "arrow.up.arrow.down")
                                    .foregroundStyle(.secondary)
                                Text(L("方向平衡"))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(viewModel.directionBalance * 100))%")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(balanceColor)
                            }
                            
                            ProgressView(value: viewModel.directionBalance)
                                .tint(balanceColor)
                                .scaleEffect(y: 1.5)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                        
                        // ✅ 琵琶声检测状态行（已回退 DSP 启发式，不再显示）
                        // 状态提示
                        Text(viewModel.statusMessage)
                            .font(.body)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .frame(minHeight: 50)
                        
                        // 开始/停止按钮
                        Button(action: togglePractice) {
                            HStack(spacing: 12) {
                                Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                                    .font(.title3)
                                Text(viewModel.isRunning ? L("停止练习") : L("开始练习"))
                                    .fontWeight(.semibold)
                                    .font(.headline)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(viewModel.isRunning ? Color.red : Color.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: (viewModel.isRunning ? Color.red : Color.cyan).opacity(0.3), radius: 8, y: 4)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            WaveSettingsSheet(
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
        .navigationBarHidden(true)
    }
    
    // MARK: - Computed Properties
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
    
    private var strengthColor: Color {
        if viewModel.averageStrength > 0.7 {
            return .green
        } else if viewModel.averageStrength > 0.4 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var balanceColor: Color {
        if viewModel.directionBalance > 0.4 {
            return .green
        } else if viewModel.directionBalance > 0.2 {
            return .orange
        } else {
            return .red
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

// MARK: - Water Surface View
struct WaterSurfaceView: View {
    let waves: [WaveRipple]
    let waterColor: Color
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                // 水面背景
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [
                            waterColor.opacity(0.3),
                            waterColor.opacity(0.6)
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
                
                // 绘制所有水波
                for wave in waves {
                    drawWave(wave, in: context, size: size)
                }
            }
        }
    }
    
    private func drawWave(_ wave: WaveRipple, in context: GraphicsContext, size: CGSize) {
        let centerX = wave.center.x * size.width
        let centerY = wave.center.y * size.height
        let center = CGPoint(x: centerX, y: centerY)
        
        // ✨ 使用 wave 的实时计算进度
        let progress = wave.progress
        let opacity = wave.opacity
        
        // 根据进度计算当前半径
        let currentRadius = wave.maxRadius * min(size.width, size.height) * CGFloat(progress)
        
        // 绘制多个同心圆环（增强波纹效果）
        for i in 0..<3 {
            let delay = Double(i) * 0.15 // 每个圆环延迟 0.15 秒
            let adjustedProgress = max(0, progress - delay)
            
            guard adjustedProgress > 0 else { continue }
            
            let adjustedRadius = currentRadius * CGFloat(adjustedProgress / progress)
            let adjustedOpacity = opacity * (1.0 - Double(i) * 0.2) // 外圈更透明
            
            // 绘制圆环
            let path = Path { p in
                p.addEllipse(in: CGRect(
                    x: center.x - adjustedRadius,
                    y: center.y - adjustedRadius,
                    width: adjustedRadius * 2,
                    height: adjustedRadius * 2
                ))
            }
            
            context.stroke(
                path,
                with: .color(wave.color.opacity(adjustedOpacity)),
                lineWidth: 3 - CGFloat(i) * 0.5 // 外圈线更细
            )
        }
    }
}

// MARK: - Wave Stat Item
struct WaveStatItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        WavePracticeView()
    }
}

