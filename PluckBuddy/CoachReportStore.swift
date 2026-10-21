//
//  CoachReportStore.swift
//  PluckBuddy
//
//  评价报告历史持久化：以 JSON 存放于 Application Support，完全离线，不落盘麦克风音频。
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class CoachReportStore: ObservableObject {
    static let shared = CoachReportStore()

    @Published private(set) var reports: [CoachReport] = []

    private let fileURL: URL
    private let maxReports = 200

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = dir.appendingPathComponent("coach_reports.json")
        load()
    }

    /// 新增一份报告（置顶），并落盘。
    func append(_ report: CoachReport) {
        reports.insert(report, at: 0)
        if reports.count > maxReports {
            reports = Array(reports.prefix(maxReports))
        }
        save()
    }

    /// 已「达标」（综合分 ≥ 70）的曲目集合，用于乐曲维度成就。
    var qualifiedPieces: Set<PracticePiece> {
        Set(reports.filter { $0.overallScore >= 70 }.map { $0.piece })
    }

    /// 达标曲目数量（去重）：同一曲目多次达标只计一次，
    /// 用于「演奏家」分级成就（初/进阶/大师分别为 1 / 3 / 5 首）。
    var qualifiedPieceCount: Int { qualifiedPieces.count }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoded = try? JSONDecoder().decode([CoachReport].self, from: data)
        reports = decoded ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
