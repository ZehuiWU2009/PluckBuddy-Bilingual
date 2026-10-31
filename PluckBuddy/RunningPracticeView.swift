//
//  RunningPracticeView.swift
//  PluckBuddy
//
//  Created by Zehui Wu on 2026/7/15.
//

import SwiftUI
import Lottie  // Lottie 动画支持

struct RunningPracticeView: View {
    @StateObject private var viewModel = RunningViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false  // 控制设置弹窗
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景渐变
                LinearGradient(
                    colors: [Color.blue.opacity(0.3), Color.green.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    // ✨ 新增：节拍器栏（条件显示）
                    if viewModel.metronome.isEnabled {
                        MetronomeBar(
                            metronome: viewModel.metronome,
                            targetBPM: Int(viewModel.targetBPM)  // ✨ 传递目标速度
                        )
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // 新顶部栏：设置按钮 + BPM 目标 + 剩余时间（简化版）
                    TopControlBar(
                        targetBPM: viewModel.targetBPM,
                        targetDuration: viewModel.targetDuration,
                        elapsedTime: viewModel.sessionDuration,
                        canEditSettings: !viewModel.isRunning,
                        onSettingsTapped: { showSettings = true }
                    )
                    .frame(height: geometry.size.height * 0.08)
                    .padding(.horizontal)
                    
                    // 跑步场景（扩大到 70% 高度）
                    CompactRunningSceneView(
                        score: viewModel.score,  // 新增：传递得分
                        trackOffset: viewModel.trackOffset,
                        runningSpeed: viewModel.runningSpeed,
                        isRunning: viewModel.isRunning,
                        isPlucking: viewModel.isPlucking,  // 新增：传递弹奏状态
                        currentBPM: viewModel.currentBPM,
                        stability: viewModel.stability,
                        sessionDuration: viewModel.sessionDuration,
                        statusMessage: viewModel.statusMessage
                    )
                    .frame(height: geometry.size.height * 0.70)
                    .padding(.horizontal)
                
                Spacer()
                    
                    // 开始/停止按钮
                    Button(action: togglePractice) {
                        HStack(spacing: 12) {
                            Image(systemName: viewModel.isRunning ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title2)
                            Text(viewModel.isRunning ? L("停止练习") : L("开始练习"))
                                .fontWeight(.semibold)
                        }
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(viewModel.isRunning ? Color.red : Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            PracticeSettingsSheet(
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
        .navigationTitle(L("弹挑跑步"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // ✨ 节拍器开关按钮
                Button(action: {
                    withAnimation(.spring()) {
                        viewModel.metronome.isEnabled.toggle()
                    }
                }) {
                    Image(systemName: viewModel.metronome.isEnabled ? "metronome.fill" : "metronome")
                        .foregroundStyle(viewModel.metronome.isEnabled ? .green : .primary)
                }
            }
        }
        .onDisappear {
            // ✨ 离开界面时停止节拍器
            viewModel.metronome.stop()
        }
    }
    
    // MARK: - Computed Properties
    private var stabilityColor: Color {
        if viewModel.stability > 0.8 {
            return .green
        } else if viewModel.stability > 0.5 {
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

// MARK: - Top Control Bar（顶部控制栏 - 简化版）
struct TopControlBar: View {
    let targetBPM: Double  // 改为只读
    let targetDuration: TimeInterval
    let elapsedTime: TimeInterval
    let canEditSettings: Bool  // 是否可以编辑设置
    let onSettingsTapped: () -> Void  // 设置按钮回调
    
    // 计算剩余时间
    private var remainingTime: TimeInterval {
        max(0, targetDuration - elapsedTime)
    }
    
    // 格式化时间显示
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // 设置按钮（仅在未开始时显示）
            if canEditSettings {
                Button(action: onSettingsTapped) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            
            // BPM 目标显示（只读，无调整按钮）
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(.orange)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                        Text(L("目标速度"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Text("\(Int(targetBPM))")
                            .font(.title3)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .frame(minWidth: 50, alignment: .center)
                        
                        Text("BPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // 剩余时间显示
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundStyle(.blue)
                    .font(.title3)
                
                VStack(alignment: .center, spacing: 2) {
                    Text(L("剩余时间"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatTime(remainingTime))
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(remainingTime < 30 ? .red : .primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Compact Running Scene View（紧凑版跑步场景）
struct CompactRunningSceneView: View {
    let score: Int  // 新增：得分
    let trackOffset: Double
    let runningSpeed: Double
    let isRunning: Bool
    let isPlucking: Bool  // 新增：弹奏状态（控制动画）
    let currentBPM: Double
    let stability: Double
    let sessionDuration: TimeInterval
    let statusMessage: String
    
    @State private var animationPhase: Double = 0
    @State private var trackScrollOffset: CGFloat = 0
    
    private var animationDuration: Double {
        guard currentBPM > 0 else { return 1.0 }
        return 60.0 / currentBPM
    }
    
    private var stabilityColor: Color {
        if stability > 0.8 {
            return .green
        } else if stability > 0.5 {
            return .orange
        } else {
            return .red
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景渐变
                LinearGradient(
                    colors: [Color.cyan.opacity(0.3), Color.blue.opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // 移动的跑道
                MovingTrackView(
                    offset: trackScrollOffset,
                    speed: currentBPM, // 直接使用 BPM
                    isActive: isPlucking  // 使用弹奏状态控制动画
                )
                
                // Lottie 跑步小人
                LottieRunnerView(
                    isRunning: isPlucking,  // 使用弹奏状态控制动画
                    currentBPM: currentBPM
                )
                .position(
                    x: geometry.size.width * 0.4,
                    y: geometry.size.height * 0.6
                )
                .scaleEffect(0.4) // 缩小到 40%（之前是 80%）
                
                // 实时数据叠加层（右侧）
                VStack {
                    HStack {
                        // 左上角：得分显示（放大）
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.title2)
                                .foregroundStyle(.yellow)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("得分"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(score)")
                                    .font(.title)  // 放大数字
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.leading, 12)
                        .padding(.top, 12)
                        
                        Spacer()
                        
                        // 右上角：实时数据
                        VStack(alignment: .trailing, spacing: 8) {
                            // 速度
                            DataBadge(
                                icon: "speedometer",
                                value: "\(Int(currentBPM))",
                                unit: "BPM",
                                color: .blue
                            )
                            
                            // 稳定性
                            DataBadge(
                                icon: "waveform",
                                value: "\(Int(stability * 100))",
                                unit: "%",
                                color: stabilityColor
                            )
                            
                            // 时长
                            DataBadge(
                                icon: "timer",
                                value: formatDuration(sessionDuration),
                                unit: "",
                                color: .orange
                            )
                        }
                        .padding(.trailing, 12)
                        .padding(.top, 12)
                    }
                    
                    Spacer()
                    
                    // 状态消息（底部居中）
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .onAppear {
            startAnimation()
        }
        .onChange(of: isRunning) { _, newValue in
            if newValue {
                startAnimation()
            }
        }
    }
    
    private func startAnimation() {
        withAnimation(.linear(duration: animationDuration).repeatForever(autoreverses: false)) {
            animationPhase = 1.0
        }
        
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
            trackScrollOffset = -100
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Moving Track View（横版移动跑道）
struct MovingTrackView: View {
    let offset: CGFloat
    let speed: Double
    let isActive: Bool
    
    @State private var scrollOffset: CGFloat = 0
    @State private var isAnimating: Bool = false  // 动画状态标记
    
    // 根据 BPM 计算滚动速度
    private var scrollDuration: Double {
        guard speed > 0 else { return 2.0 }
        // BPM 越高，duration 越短，移动越快
        // 60 BPM → 3.0秒
        // 120 BPM → 1.5秒
        // 180 BPM → 1.0秒
        return max(0.5, 3.0 - (speed / 120.0) * 1.5)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 跑道线条（横向）
                ForEach(0..<15, id: \.self) { index in
                    // 虚线样式的跑道线
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 80, height: 4)
                        .position(
                            x: CGFloat(index) * 100 + scrollOffset,
                            y: geometry.size.height * 0.65 // 在场景下方
                        )
                }
                
                // 上下边界线（可选）
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 2)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.55)
                
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 2)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.75)
            }
            .clipped()
            // 监听弹奏状态变化
            .onChange(of: isActive) { _, newValue in
                print("🛤️ MovingTrackView.isActive: \(newValue), speed: \(String(format: "%.1f", speed))")
                
                if newValue {
                    startScrolling()
                } else {
                    stopScrolling()
                }
            }
            // 监听速度变化（弹奏中速度变化时重启动画）
            .onChange(of: speed) { oldValue, newValue in
                print("🏃 MovingTrackView.speed: \(String(format: "%.1f", oldValue)) → \(String(format: "%.1f", newValue)), isActive: \(isActive)")
                
                if isActive && newValue > 0 {
                    print("   → 重启滚动")
                    restartScrolling()
                }
            }
        }
    }
    
    // 开始滚动
    private func startScrolling() {
        guard !isAnimating, speed > 0 else {
            print("   ⚠️ 跳过滚动：isAnimating=\(isAnimating), speed=\(String(format: "%.1f", speed))")
            return
        }
        
        isAnimating = true
        print("   ✓ 准备启动滚动，时长: \(String(format: "%.2f", scrollDuration))秒，当前offset: \(String(format: "%.1f", scrollOffset))")
        
        // 先彻底停止
        withAnimation(.linear(duration: 0)) {
            // 清理状态
        }
        
        // 延迟启动（关键！）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard self.speed > 0 else {
                print("   ⚠️ 延迟后speed=0，取消启动")
                self.isAnimating = false
                return
            }
            
            print("   → 延迟后启动滚动，speed: \(String(format: "%.1f", self.speed))")
            let duration = self.scrollDuration
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                self.scrollOffset = -100
            }
            print("   ✓ 滚动已启动！")
        }
    }
    
    // 停止滚动
    private func stopScrolling() {
        print("   ✓ 停止滚动")
        isAnimating = false
        
        // 停止动画 - 明确移除动画
        withAnimation(.linear(duration: 0)) {
            // 移除 repeatForever 动画
        }
    }
    
    // 重启滚动（速度变化时）
    private func restartScrolling() {
        print("   🔄 准备重启滚动")
        
        // 先完全停止
        isAnimating = false
        withAnimation(.linear(duration: 0)) {
            // 移除旧动画
        }
        
        // 短暂延迟后重新开始
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.startScrolling()
        }
    }
}

// MARK: - Data Badge（数据徽章组件）
struct DataBadge: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
            
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.4))
        .clipShape(Capsule())
    }
}

// MARK: - Compact Runner View（紧凑版跑步小人）
struct CompactRunnerView: View {
    let animationPhase: Double
    let isRunning: Bool
    
    private var leftArmAngle: Angle {
        .degrees(sin(animationPhase * .pi * 2) * 30)
    }
    
    private var rightArmAngle: Angle {
        .degrees(-sin(animationPhase * .pi * 2) * 30)
    }
    
    private var leftLegAngle: Angle {
        .degrees(-sin(animationPhase * .pi * 2) * 40)
    }
    
    private var rightLegAngle: Angle {
        .degrees(sin(animationPhase * .pi * 2) * 40)
    }
    
    private var bodyTilt: Angle {
        .degrees(isRunning ? 5 : 0)
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 头部
                Circle()
                    .fill(Color.orange.gradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 4, height: 4)
                            Circle()
                                .fill(Color.black)
                                .frame(width: 4, height: 4)
                        }
                        .offset(y: -2)
                    }
                
                // 躯干
                Capsule()
                    .fill(Color.blue.gradient)
                    .frame(width: 20, height: 40)
                
                // 腿部
                ZStack {
                    Capsule()
                        .fill(Color.green.gradient)
                        .frame(width: 10, height: 35)
                        .offset(y: 17.5)
                        .rotationEffect(leftLegAngle, anchor: .top)
                        .offset(x: -5)
                    
                    Capsule()
                        .fill(Color.green.gradient)
                        .frame(width: 10, height: 35)
                        .offset(y: 17.5)
                        .rotationEffect(rightLegAngle, anchor: .top)
                        .offset(x: 5)
                }
                .frame(height: 35)
            }
            .overlay(alignment: .top) {
                ZStack {
                    Capsule()
                        .fill(Color.orange.gradient)
                        .frame(width: 8, height: 30)
                        .offset(y: 15)
                        .rotationEffect(leftArmAngle, anchor: .top)
                        .offset(x: -15, y: 30)
                    
                    Capsule()
                        .fill(Color.orange.gradient)
                        .frame(width: 8, height: 30)
                        .offset(y: 15)
                        .rotationEffect(rightArmAngle, anchor: .top)
                        .offset(x: 15, y: 30)
                }
            }
            .rotationEffect(bodyTilt)
            
            // 阴影
            Ellipse()
                .fill(Color.black.opacity(0.2))
                .frame(width: 50, height: 12)
                .offset(y: 65)
                .scaleEffect(x: isRunning ? 1.1 : 1.0)
        }
        .animation(.easeInOut(duration: 0.1), value: isRunning)
    }
}


// MARK: - Practice Settings Sheet（练习设置对话框）
struct PracticeSettingsSheet: View {
    @Binding var targetBPM: Double
    @Binding var targetDuration: TimeInterval
    @Binding var metronomeEnabled: Bool  // ✨ 新增：节拍器开关
    @Binding var metronomeSoundType: MetronomeSoundType  // ✨ 新增：节拍器音色
    @Environment(\.dismiss) private var dismiss
    
    // 本地临时状态
    @State private var localBPM: Double
    @State private var localDuration: TimeInterval
    @State private var localMetronomeEnabled: Bool  // ✨ 新增
    @State private var localSoundType: MetronomeSoundType  // ✨ 新增
    
    // 预设时长选项
    private let durationPresets: [(String, TimeInterval)] = [
        (L("1分钟"), 60),
        (L("3分钟"), 180),
        (L("5分钟"), 300),
        (L("10分钟"), 600),
        (L("15分钟"), 900),
        (L("30分钟"), 1800)
    ]
    
    // 格式化时长显示
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes == 0 {
            return L("30秒")
        } else if minutes < 60 {
            return "\(minutes)" + L("分钟")
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours)" + L("小时")
            } else {
                return "\(hours)" + L("小时") + "\(mins)" + L("分钟")
            }
        }
    }
    
    init(targetBPM: Binding<Double>, targetDuration: Binding<TimeInterval>, metronomeEnabled: Binding<Bool>, metronomeSoundType: Binding<MetronomeSoundType>) {
        _targetBPM = targetBPM
        _targetDuration = targetDuration
        _metronomeEnabled = metronomeEnabled
        _metronomeSoundType = metronomeSoundType
        _localBPM = State(initialValue: targetBPM.wrappedValue)
        _localDuration = State(initialValue: targetDuration.wrappedValue)
        _localMetronomeEnabled = State(initialValue: metronomeEnabled.wrappedValue)
        _localSoundType = State(initialValue: metronomeSoundType.wrappedValue)
    }
    
    var body: some View {
        NavigationView {
            Form {
                // BPM 设置区
                Section {
                    VStack(spacing: 16) {
                        // BPM 数值显示
                        HStack {
                            Spacer()
                            Text("\(Int(localBPM))")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.blue)
                            Text("BPM")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        
                        // 调整按钮
                        HStack(spacing: 12) {
                            Button(action: {
                                localBPM = max(Double(MetronomeManager.minimumBPM), localBPM - 10)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            Button(action: {
                                localBPM = min(Double(MetronomeManager.maximumBPM), localBPM + 10)
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // 滑块
                        Slider(value: $localBPM, in: Double(MetronomeManager.minimumBPM)...Double(MetronomeManager.maximumBPM), step: 1)
                            .tint(.blue)
                        
                        // 提示文字
                        Text("\(L("范围")): \(MetronomeManager.minimumBPM)-\(MetronomeManager.maximumBPM) BPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Label(L("目标速度"), systemImage: "target")
                }
                
                // 时长设置区
                Section {
                    // 时长数值显示
                    VStack(spacing: 16) {
                        HStack {
                            Spacer()
                            Text(formatDuration(localDuration))
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                            Spacer()
                        }
                        
                        // 滑块
                        Slider(value: $localDuration, in: 30...3600, step: 30)
                            .tint(.orange)
                        
                        HStack {
                            Text(L("30秒"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(L("60分钟"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    
                    // 快捷选择按钮
                    VStack(spacing: 8) {
                        Text(L("快捷选择"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            ForEach(durationPresets, id: \.0) { name, duration in
                                Button(action: {
                                    localDuration = duration
                                }) {
                                    Text(name)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            isSelected(duration) ? Color.blue : Color(.systemGray5)
                                        )
                                        .foregroundStyle(
                                            isSelected(duration) ? .white : .primary
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Label(L("训练时长"), systemImage: "timer")
                }
                
                // ✨ 节拍器设置区（新增）
                Section {
                    // 节拍器开关
                    Toggle(isOn: $localMetronomeEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "metronome.fill")
                                .foregroundStyle(localMetronomeEnabled ? .green : .secondary)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("启用节拍器"))
                                    .font(.body)
                                if localMetronomeEnabled {
                                    Text(L("将在练习开始时自动播放"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .tint(.green)
                    
                    // 音色选择（只在启用时显示）
                    if localMetronomeEnabled {
                        Picker(L("节拍器音色"), selection: $localSoundType) {
                            ForEach(MetronomeSoundType.allCases) { type in
                                HStack(spacing: 8) {
                                    Image(systemName: type.icon)
                                    Text(type.displayName)
                                }
                                .tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Label(L("节拍器"), systemImage: "metronome")
                } footer: {
                    if localMetronomeEnabled {
                        Text(L("节拍器将使用与练习相同的速度（") + "\(Int(localBPM)) BPM" + L("）"))
                    } else {
                        Text(L("开启节拍器可帮助您保持稳定的练习节奏"))
                    }
                }
            }
            .navigationTitle(L("练习设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("确认")) {
                        targetBPM = localBPM
                        targetDuration = localDuration
                        metronomeEnabled = localMetronomeEnabled  // ✨ 保存节拍器开关
                        metronomeSoundType = localSoundType  // ✨ 保存节拍器音色
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func isSelected(_ duration: TimeInterval) -> Bool {
        return abs(localDuration - duration) < 1
    }
}


#Preview {
    NavigationStack {
        RunningPracticeView()
    }
}

