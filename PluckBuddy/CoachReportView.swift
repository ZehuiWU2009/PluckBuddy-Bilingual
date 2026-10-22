//
//  CoachReportView.swift
//  PluckBuddy
//
//  演奏结束后弹出的「分析评价报告」。融合视频手型评估与音频分析，
//  头部以情感把握的一句话替代原「总体评价」，结构为：
//  头部（曲目/时长/综合得分/情感句/背景介绍）→ 四维度得分 → 详细分析 → 错误定位与建议。
//

import SwiftUI

struct CoachReportView: View {
    let report: CoachReport
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var theme: PieceTheme { report.piece.theme }

    private var durationText: String {
        let total = Int(report.duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    dimensionsSection
                    pieceSection
                    detailsSection
                    errorSection
                    suggestionSection

                    Button {
                        dismiss()
                    } label: {
                        Text(L("完成"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(theme.gradient[0])
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(reportBackground.ignoresSafeArea())
            .tint(theme.accent)
            .navigationTitle(L("分析评价报告"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("关闭")) { dismiss() }
                }
            }
        }
    }

    // 色彩只作用于背景与装饰；布局、评分语义色及交互保持原有行为。
    private var reportBackground: some View {
        ZStack {
            Color(.systemBackground)
            LinearGradient(
                colors: theme.gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(colorScheme == .dark ? 0.30 : 0.28)
            RadialGradient(
                colors: [theme.gradient[2].opacity(0.24), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 420
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func cardBackground(highlighted: Bool = false) -> some View {
        ZStack {
            // 实色底确保深浅外观下，背景色不会干扰正文与评分。
            Color(.secondarySystemBackground)
            LinearGradient(
                colors: theme.gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(highlighted ? 0.15 : 0.06)
        }
    }

    @ViewBuilder
    private var headerBackground: some View {
        if let imageName = theme.reportBackgroundImage {
            ZStack {
                Image(imageName)
                    .resizable()
                    .scaledToFill()

                // 双层遮罩同时压低高光和繁复细节；整体调亮以看清背景图。
                Color.black.opacity(theme.imageOverlayOpacity * 0.5)
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.03),
                        Color.black.opacity(0.16),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            cardBackground(highlighted: true)
        }
    }

    // MARK: - 头部：曲目 / 时长 / 综合得分 / 评价

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("练习曲目"))
                        .font(.caption)
                        .foregroundStyle(theme.headerSecondaryForeground)
                    Text(report.piece.displayName)
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(theme.headerForeground)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("演奏时长"))
                        .font(.caption)
                        .foregroundStyle(theme.headerSecondaryForeground)
                    Text(durationText)
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(theme.headerForeground)
                        .monospacedDigit()
                }
            }

            Divider()
                .overlay(theme.headerSecondaryForeground.opacity(0.55))

            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(theme.reportBackgroundImage == nil ? 0 : 0.28))
                    Circle()
                        .stroke(
                            theme.reportBackgroundImage == nil
                                ? scoreColor(report.overallScore).opacity(0.25)
                                : Color.white.opacity(0.30),
                            lineWidth: 8
                        )
                    Circle()
                        .trim(from: 0, to: CGFloat(report.overallScore / 100))
                        .stroke(scoreColor(report.overallScore), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int(report.overallScore))")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(scoreColor(report.overallScore))
                        Text(L("综合得分"))
                            .font(.caption2)
                            .foregroundStyle(theme.headerSecondaryForeground)
                    }
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 6) {
                    Text(report.emotionalComment)
                        .font(.callout)
                        .foregroundStyle(theme.headerForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 按当前曲目资料展示，已保存的报告也能读到更新后的中英文介绍。
            Text(report.piece.introduction)
                .font(.caption)
                .foregroundStyle(theme.headerSecondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(headerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(theme.headerForeground.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: theme.accent.opacity(0.16), radius: 10, y: 4)
    }

    // MARK: - 四维度得分

    private var dimensionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("技术维度得分"))
            VStack(spacing: 8) {
                ForEach(report.dimensions) { dim in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(dim.title)
                                    .font(.subheadline).fontWeight(.semibold)
                                Text("· \(dim.comment)")
                                    .font(.caption)
                                    .foregroundStyle(scoreColor(dim.score))
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(.tertiarySystemFill))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(scoreColor(dim.score))
                                        .frame(width: geo.size.width * CGFloat(dim.score / 100))
                                }
                            }
                            .frame(height: 7)
                        }
                        VStack(spacing: 0) {
                            Text("\(Int(dim.score))")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(scoreColor(dim.score))
                            Text("\(dim.weight)%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 44)
                    }
                }
            }
            .padding(14)
            .background(cardBackground())
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - 乐曲维度（仅指定曲目）

