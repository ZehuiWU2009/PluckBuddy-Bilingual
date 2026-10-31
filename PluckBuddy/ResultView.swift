//
//  ResultView.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/7/15.
//

import SwiftUI
import Charts
import CoreData

struct ResultView: View {
    @StateObject private var dataManager = PracticeDataManager.shared
    @State private var selectedTab: StatTab = .overview
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PracticeSession.startTime, ascending: false)],
        animation: .default
    )
    private var sessions: FetchedResults<PracticeSession>
    
    enum StatTab: String, CaseIterable {
        case overview = "总览"
        case history = "历史"
        case achievements = "成就"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标签切换
            Picker(L("统计类型"), selection: $selectedTab) {
                ForEach(StatTab.allCases, id: \.self) { tab in
                    Text(L(tab.rawValue)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // 内容区域
            ScrollView {
                switch selectedTab {
                case .overview:
                    OverviewSection(dataManager: dataManager)
                case .history:
                    HistorySection(sessions: Array(sessions))
                case .achievements:
                    AchievementsSection(dataManager: dataManager)
                }
            }
        }
        .navigationTitle(L("我的成绩"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            dataManager.updateStatistics()
        }
    }
}

// MARK: - Overview Section
struct OverviewSection: View {
    @ObservedObject var dataManager: PracticeDataManager
    @StateObject private var coachStore = CoachReportStore.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // 总览卡片
            HStack(spacing: 16) {
                StatCard(
                    title: L("总练习"),
                    value: "\(dataManager.totalSessions)",
                    unit: L("次"),
                    icon: "list.bullet",
                    color: .blue
                )
                
                StatCard(
                    title: L("总时长"),
                    value: formatDuration(dataManager.totalDuration),
                    unit: "",
                    icon: "clock",
                    color: .green
                )
            }
            .padding(.horizontal)
            
            HStack(spacing: 16) {
                StatCard(
                    title: L("总得分"),
                    value: "\(dataManager.totalScore)",
                    unit: L("分"),
                    icon: "star.fill",
                    color: .orange
                )
                
                StatCard(
                    title: L("连续天数"),
                    value: "\(dataManager.currentStreak)",
                    unit: L("天"),
                    icon: "flame.fill",
                    color: .red
                )
            }
            .padding(.horizontal)
            
            // 7 天趋势图
            VStack(alignment: .leading, spacing: 12) {
                Text(L("最近 7 天练习"))
                    .font(.headline)
                    .padding(.horizontal)
                
                if #available(iOS 16.0, *) {
                    DailyPracticeChart(stats: dataManager.getDailyStats())
                        .frame(height: 200)
                        .padding()
                } else {
                    Text(L("需要 iOS 16+ 才能显示图表"))
                        .foregroundStyle(.secondary)
                        .frame(height: 200)
                }
            }
            .padding(.vertical)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8)
            .padding(.horizontal)

            // 智能指法教练 · 曲目维度统计
            PieceDimensionSection(reports: coachStore.reports)
        }
        .padding(.top)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        } else {
            return "\(minutes)\(L("分钟"))"
        }
    }
}

// MARK: - History Section
struct HistorySection: View {
    let sessions: [PracticeSession]
    @StateObject private var store = CoachReportStore.shared
    @State private var selectedReport: CoachReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if sessions.isEmpty && store.reports.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text(L("还没有记录"))
                        .foregroundStyle(.secondary)
                    Text(L("开始练习或生成评价报告吧！"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else {
                if !store.reports.isEmpty {
                    Text(L("评价报告"))
                        .font(.headline)
                        .padding(.top, 4)
                    ForEach(store.reports) { report in
                        CoachReportHistoryRow(report: report)
                            .onTapGesture { selectedReport = report }
                    }
                }

                if !sessions.isEmpty {
                    Text(L("游戏得分"))
                        .font(.headline)
                        .padding(.top, 4)
                    ForEach(sessions, id: \.id) { session in
                        SessionRow(session: session)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top)
        .sheet(item: $selectedReport) { report in
            CoachReportView(report: report)
        }
    }
}

// MARK: - 评价报告历史行
struct CoachReportHistoryRow: View {
    let report: CoachReport

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundStyle(report.piece.theme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(report.piece.displayName)
                    .font(.headline)
                Text(report.dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f", report.overallScore) + " " + L("分"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
                Text(L("查看"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4)
    }
}

// MARK: - Achievements Section
struct AchievementsSection: View {
    @ObservedObject var dataManager: PracticeDataManager
    
    var body: some View {
        VStack(spacing: 16) {
            // 成就列表
            AchievementCard(
                title: L("初学者"),
                description: L("完成第一次练习"),
                icon: "🎯",
                isUnlocked: dataManager.totalSessions >= 1,
                progress: min(1.0, Double(dataManager.totalSessions))
            )
            
            AchievementCard(
                title: L("勤奋练习"),
                description: L("累计练习 10 次"),
                icon: "💪",
                isUnlocked: dataManager.totalSessions >= 10,
                progress: min(1.0, Double(dataManager.totalSessions) / 10.0)
            )
            
            AchievementCard(
                title: L("坚持不懈"),
                description: L("连续练习 7 天"),
                icon: "🔥",
                isUnlocked: dataManager.currentStreak >= 7,
                progress: min(1.0, Double(dataManager.currentStreak) / 7.0)
            )
            
            AchievementCard(
                title: L("时间大师"),
                description: L("累计练习 1 小时"),
                icon: "⏰",
                isUnlocked: dataManager.totalDuration >= 3600,
                progress: min(1.0, dataManager.totalDuration / 3600.0)
            )
            
            AchievementCard(
                title: L("高分选手"),
                description: L("累计得分达到 1000"),
                icon: "⭐",
                isUnlocked: dataManager.totalScore >= 1000,
                progress: min(1.0, Double(dataManager.totalScore) / 1000.0)
            )
            
            AchievementCard(
                title: L("全能选手"),
                description: L("尝试所有练习模式"),
                icon: "🏆",
                isUnlocked: checkAllModes(),
                progress: Double(getUniqueModes()) / 4.0
            )

            // 乐曲维度成就（演奏家分级）：按「达标曲目数」去重（同一曲目不重复累计），初 / 进阶 / 大师三档
            let qualified = CoachReportStore.shared.qualifiedPieceCount
            AchievementCard(
                title: L("初级演奏家"),
                description: L("完成 1 首乐曲的演奏并达标"),
                icon: "🎻",
                isUnlocked: qualified >= 1,
                progress: min(1.0, Double(qualified) / 1.0))
            AchievementCard(
                title: L("进阶演奏家"),
                description: L("完成 5 首乐曲的演奏并达标"),
                icon: "🎼",
                isUnlocked: qualified >= 5,
                progress: min(1.0, Double(qualified) / 5.0))
            AchievementCard(
                title: L("演奏大师"),
                description: L("完成 10 首乐曲的演奏并达标"),
                icon: "👑",
                isUnlocked: qualified >= 10,
                progress: min(1.0, Double(qualified) / 10.0))
        }
        .padding()
    }
    
    private func checkAllModes() -> Bool {
        return getUniqueModes() >= 4
    }
    
    private func getUniqueModes() -> Int {
        let sessions = dataManager.fetchAllSessions()
        let types = Set(sessions.map { $0.sessionType })
        return types.count
    }
}

// MARK: - Components

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title.bold())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4)
    }
}

struct SessionRow: View {
    let session: PracticeSession
    
