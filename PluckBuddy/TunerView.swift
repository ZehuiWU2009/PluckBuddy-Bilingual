//
//  TunerView.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/7/15.
//

import SwiftUI

struct TunerView: View {
    @StateObject private var viewModel = TunerViewModel()
    
    var body: some View {
        VStack(spacing: 15) {
            // 顶部说明和波形
            VStack(spacing: 12) {
                HStack {
                    Text(L("请依次调整每根弦"))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // ✅ 琵琶声过滤开关
                    Toggle(isOn: $viewModel.pipaFilterEnabled) {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.pipaFilterEnabled ? "waveform.path" : "waveform")
                                .font(.caption)
                            Text(viewModel.pipaFilterEnabled ? L("琵琶模式") : L("通用模式"))
                                .font(.caption)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(.blue)
                }
                .padding(.horizontal)
                
                // ✅ CoreML 判门状态：让「先判琵琶声、再判音高」可见
                HStack(spacing: 6) {
                    if viewModel.pipaFilterEnabled {
                        Image(systemName: viewModel.pipaSoundDetected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                            .foregroundStyle(viewModel.pipaSoundDetected ? Color.green : Color.gray)
                        Text(viewModel.pipaSoundDetected ? L("已检测到琵琶声") : (viewModel.pipaGateAvailable ? L("聆听中…等待琵琶声") : L("模型未加载，已降级")))
                            .font(.caption)
                            .foregroundStyle(viewModel.pipaSoundDetected ? Color.green : (viewModel.pipaGateAvailable ? Color.secondary : Color.orange))

                        // 判门概率：调音没反馈时用于区分「没听到琵琶声」和「听到了但音高没测到」
                        if viewModel.pipaGateAvailable {
                            Text(String(format: L("琵琶概率 %.0f%%"), viewModel.pipaScoreValue * 100))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        // 关掉过滤时给个轻提示，避免用户以为界面挂了
                        Image(systemName: "waveform")
                            .foregroundStyle(.secondary)
                        Text(L("通用模式：不区分声音类型"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 实时波形显示
                WaveformView(amplitudes: viewModel.waveformData)
                    .frame(height: 90)
                    .padding(.horizontal)
                
                if viewModel.frequency > 0 {
                    HStack(spacing: 8) {
                        Text(String(format: "%.1f Hz", viewModel.frequency))
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(.primary)
                        
                        // 置信度指示器
                        HStack(spacing: 2) {
                            ForEach(0..<3) { index in
                                Circle()
                                    .fill(viewModel.confidence > Double(index) * 0.33 ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }
            }
            .padding(.top)
            
            Spacer()
            
            // 四根弦横向排列：从左到右 子弦 → 缠弦，音高由高到低
            // 间距 28 是为了给挂在指示条左侧的刻度数字留出空隙（数字不参与布局宽度）
            HStack(spacing: 28) {
                Spacer()
                
                ForEach(TunerViewModel.pipaStrings.indices, id: \.self) { index in
                    let string = TunerViewModel.pipaStrings[index]
                    let isActive = viewModel.detectedNote == string.name
                    
                    StringTuner(
                        stringName: string.traditionalName,
                        note: string.name,
                        frequency: string.frequency,
                        isActive: isActive,
                        centOffset: isActive ? viewModel.centOffset : 0,
                        isTuned: isActive && viewModel.isTuned
                    )
                }
                
                Spacer()
            }
            
            Spacer()
            
            // 底部提示
            VStack(spacing: 12) {
                Text(viewModel.tuningMessage)
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(viewModel.isTuned ? .green : .primary)
                    .animation(.easeInOut, value: viewModel.tuningMessage)
                
                if viewModel.frequency > 0 {
                    Text(String(format: "%+.0f cents", viewModel.centOffset))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(
                            abs(viewModel.centOffset) < 5 ? .green :
                            abs(viewModel.centOffset) < 15 ? .orange : .red
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
        .navigationTitle(L("智能调音"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .onChange(of: viewModel.isTuned) { oldValue, newValue in
            if !oldValue && newValue {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }
}

// MARK: - Waveform View (升级为频谱分析器)
struct WaveformView: View {
    let amplitudes: [Float]
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard !amplitudes.isEmpty else { return }
                
                let width = size.width
                let height = size.height
                
                // 绘制背景渐变
                let backgroundGradient = Gradient(colors: [
                    Color.blue.opacity(0.1),
                    Color.cyan.opacity(0.05)
                ])
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        backgroundGradient,
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: height)
                    )
                )
                
                // 绘制柱状频谱
                let barCount = amplitudes.count
                let barWidth = width / CGFloat(barCount)
                let spacing: CGFloat = 1
                
                for (index, amplitude) in amplitudes.enumerated() {
                    let x = CGFloat(index) * barWidth
                    
                    // 归一化振幅（0-1）
                    let normalizedAmp = min(1.0, abs(amplitude))
                    let barHeight = CGFloat(normalizedAmp) * height * 0.95
                    
                    // 根据振幅计算颜色（从绿色到黄色到红色）
                    let color: Color
                    if normalizedAmp < 0.3 {
                        color = .green
                    } else if normalizedAmp < 0.6 {
                        color = .yellow
                    } else {
                        color = .orange
                    }
                    
                    // 绘制柱状条
                    let barRect = CGRect(
                        x: x,
                        y: height - barHeight,
                        width: barWidth - spacing,
                        height: barHeight
                    )
                    
                    // 渐变填充
                    let gradient = Gradient(colors: [
                        color,
                        color.opacity(0.3)
                    ])
                    context.fill(
                        Path(roundedRect: barRect, cornerRadius: 2),
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: barRect.midX, y: barRect.maxY),
                            endPoint: CGPoint(x: barRect.midX, y: barRect.minY)
                        )
                    )
                    
                    // 顶部高光点
                    if normalizedAmp > 0.1 {
                        let dotRect = CGRect(
                            x: x + (barWidth - spacing) / 2 - 2,
                            y: height - barHeight - 3,
                            width: 4,
                            height: 4
                        )
                        context.fill(
                            Path(ellipseIn: dotRect),
                            with: .color(.white.opacity(0.8))
                        )
                    }
                }
                
                // 绘制中心参考线
                let midY = height / 2
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: midY))
                        path.addLine(to: CGPoint(x: width, y: midY))
                    },
                    with: .color(.white.opacity(0.2)),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
            }
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.blue.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .cyan.opacity(0.2), radius: 8, y: 4)
    }
}

// MARK: - String Tuner (单根弦的调音指示器)
struct StringTuner: View {
    let stringName: String
    let note: String
    let frequency: Double
    let isActive: Bool
    let centOffset: Double
    let isTuned: Bool

    /// 音名圆直径（同时决定整列宽度）
    private let dotSize: CGFloat = 56
    /// 指示条宽度
    private let barWidth: CGFloat = 52
    /// 指示条上 / 中 / 下三段高度
    private let upperHeight: CGFloat = 105
    private let centerHeight: CGFloat = 50
    private let lowerHeight: CGFloat = 105
    /// 刻度数字列宽与间距。数字用 overlay 挂在指示条左侧，不参与布局宽度，
    /// 因此指示条能严格与上方音名圆同轴居中。
    private let scaleWidth: CGFloat = 22
    private let scaleGap: CGFloat = 5

    private var barHeight: CGFloat { upperHeight + centerHeight + lowerHeight }

    var body: some View {
        VStack(spacing: 12) {
            // 弦名标签：子弦 / 中弦 / 老弦 / 缠弦
            Text(L(stringName))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // 音名
            Text(note)
                .font(.title.weight(.bold))
                .foregroundStyle(isActive ? (isTuned ? .green : .primary) : .secondary)
                .frame(width: dotSize, height: dotSize)
                .background(
                    Circle()
                        .fill(isActive ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                        .overlay(
                            Circle()
                                .stroke(isActive ? (isTuned ? Color.green : Color.blue) : Color.gray.opacity(0.3), lineWidth: 2)
                        )
                )
                .scaleEffect(isActive ? 1.1 : 1.0)
                .animation(.spring(response: 0.3), value: isActive)

            // 竖向音准指示器（与上方音名圆同轴）
            indicatorBar
                .frame(width: barWidth)
                .overlay(alignment: .leading) {
                    scaleLabels
                        .frame(width: scaleWidth, height: barHeight)
                        .offset(x: -(scaleWidth + scaleGap))
                }

            // 频率标签
            Text(String(format: "%.1f Hz", frequency))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - 指示条

    private var indicatorBar: some View {
        VStack(spacing: 0) {
            // 偏高区域
            Rectangle()
                .fill(Color.red.opacity(0.1))
                .frame(width: barWidth, height: upperHeight)
                .overlay(alignment: .top) {
                    Text(L("高"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .overlay { tickLines }

            // 准确区域
            Rectangle()
                .fill(Color.green.opacity(0.25))
                .frame(width: barWidth, height: centerHeight)
                .overlay {
                    Text("✓")
                        .font(.title2)
                        .foregroundStyle(.green)
                }

            // 偏低区域
            Rectangle()
                .fill(Color.red.opacity(0.1))
                .frame(width: barWidth, height: lowerHeight)
                .overlay(alignment: .bottom) {
                    Text(L("低"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
                .overlay { tickLines }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .center) {
            // 指针箭头
            if isActive {
                Image(systemName: "arrowtriangle.right.fill")
                    .foregroundStyle(isTuned ? .green : .red)
                    .font(.system(size: 16))
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .offset(y: calculateArrowOffset(cents: centOffset))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: centOffset)
            }
        }
    }

    /// 刻度线
    private var tickLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<5) { i in
                Divider()
                    .background(Color.gray.opacity(0.3))
                if i < 4 {
                    Spacer()
                }
            }
        }
    }

    /// 左侧刻度数字。按指示条三段的分界线精确定位，不再用等分 Spacer，
    /// 避免 "+50" 这类文字被压窄后换行（原来会拆成 "+5 0"）。
    private var scaleLabels: some View {
        ZStack {
            Text("+50")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(y: -(barHeight / 2 - 9))

            Text("+25")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(y: -(barHeight / 4))

            Text("0")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text("-25")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(y: barHeight / 4)

            Text("-50")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(y: barHeight / 2 - 9)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .allowsTightening(true)
    }

    /// 计算箭头位置偏移
    /// cents 范围：-50 到 +50，对应 ±半个指示条高度
    private func calculateArrowOffset(cents: Double) -> CGFloat {
        let clampedCents = max(-50, min(50, cents))
        // 负值表示偏低（箭头向下），正值表示偏高（箭头向上）
        return CGFloat(-clampedCents) * (barHeight / 2 / 50)
    }
}

#Preview {
    NavigationStack {
        TunerView()
    }
}