    @ViewBuilder
    private var pieceSection: some View {
        if let dim = report.pieceDimension, let detail = report.pieceDetail {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(L("乐曲维度得分"))
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(dim.title)
                                    .font(.subheadline).fontWeight(.semibold)
                                Text("· \(dim.comment)")
                                    .font(.caption)
                                    .foregroundStyle(scoreColor(dim.score))
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(.tertiarySystemFill))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(scoreColor(dim.score))
                                        .frame(width: geo.size.width * CGFloat(dim.score / 100))
                                }
                            }
                            .frame(height: 7)
                        }
                        VStack(spacing: 0) {
                            Text("\(Int(dim.score))")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(scoreColor(dim.score))
                            Text(L("乐曲"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 44)
                    }
                    ForEach(detail.metrics, id: \.label) { metric in
                        HStack(alignment: .top) {
                            Text(metric.label)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .frame(width: 96, alignment: .leading)
                            Text(metric.value)
                                .font(.caption).fontWeight(.medium)
                                .foregroundStyle(scoreColorFromValue(metric))
                                .frame(width: 92, alignment: .leading)
                                .monospacedDigit()
                            Text(metric.note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(14)
                .background(cardBackground())
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - 详细分析

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("详细分析"))
            ForEach(report.details) { detail in
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.title)
                        .font(.subheadline).fontWeight(.semibold)
                    ForEach(detail.metrics, id: \.label) { metric in
                        HStack(alignment: .top) {
                            Text(metric.label)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .frame(width: 96, alignment: .leading)
                            Text(metric.value)
                                .font(.caption).fontWeight(.medium)
                                .foregroundStyle(scoreColorFromValue(metric))
                                .frame(width: 92, alignment: .leading)
                                .monospacedDigit()
                            Text(metric.note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground())
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - 错误定位

    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("错误定位与建议"))
            ForEach(Array(report.errorPoints.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(point.timeLabel)
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Text(point.issue)
                                .font(.caption).fontWeight(.semibold)
                        }
                        Text(point.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground())
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - 改进建议

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("智能改进建议"))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(report.suggestions.enumerated()), id: \.offset) { idx, text in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(.callout).fontWeight(.bold)
                            .foregroundStyle(theme.accent)
                        Text(text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground())
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - 小标题

    private func sectionTitle(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(theme.accent)
                .font(.caption)
            Text(text)
                .font(.subheadline).fontWeight(.semibold)
        }
    }

    // MARK: - 颜色

    private func scoreColor(_ score: Double) -> Color {
        if score >= 90 { return .green }
        if score >= 80 { return .blue }
        if score >= 70 { return .orange }
        return .red
    }

    /// 详细指标里把「— / 数字 / 文本」统一着色：纯文本用主色，否则按分数色
    private func scoreColorFromValue(_ metric: CoachReport.Metric) -> Color {
        let v = metric.value.trimmingCharacters(in: .whitespaces)
        if v == L("—") { return .secondary }
        if let first = v.first, first.isNumber {
            // 取数值部分粗略判断（百分比/分值越高越好）
            if let num = Double(v.replacingOccurrences(of: "%", with: "")) {
                return scoreColor(num)
            }
        }
        return .primary
    }
}