    var body: some View {
        HStack(spacing: 12) {
            Text(session.icon)
                .font(.title)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(session.typeName)
                    .font(.headline)
                Text(session.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(session.score) " + L("分"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
                Text(session.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4)
    }
}

struct AchievementCard: View {
    let title: String
    let description: String
    let icon: String
    let isUnlocked: Bool
    let progress: Double
    
    var body: some View {
        HStack(spacing: 16) {
            Text(icon)
                .font(.system(size: 40))
                .grayscale(isUnlocked ? 0 : 1)
                .opacity(isUnlocked ? 1 : 0.3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isUnlocked ? .primary : .secondary)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if !isUnlocked {
                    ProgressView(value: progress)
                        .tint(.blue)
                }
            }
            
            Spacer()
            
            if isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4)
    }
}

// MARK: - Daily Practice Chart
@available(iOS 16.0, *)
struct DailyPracticeChart: View {
    let stats: [DailyStats]
    
    var body: some View {
        Chart {
            ForEach(stats) { stat in
                BarMark(
                    x: .value(L("日期"), stat.weekday),
                    y: .value(L("时长"), stat.totalDuration / 60)
                )
                .foregroundStyle(.blue.gradient)
                .annotation(position: .top) {
                    if stat.sessionCount > 0 {
                        Text("\(Int(stat.totalDuration / 60))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text("\(Int(minutes))" + L("分"))
                            .font(.caption2)
                    }
                }
            }
        }
    }
}

// MARK: - 智能指法教练 · 曲目维度统计

private struct PieceStat {
    let piece: PracticePiece
    let count: Int
    let best: Double
    let avg: Double
    let qualified: Bool
}

struct PieceDimensionSection: View {
    let reports: [CoachReport]

    private var grouped: [PieceStat] {
        Dictionary(grouping: reports, by: { $0.piece }).map { (piece, rs) in
            let scores = rs.map { $0.overallScore }
            let best = scores.max() ?? 0
            let avg = scores.reduce(0, +) / Double(scores.count)
            return PieceStat(piece: piece, count: rs.count, best: best, avg: avg, qualified: best >= 70)
        }
        .sorted { $0.best > $1.best }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "music.note.list")
                    .foregroundStyle(.purple)
                Text(L("智能指法教练 · 曲目维度"))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            if reports.isEmpty {
                Text(L("还没有智能指法教练的评价报告"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            } else {
                HStack(spacing: 12) {
                    PieceStatPill(title: L("评价报告"), value: "\(reports.count)")
                    PieceStatPill(title: L("涉及曲目"), value: "\(grouped.count)")
                    PieceStatPill(title: L("达标曲目"), value: "\(grouped.filter { $0.qualified }.count)")
                }
                .padding(.horizontal)

                VStack(spacing: 12) {
                    ForEach(grouped, id: \.piece) { item in
                        PieceStatRow(item: item)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8)
        .padding(.horizontal)
    }
}

private struct PieceStatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemFill))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PieceStatRow: View {
    let item: PieceStat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "music.note")
                    .foregroundStyle(item.piece.theme.accent)
                Text(item.piece.displayName)
                    .font(.subheadline.bold())
                Spacer()
                if item.qualified {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Text("\(Int(item.best)) " + L("分"))
                    .font(.subheadline.bold())
                    .foregroundStyle(scoreColor(item.best))
            }

            Text(L("练习") + " \(item.count) " + L("次"))
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemFill))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(scoreColor(item.best))
                        .frame(width: geo.size.width * CGFloat(item.best / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func scoreColor(_ s: Double) -> Color {
        if s >= 90 { return .green }
        if s >= 70 { return .blue }
        if s >= 60 { return .orange }
        return .red
    }
}

#Preview {
    NavigationStack {
        ResultView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
