//
//  TechniqueCoachView.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/7/29.
//

import SwiftUI
import Combine

/// 智能指法教练主界面
struct TechniqueCoachView: View {
    @StateObject private var viewModel = TechniqueCoachViewModel()
    
    /// 界面固定展示的技法：识别到新技法时更新，识别丢失时沿用上一次。
    /// 直接绑定 viewModel.detectedTechnique 会在「识别到」与「未识别」之间抖动，
    /// 导致下方要求条与评估面板整块闪进闪出。
    @State private var displayTechnique: TechniqueType = .unknown
    /// 固定展示的评估结果：同样沿用上一次有效值，避免评分数字闪烁
    @State private var displayEvaluation: PostureEvaluation?
    /// 本次会话是否“听到过琵琶声”的锁存：第一个音出现即置 true，之后不再因
    /// 音符间隙门控短暂判非琵琶声而回落。true 之前四维评分固定保持全黑占位。
    @State private var hasHeardPipa = false
    
    var body: some View {
        ZStack {
            // 深色背景
            Color.black.ignoresSafeArea()
            
        VStack(spacing: 16) {
            // 摄像头预览区域
            cameraPreviewSection

                // 合并的检测结果和评估面板（常驻显示）
                // 核心要求已压缩为面板顶部一行，不再单独占一块卡片
                combinedEvaluationPanel
                
                Spacer()
                
                // 控制按钮
                controlButton
            }
        }
        .onChange(of: viewModel.detectedTechnique) { _, newValue in
            // 只在识别到明确技法时切换界面，未识别时保持当前显示
            guard newValue != .unknown, newValue != displayTechnique else { return }
            displayTechnique = newValue
            // 注意：不要在这里清空 displayEvaluation。音频门控在音符间隙会短暂判非琵琶声，
            // 且技法常在弹挑/轮指间抖动，若在此清空，四维评分面板会瞬间全黑闪一下。
            // 评分由下面的 onChange 与 hasHeardPipa 锁存自然管理，这里只管技法标签。
        }
        .onChange(of: viewModel.currentEvaluation) { _, newEval in
            // 听到第一个音（currentEvaluation 首次非 nil）即启动四维评分并锁存 hasHeardPipa；
            // 此后音符间隙让门控短暂判非琵琶声（newEval 变 nil）时，沿用上一次评分不闪黑。
            // hasHeardPipa 为 false 之前，四维面板固定保持全黑占位（“没听到琵琶声就全黑”）。
            if let eval = newEval {
                hasHeardPipa = true
                displayEvaluation = eval
            }
        }
        .onChange(of: viewModel.isAnalyzing) { _, analyzing in
            // 会话结束（停止分析）时复位锁存，下次重新开始、听到第一个音之前保持全黑。
            if !analyzing {
                hasHeardPipa = false
                displayEvaluation = nil
            }
        }
        .sheet(item: $viewModel.report) { report in
            CoachReportView(report: report)
        }
        .alert("提示", isPresented: Binding(
            get: { viewModel.reportBlockedReason != nil },
            set: { if !$0 { viewModel.reportBlockedReason = nil } }
        )) {
            Button(L("知道了"), role: .cancel) {
                viewModel.reportBlockedReason = nil
            }
        } message: {
            Text(viewModel.reportBlockedReason ?? "")
        }
        .toolbar {
            // 右上角：...⭕️ 图标菜单选择曲目（不显示曲目文字）
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(PracticePiece.allCases) { piece in
                        Button {
                            viewModel.selectedPiece = piece
                        } label: {
                            if viewModel.selectedPiece == piece {
                                Label(piece.displayName, systemImage: "checkmark")
                            } else {
                                Text(piece.displayName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .disabled(viewModel.isAnalyzing)
            }

            // 中间：选中曲目名（取代导航标题），亮色显示，不用黑色
            ToolbarItem(placement: .principal) {
                Text(viewModel.selectedPiece.displayName)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
    }
    
    // MARK: - 摄像头预览区域
    
    private var cameraPreviewSection: some View {
        ZStack {
            if viewModel.isAnalyzing, let previewLayer = viewModel.videoCapture?.previewLayer {
                // 真实摄像头预览
                CameraPreviewView(previewLayer: previewLayer)
                    .frame(height: 470)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                
                // ✨ 手部骨骼覆盖层
                if let skeletonImage = viewModel.skeletonOverlayImage {
                    Image(uiImage: skeletonImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 470)
                        .allowsHitTesting(false)  // 不拦截触摸事件
                }
            } else {
                // 占位视图
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 470)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.white.opacity(0.5))
                            
                            if !viewModel.isAnalyzing {
                                Text(L("点击开始分析按钮启动摄像头"))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.85))
                            } else if viewModel.handPose == nil {
                                Text(L("等待检测手部..."))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.85))
                            } else {
                                Text(L("✅ 手部已检测"))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.green)
                            }
                        }
                    )
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.isAnalyzing {
                HStack(spacing: 10) {
                    handBadge(L("左手"), detected: viewModel.leftHandDetected, color: .teal)
                    handBadge(L("右手"), detected: viewModel.rightHandDetected, color: .pink, sub: L("指法分析"))
                }
                .padding(6)
            }
        }
        .padding(.horizontal)
    }

    /// 双手识别状态小徽标
    private func handBadge(_ title: String, detected: Bool, color: Color, sub: String? = nil) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(detected ? color : .white.opacity(0.4))
            if let sub {
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundStyle(detected ? color.opacity(0.85) : .white.opacity(0.3))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(detected ? color.opacity(0.18) : Color.white.opacity(0.08))
                .overlay(Capsule().stroke(detected ? color : .white.opacity(0.2), lineWidth: 1))
        )
    }
    
    private var combinedEvaluationPanel: some View {
        VStack(spacing: 0) {
            // 顶部：单行轮播——选定乐曲时轮播乐曲文案，「指法基本功」轮播技法要求（32pt，不扩大）
            RequirementStripView(technique: displayTechnique, piece: viewModel.selectedPiece)
            
            // 分隔线
            Divider()
            
            // 上半部分：检测信息（左） + 建议（右）
            HStack(spacing: 0) {
                // 左侧：检测信息
                HStack(spacing: 12) {
                    // 技法图标
                    Image(systemName: displayTechnique.icon)
                        .font(.system(size: 26))
                        .foregroundStyle(displayTechnique.color)
                        .frame(width: 40, height: 40)
                        .background(displayTechnique.color.opacity(0.2))
                        .clipShape(Circle())
                    
                    // 检测信息三行：技法名 / 评分 / 状态
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(L("检测到:"))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                            Text(displayTechnique.displayName)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(displayTechnique.color)
                        }
                        
                        if let evaluation = displayEvaluation {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                Text("\(Int(evaluation.overallScore))/100")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(scoreColor(evaluation.overallScore))
                            }
                        }
                        
                        Text(viewModel.statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                
                // 分隔线
                Divider()
                    .padding(.vertical, 8)
                
                // 右侧：改进建议（可滚动显示2条）
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text(L("改进建议"))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    
                    if let evaluation = displayEvaluation {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(evaluation.suggestions.prefix(5), id: \.self) { suggestion in
                                    Text("• \(suggestion)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.82))
                                        .lineLimit(2)
                                }
                            }
                        }
                        .frame(height: 36)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
            }
            .frame(height: 78)
            
            // 分隔线
            Divider()
            
            // 下半部分：固定的4个评估维度（2×2）
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { index in
                        if let aspect = getStandardAspect(at: index) {
                            FixedAspectView(aspect: aspect)
                        } else {
                            PlaceholderAspectView()
                        }
                    }
                }
                
                HStack(spacing: 6) {
                    ForEach(2..<4, id: \.self) { index in
                        if let aspect = getStandardAspect(at: index) {
                            FixedAspectView(aspect: aspect)
                        } else {
                            PlaceholderAspectView()
                        }
                    }
                }
            }
            .padding(10)
            .frame(height: 106)
        }
        .frame(height: 230)  // 44(要求) + 1 + 78(上半) + 1 + 106(下半)
        .modifier(CoachPanelBackground())
        .padding(.horizontal)
    }
    
    // MARK: - 获取标准评估维度
    
    /// 获取通用的4个固定评估维度
    private func getStandardAspect(at index: Int) -> EvaluationAspect? {
        // 没听到过琵琶声（hasHeardPipa 为 false）时保持全黑占位；
        // 听到第一个音之后才出值，之后音符间隙沿用上一帧、不再全黑。
        guard hasHeardPipa, let evaluation = displayEvaluation else {
            return nil
        }
        
        // 定义通用的4个固定维度
        let standardCategories: [EvaluationAspect.Category] = [
            .handShape,      // 手型
            .tigerMouth,     // 虎口角度
            .rhythm,         // 节奏稳定性
            .wristPosition   // 手腕位置
        ]
        
        guard index < standardCategories.count else {
            return nil
        }
        
        let category = standardCategories[index]
        
        // 从评估结果中查找对应的维度
        if let aspect = evaluation.aspects.first(where: { $0.category == category }) {
            return aspect
        }
        
        // 如果没有找到，返回默认值
        return EvaluationAspect(
            category: category,
            score: 0,
            description: L("暂无数据")
        )
    }
    
    // MARK: - 检测结果卡片
    
    private var detectionResultCard: some View {
        HStack(spacing: 16) {
            // 技法图标 - 稍小
            Image(systemName: viewModel.detectedTechnique.icon)
                .font(.system(size: 32))
                .foregroundStyle(viewModel.detectedTechnique.color)
                .frame(width: 50, height: 50)
                .background(viewModel.detectedTechnique.color.opacity(0.2))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                // 检测到的技法
                HStack(spacing: 4) {
                    Text(L("检测:"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text(viewModel.detectedTechnique.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(viewModel.detectedTechnique.color)
                }
                
                // 评分
                if let evaluation = viewModel.currentEvaluation {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        
                        Text("\(Int(evaluation.overallScore))/100")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(scoreColor(evaluation.overallScore))
                    }
                }
                
                // 状态消息
                Text(viewModel.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
    
    // MARK: - 详细评估面板
    
    private func evaluationDetailSection(evaluation: PostureEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                Text(L("详细评估"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            // 各维度评分 - 压缩为 2 行，每行 2 个
            if !evaluation.aspects.isEmpty {
                VStack(spacing: 6) {
                    // 将评分点分成两行
                    let aspectPairs = stride(from: 0, to: evaluation.aspects.count, by: 2).map { index -> [EvaluationAspect] in
                        let endIndex = min(index + 2, evaluation.aspects.count)
                        return Array(evaluation.aspects[index..<endIndex])
                    }
                    
                    ForEach(aspectPairs.indices, id: \.self) { pairIndex in
                        HStack(spacing: 8) {
                            ForEach(aspectPairs[pairIndex].indices, id: \.self) { index in
                                CompactAspectView(aspect: aspectPairs[pairIndex][index])
                            }
                        }
                    }
                }
            }
            
            // 改进建议 - 更紧凑
            if !evaluation.suggestions.isEmpty {
                Divider()
                    .padding(.vertical, 2)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption2)
                        Text(L("建议"))
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    // 只显示前 2 条建议，避免过长
                    ForEach(evaluation.suggestions.prefix(2), id: \.self) { suggestion in
                        Text("• \(suggestion)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - 控制按钮
    
    private var controlButton: some View {
        Button(action: toggleAnalysis) {
            HStack(spacing: 12) {
                Image(systemName: viewModel.isAnalyzing ? "stop.fill" : "play.fill")
                    .font(.title3)
                
                Text(viewModel.isAnalyzing ? L("停止分析") : L("开始分析"))
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                viewModel.isAnalyzing
                    ? Color.red
                    : Color.blue
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal)
        .padding(.bottom, 116)
    }
    
    // MARK: - Actions
    
    private func toggleAnalysis() {
        if viewModel.isAnalyzing {
            viewModel.stopAnalysis()
        } else {
            Task {
                await viewModel.startAnalysis()
            }
        }
    }
    
    // MARK: - Helper
    
    private func scoreColor(_ score: Double) -> Color {
        if score >= 90 {
            return .green
        } else if score >= 80 {
            return .blue
        } else if score >= 70 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - 固定评估维度视图

struct FixedAspectView: View {
    let aspect: EvaluationAspect
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 分类名称和分数
            HStack(spacing: 4) {
                Text(aspect.category.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                
                Spacer()
                
                Text("\(Int(aspect.score))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(scoreColor)
            }
            
            // 紧凑型进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(scoreColor)
                        .frame(
                            width: geometry.size.width * (aspect.score / 100),
                            height: 4
                        )
                }
            }
            .frame(height: 4)
        }
        .padding(8)
        .frame(height: 40)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private var scoreColor: Color {
        if aspect.score >= 80 {
            return .green
        } else if aspect.score >= 60 {
            return .orange
        } else if aspect.score > 0 {
            return .red
        } else {
            return .gray
        }
    }
}

// MARK: - 占位评估维度视图

struct PlaceholderAspectView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("---")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("--")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.white.opacity(0.12))
                .frame(height: 4)
        }
        .padding(8)
        .frame(height: 40)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 评估维度行

struct AspectRow: View {
    let aspect: EvaluationAspect
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(aspect.category.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(Int(aspect.score))/100")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(scoreColor)
            }
            
            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                    
                    // 进度
                    RoundedRectangle(cornerRadius: 2)
                        .fill(scoreColor)
                        .frame(
                            width: geometry.size.width * (aspect.score / 100),
                            height: 6
                        )
                }
            }
            .frame(height: 6)
            
            // 描述
            Text(aspect.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    
    private var scoreColor: Color {
        if aspect.score >= 80 {
            return .green
        } else if aspect.score >= 60 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - 紧凑型评分视图

struct CompactAspectView: View {
    let aspect: EvaluationAspect
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 分类和分数
            HStack(spacing: 4) {
                Text(aspect.category.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(Int(aspect.score))")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(scoreColor)
            }
            
            // 紧凑型进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(scoreColor)
                        .frame(
                            width: geometry.size.width * (aspect.score / 100),
                            height: 4
                        )
                }
            }
            .frame(height: 4)
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var scoreColor: Color {
        if aspect.score >= 80 {
            return .green
        } else if aspect.score >= 60 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - 核心要求轮播视图

/// 单行轮播：选定乐曲时逐条切换该曲的背景 / 历史 / 情感文案（无标题、单行不扩大），
/// 选「指法基本功」时轮播当前技法的练习要求。
/// 原先是横向跑马灯（文字从屏幕右侧外滚进来，50 pt/s，七八秒后才露头，且技法一切换就重置），
/// 后来改成独立卡片 + 逐条淡入切换，仍占 86pt 高。这里压缩成 32pt 单行走条，并入下方面板顶部。
struct RequirementStripView: View {
    let technique: TechniqueType
    let piece: PracticePiece

    @State private var index = 0
    @State private var tick = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    /// 乐曲模式：该曲的知识提示逐条轮播；基本功模式：技法练习要求。
    private var items: [String] {
        if !piece.hints.isEmpty {
            return piece.hints
        }
        return TechniqueRequirementsManager.getRequirements(for: technique)
    }

    private var isPieceMode: Bool { !piece.hints.isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            if isPieceMode {
                Image(systemName: "music.note")
                    .font(.system(size: 15))
                    .foregroundStyle(piece.theme.accent)
            } else {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.yellow)
            }

            Text(items.isEmpty ? L("暂无要求") : items[safeIndex])
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(safeIndex)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: safeIndex)

            if items.count > 1 {
                Text("\(safeIndex + 1)/\(items.count)")
                    .font(.system(size: 13))
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .onReceive(tick) { _ in
            guard items.count > 1 else { return }
            index = (index + 1) % items.count
        }
        .onChange(of: technique) { _, _ in
            index = 0
        }
        .onChange(of: piece) { _, _ in
            index = 0
        }
    }

    /// 防止切换后条目数变化导致下标越界
    private var safeIndex: Int {
        guard !items.isEmpty else { return 0 }
        return min(index, items.count - 1)
    }
}

// MARK: - 面板背景样式

/// 半透明黑底 + 细描边：摄像头画面偏亮时也能保证文字对比度
struct CoachPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TechniqueCoachView()
    }
}
