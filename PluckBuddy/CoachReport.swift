//
//  CoachReport.swift
//  PluckBuddy
//
//  智能指法教练的「分析评价报告」数据模型与端侧分析器。
//  报告融合两种真实评价信号：
//   1) 视频手型评估（智能指法教练正在使用的 Vision 21 关键点 + 虎口角度，见 TechniqueEvaluators）
//   2) 模板里的音频分析（音高 / 颗粒度 / 节奏 / 稳定性）
//  结构遵循用户提供的模板：总体评价 → 详细分析（四维度）→ 错误定位与建议。
//  所有分析完全离线：麦克风音频只在内存里滑动，不落盘、不上传。
//

import Foundation
import AVFoundation
import Accelerate
import SwiftUI

// MARK: - 练习曲目

/// 用户进入智能指法教练后可选择的练习曲目，默认「指法基本功」。
enum PracticePiece: String, CaseIterable, Identifiable, Codable {
    case etude = "指法基本功"
    case springRiver = "春江花月夜"
    case ambush = "十面埋伏"
    case kingUnarm = "霸王卸甲"
    case bigWaves = "大浪淘沙"
    case yangChun = "阳春白雪"
    case zhaoJun = "昭君出塞"
    case pingSha = "平沙落雁"
    case lvYao = "新番羽调绿腰"
    case tashikuergan = "阳光照耀着塔什库尔干"
    case caoyuan = "草原小姐妹"
    case weiShui = "渭水情"

    var id: String { rawValue }

    /// 本地化显示名（中文环境即原文，英文走 en.lproj）
    var displayName: String { L(rawValue) }

    /// 该曲目参考速度（BPM）。练习曲无固定速度，返回 nil。
    var targetTempoBPM: Double? {
        switch self {
        case .etude:       return nil
        case .springRiver: return 69
        case .ambush:      return 120
        case .kingUnarm:   return 76
        case .bigWaves:    return 58
        case .yangChun:    return 104
        case .zhaoJun:     return 66
        case .pingSha:     return 58
        case .lvYao:       return 88
        case .tashikuergan: return 132
        case .caoyuan:    return 96
        case .weiShui:    return 60
        }
    }

    /// 以曲目意象配色：深色起笔、中色铺陈、浅色留白。
    var theme: PieceTheme {
        switch self {
        case .etude: // 基本功：原有蓝色
            return PieceTheme(
                gradient: [
                    Color(red: 107.0 / 255, green: 133.0 / 255, blue: 235.0 / 255),
                    Color(red: 71.0 / 255, green: 94.0 / 255, blue: 184.0 / 255),
                    Color(red: 221.0 / 255, green: 229.0 / 255, blue: 255.0 / 255),
                ],
                accent: Color(red: 80.0 / 255, green: 109.0 / 255, blue: 204.0 / 255),
                headerForeground: .primary,
                headerSecondaryForeground: .secondary)
        case .springRiver: // 春江：江青、水雾、月白
            return PieceTheme(
                gradient: [
                    Color(red: 36.0 / 255, green: 107.0 / 255, blue: 120.0 / 255),
                    Color(red: 141.0 / 255, green: 184.0 / 255, blue: 186.0 / 255),
                    Color(red: 243.0 / 255, green: 235.0 / 255, blue: 210.0 / 255),
                ],
                accent: Color(red: 54.0 / 255, green: 124.0 / 255, blue: 133.0 / 255),
                reportBackgroundImage: "CoachSpringRiver")
        case .ambush: // 十面：墨色、暗红、古铜
            return PieceTheme(
                gradient: [
                    Color(red: 52.0 / 255, green: 46.0 / 255, blue: 55.0 / 255),
                    Color(red: 152.0 / 255, green: 61.0 / 255, blue: 59.0 / 255),
                    Color(red: 183.0 / 255, green: 149.0 / 255, blue: 97.0 / 255),
                ],
                accent: Color(red: 173.0 / 255, green: 81.0 / 255, blue: 66.0 / 255),
                reportBackgroundImage: "CoachAmbush")
        case .kingUnarm: // 霸王：墨紫、赭红、残阳
            return PieceTheme(
                gradient: [
                    Color(red: 73.0 / 255, green: 51.0 / 255, blue: 73.0 / 255),
                    Color(red: 131.0 / 255, green: 81.0 / 255, blue: 93.0 / 255),
                    Color(red: 195.0 / 255, green: 146.0 / 255, blue: 118.0 / 255),
                ],
                accent: Color(red: 166.0 / 255, green: 108.0 / 255, blue: 118.0 / 255),
                reportBackgroundImage: "CoachKingUnarm")
        case .bigWaves: // 淘沙：深水、浪青、沙金
            return PieceTheme(
                gradient: [
                    Color(red: 36.0 / 255, green: 84.0 / 255, blue: 109.0 / 255),
                    Color(red: 100.0 / 255, green: 139.0 / 255, blue: 153.0 / 255),
                    Color(red: 195.0 / 255, green: 170.0 / 255, blue: 121.0 / 255),
                ],
                accent: Color(red: 66.0 / 255, green: 122.0 / 255, blue: 145.0 / 255),
                reportBackgroundImage: "CoachBigWaves")
        case .yangChun: // 阳春：春枝、嫩绿、雪白
            return PieceTheme(
                gradient: [
                    Color(red: 82.0 / 255, green: 126.0 / 255, blue: 93.0 / 255),
                    Color(red: 183.0 / 255, green: 208.0 / 255, blue: 173.0 / 255),
                    Color(red: 244.0 / 255, green: 241.0 / 255, blue: 226.0 / 255),
                ],
                accent: Color(red: 89.0 / 255, green: 134.0 / 255, blue: 98.0 / 255),
                reportBackgroundImage: "CoachYangChun",
                imageOverlayOpacity: 0.58)
        case .zhaoJun: // 昭君：塞外沙金、远山青灰
            return PieceTheme(
                gradient: [
                    Color(red: 161.0 / 255, green: 133.0 / 255, blue: 87.0 / 255),
                    Color(red: 189.0 / 255, green: 174.0 / 255, blue: 146.0 / 255),
                    Color(red: 100.0 / 255, green: 126.0 / 255, blue: 145.0 / 255),
                ],
                accent: Color(red: 153.0 / 255, green: 119.0 / 255, blue: 70.0 / 255),
                reportBackgroundImage: "CoachZhaoJun",
                imageOverlayOpacity: 0.52)
        case .pingSha: // 平沙：雾灰、秋水、芦苇
            return PieceTheme(
                gradient: [
                    Color(red: 126.0 / 255, green: 134.0 / 255, blue: 127.0 / 255),
                    Color(red: 188.0 / 255, green: 197.0 / 255, blue: 188.0 / 255),
                    Color(red: 216.0 / 255, green: 202.0 / 255, blue: 170.0 / 255),
                ],
                accent: Color(red: 112.0 / 255, green: 124.0 / 255, blue: 105.0 / 255),
                reportBackgroundImage: "CoachPingSha",
                imageOverlayOpacity: 0.56)
        case .lvYao: // 绿腰：唐风青绿、绢色、淡金
            return PieceTheme(
                gradient: [
                    Color(red: 39.0 / 255, green: 123.0 / 255, blue: 116.0 / 255),
                    Color(red: 168.0 / 255, green: 191.0 / 255, blue: 158.0 / 255),
                    Color(red: 207.0 / 255, green: 173.0 / 255, blue: 98.0 / 255),
                ],
                accent: Color(red: 143.0 / 255, green: 119.0 / 255, blue: 55.0 / 255),
                reportBackgroundImage: "CoachLvYao",
                imageOverlayOpacity: 0.50)
        case .tashikuergan: // 塔什库尔干：晴空、雪峰、阳光
            return PieceTheme(
                gradient: [
                    Color(red: 54.0 / 255, green: 127.0 / 255, blue: 173.0 / 255),
                    Color(red: 220.0 / 255, green: 234.0 / 255, blue: 241.0 / 255),
                    Color(red: 227.0 / 255, green: 185.0 / 255, blue: 94.0 / 255),
                ],
                accent: Color(red: 59.0 / 255, green: 131.0 / 255, blue: 176.0 / 255),
                reportBackgroundImage: "CoachTashikuergan",
                imageOverlayOpacity: 0.58)
        case .caoyuan: // 草原：草绿、远野、风雪
            return PieceTheme(
                gradient: [
                    Color(red: 56.0 / 255, green: 124.0 / 255, blue: 100.0 / 255),
                    Color(red: 166.0 / 255, green: 195.0 / 255, blue: 177.0 / 255),
                    Color(red: 236.0 / 255, green: 241.0 / 255, blue: 238.0 / 255),
                ],
                accent: Color(red: 64.0 / 255, green: 132.0 / 255, blue: 105.0 / 255),
                reportBackgroundImage: "CoachCaoyuan",
                imageOverlayOpacity: 0.54)
        case .weiShui: // 渭水：黄土、河岸、渭水青
            return PieceTheme(
                gradient: [
                    Color(red: 146.0 / 255, green: 108.0 / 255, blue: 75.0 / 255),
                    Color(red: 198.0 / 255, green: 169.0 / 255, blue: 125.0 / 255),
                    Color(red: 119.0 / 255, green: 153.0 / 255, blue: 150.0 / 255),
                ],
                accent: Color(red: 150.0 / 255, green: 116.0 / 255, blue: 73.0 / 255),
                reportBackgroundImage: "CoachWeiShui",
                imageOverlayOpacity: 0.54)
        }
    }

}

// 兼容更名前持久化的历史报告：旧 rawValue「练习曲」统一映射为 etude。
extension PracticePiece {
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let p = PracticePiece(rawValue: raw) {
            self = p
        } else {
            self = .etude
        }
    }
}

/// 报告主题配色（非持久化，仅用于界面展示）。
struct PieceTheme {
    let gradient: [Color]
    let accent: Color
    let reportBackgroundImage: String?
    let headerForeground: Color
    let headerSecondaryForeground: Color
    let imageOverlayOpacity: Double

    init(
        gradient: [Color],
        accent: Color,
        reportBackgroundImage: String? = nil,
        headerForeground: Color = Color(red: 1.0, green: 0.98, blue: 0.92),
        headerSecondaryForeground: Color = Color.white.opacity(0.82),
        imageOverlayOpacity: Double = 0.46
    ) {
        self.gradient = gradient
        self.accent = accent
        self.reportBackgroundImage = reportBackgroundImage
        self.headerForeground = headerForeground
        self.headerSecondaryForeground = headerSecondaryForeground
        self.imageOverlayOpacity = imageOverlayOpacity
    }
}

// MARK: - 报告数据模型

struct CoachReport: Identifiable, Codable {
    let id = UUID()

    let piece: PracticePiece
    let duration: TimeInterval
    let date: Date

    /// 综合得分（满分 100）
    let overallScore: Double
    /// 总体评价结论（一句话）
    let grade: String

    /// 四大维度（顺序固定：指法准确度 / 演奏颗粒度 / 节奏准确性 / 演奏稳定性）
    let dimensions: [DimensionScore]

    /// 各维度的详细指标
    let details: [CoachReport.DimensionDetail]

    /// 乐曲维度（仅指定曲目有：《春江花月夜》乐曲表现力、《十面埋伏》张力与气势、《霸王卸甲》情感深度；练习曲为 nil）
    let pieceDimension: DimensionScore?

    /// 乐曲维度的详细指标
    let pieceDetail: DimensionDetail?

    /// 典型错误点位
    let errorPoints: [CoachReport.ErrorPoint]

    /// AI 智能改进建议（编号列表）
    let suggestions: [String]

    /// 首部一句话乐曲介绍
    let intro: String

    /// 对乐曲情感把握的正面激励评价
    let emotionalComment: String

    /// 格式化日期（用于历史列表展示）
    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    struct DimensionScore: Identifiable, Codable {
        let id = UUID()
        let title: String
        let score: Double
        let weight: Int        // 权重（百分比整数，如 30）
        let comment: String    // 评价：优秀 / 良好 / 基本达标 / 未达标
    }

    struct Metric: Codable {
        let label: String
        let value: String
        let note: String
    }

    struct DimensionDetail: Identifiable, Codable {
        let id = UUID()
        let title: String
        let metrics: [Metric]
    }

    struct ErrorPoint: Codable {
        let timeLabel: String  // 如「约第 12 秒」
        let issue: String
        let detail: String
    }
}

// MARK: - 端侧分析器

/// 在演奏过程中持续累积 16 kHz 单声道采样（音频）与逐帧视频手型评估，
/// 演奏结束后一次性算出报告所需指标。
/// 所有计算在内存中完成，不保留任何音频数据。
/// 内部用一个串行队列保护可变状态：音频 tap 在后台队列喂数据，
/// 视频帧在主线程记录手型，stop 时统一取快照生成报告，避免竞态。
final class SessionAudioAnalyzer {

    private let sampleRate: Double
    private let windowSize: Int
    private let hopSize: Int
    private let queue = DispatchQueue(label: "com.pluckbuddy.coachreport.analysis")

    // —— 以下状态仅在本队列内访问 ——
    private var pending = [Float]()
    private var processedSamples: Int64 = 0

    private var rmsHistory: [Double] = []
    private var zcrHistory: [Double] = []          // 过零率（音色亮度近似）
    private var pitchCents: [Double] = []          // 每个有音高帧相对最近等律音的偏差（音分）
    private var activeFrames = 0
    private var tonalFrames = 0                     // 检出清晰音高的活跃帧

    private var onsetTimes: [Double] = []
    private var lastOnsetTime: Double = -1
    private var rmsEMA: Double = 0
    private var wasActive = false

    private var rollIOIs: [Double] = []            // 轮指段内的起音间隔

    private var currentTechnique: TechniqueType = .unknown
    private var techniqueObsTotal = 0
    private var techniqueObsKnown = 0

    // 视频手型评估（逐帧传入 PostureEvaluation 的各方面分数）
    private var postureScores: [Double] = []              // overallScore 序列
    private var postureHandShapeScores: [Double] = []     // 手型维度
    private var postureTigerMouthScores: [Double] = []    // 虎口角度维度

    private var worstPitch: (time: Double, cents: Double)?
    private var worstOnsetIndex: Int?

    init(sampleRate: Double = 16000, windowSize: Int = 1024) {
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        self.hopSize = windowSize
    }

    // MARK: - 外部喂数据（线程安全）

    /// 由声音分类引擎的同一个音频 tap 转发 16 kHz 单声道样本。
    func process(_ samples: [Float]) {
        queue.async { [weak self] in self?._process(samples) }
    }

    /// 记录当前稳定技法（视频侧识别结果）
    func recordTechnique(_ technique: TechniqueType) {
        queue.async { [weak self] in self?._recordTechnique(technique) }
    }

    /// 记录一帧真实视频手型评估（智能指法教练的 PostureEvaluation）
    func recordPosture(evaluation: PostureEvaluation) {
        queue.async { [weak self] in self?._recordPosture(evaluation) }
    }

    func reset() {
        queue.async { [weak self] in self?._reset() }
    }

    /// 演奏结束生成报告：先在本队列取快照，再在主线程（调用方）构建报告，
    /// 这样 finalize 内部调用 L() 不会触碰后台线程的隔离状态。
    func finalize(piece: PracticePiece, duration: TimeInterval) -> CoachReport {
        let snap = queue.sync { _snapshot() }
        return Self.buildReport(snapshot: snap, piece: piece, duration: duration)
    }

    // MARK: - 队列内实现

    private func _process(_ samples: [Float]) {
        pending.append(contentsOf: samples)
        while pending.count >= windowSize {
            let window = Array(pending.prefix(windowSize))
            pending.removeFirst(hopSize)
            analyzeWindow(window)
        }
        // 防止积压
        if pending.count > windowSize * 8 {
            pending.removeFirst(pending.count - windowSize)
        }
    }

    private func _recordTechnique(_ technique: TechniqueType) {
        techniqueObsTotal += 1
        if technique != .unknown {
            techniqueObsKnown += 1
            currentTechnique = technique
        } else {
            currentTechnique = .unknown
        }
    }

    private func _recordPosture(_ evaluation: PostureEvaluation) {
        postureScores.append(evaluation.overallScore)
        for aspect in evaluation.aspects {
            switch aspect.category {
            case .handShape:  postureHandShapeScores.append(aspect.score)
            case .tigerMouth: postureTigerMouthScores.append(aspect.score)
            default: break
            }
        }
    }

    private func _reset() {
        pending.removeAll()
        processedSamples = 0
        rmsHistory.removeAll()
        zcrHistory.removeAll()
        pitchCents.removeAll()
        activeFrames = 0
        tonalFrames = 0
        onsetTimes.removeAll()
        lastOnsetTime = -1
        rmsEMA = 0
        wasActive = false
        rollIOIs.removeAll()
        currentTechnique = .unknown
        techniqueObsTotal = 0
        techniqueObsKnown = 0
        postureScores.removeAll()
        postureHandShapeScores.removeAll()
        postureTigerMouthScores.removeAll()
        worstPitch = nil
        worstOnsetIndex = nil
    }

    private struct Snapshot {
        let rmsHistory: [Double]
        let zcrHistory: [Double]
        let pitchCents: [Double]
        let activeFrames: Int
        let tonalFrames: Int
        let onsetTimes: [Double]
        let rollIOIs: [Double]
        let techniqueObsTotal: Int
        let techniqueObsKnown: Int
        let postureScores: [Double]
        let postureHandShapeScores: [Double]
        let postureTigerMouthScores: [Double]
        let worstPitch: (time: Double, cents: Double)?
        let worstOnsetIndex: Int?
    }

    private func _snapshot() -> Snapshot {
        Snapshot(
            rmsHistory: rmsHistory,
            zcrHistory: zcrHistory,
            pitchCents: pitchCents,
            activeFrames: activeFrames,
            tonalFrames: tonalFrames,
            onsetTimes: onsetTimes,
            rollIOIs: rollIOIs,
            techniqueObsTotal: techniqueObsTotal,
            techniqueObsKnown: techniqueObsKnown,
            postureScores: postureScores,
            postureHandShapeScores: postureHandShapeScores,
            postureTigerMouthScores: postureTigerMouthScores,
            worstPitch: worstPitch,
            worstOnsetIndex: worstOnsetIndex
        )
    }

    private func analyzeWindow(_ window: [Float]) {
        let time = Double(processedSamples) / sampleRate
        processedSamples += Int64(window.count)

        var rms: Float = 0
        vDSP_rmsqv(window, 1, &rms, vDSP_Length(window.count))
        let rmsD = Double(rms)

        // 过零率（音色亮度近似）
        var zcr = 0
        for i in 1..<window.count {
            if (window[i] >= 0) != (window[i - 1] >= 0) { zcr += 1 }
        }
        let zcrD = Double(zcr) / Double(window.count)

        rmsHistory.append(rmsD)
        zcrHistory.append(zcrD)

        let active = rmsD > 0.02
        if active { activeFrames += 1 }

        // 长期 RMS 均值（EMA），用于起音检测
        rmsEMA = rmsEMA == 0 ? rmsD : rmsEMA * 0.95 + rmsD * 0.05

        if active {
            if let freq = estimatePitch(window), freq > 60, freq < 1200 {
                let cents = centsDeviation(freq)
                pitchCents.append(cents)
                tonalFrames += 1
                if worstPitch == nil || abs(cents) > abs(worstPitch!.cents) {
                    worstPitch = (time, cents)
                }
            }

            // 起音检测：当前能量明显高于背景且距上次起音足够远
            if rmsD > max(rmsEMA * 1.8, 0.03) && (time - lastOnsetTime) > 0.08 {
                if lastOnsetTime > 0, currentTechnique == .roll {
                    let ioi = time - lastOnsetTime
                    if ioi > 0.05, ioi < 1.5 { rollIOIs.append(ioi) }
                }
                if onsetTimes.count >= 2 {
                    let iois = zip(onsetTimes, onsetTimes.dropFirst()).map { $1 - $0 }
                    if let median = iois.median {
                        var maxDev = 0.0, maxIdx = onsetTimes.count - 1
                        for i in 1..<iois.count {
                            let dev = abs(iois[i] - median)
                            if dev > maxDev { maxDev = dev; maxIdx = i }
                        }
                        if maxDev > median * 0.35 { worstOnsetIndex = maxIdx }
                    }
                }
                onsetTimes.append(time)
                lastOnsetTime = time
            }
        }

        wasActive = active
    }

    // MARK: - 音高估计（自相关，覆盖琵琶有效音域）

    private func estimatePitch(_ window: [Float]) -> Double? {
        let n = window.count
        guard n > 0 else { return nil }
        var rms: Float = 0
        vDSP_rmsqv(window, 1, &rms, vDSP_Length(n))
        guard rms > 0.02 else { return nil }

        // 去直流
        var mean: Float = 0
        vDSP_meanv(window, 1, &mean, vDSP_Length(n))
        var centered = window
        var centeredOut = [Float](repeating: 0, count: n)
        vDSP_vsub([mean], 0, centered, 1, &centeredOut, 1, vDSP_Length(n))
        centered = centeredOut

        let minLag = max(2, Int(sampleRate / 1200))
        let maxLag = min(n - 1, Int(sampleRate / 60))
        guard maxLag > minLag else { return nil }

        var bestLag = 0
        var bestCorr: Float = 0
        for lag in minLag...maxLag {
            var corr: Float = 0
            vDSP_dotpr(centered, 1, &centered[lag], 1, &corr, vDSP_Length(n - lag))
            if corr > bestCorr { bestCorr = corr; bestLag = lag }
        }
        guard bestLag > 0, bestCorr > 1e-4 else { return nil }
        return sampleRate / Double(bestLag)
    }

    /// 相对最近等律音的偏差（音分）。正为偏高，负为偏低。
    private func centsDeviation(_ freq: Double) -> Double {
        let n = 12 * log2(freq / 440.0)
        let nearest = round(n)
        let etFreq = 440.0 * pow(2.0, nearest / 12.0)
        return 1200 * log2(freq / etFreq)
    }

    // MARK: - 报告构建（在主线程调用，可安全使用 L()）

    private static func buildReport(
        snapshot: Snapshot,
        piece: PracticePiece,
        duration: TimeInterval
    ) -> CoachReport {

        let rmsHistory = snapshot.rmsHistory
        let zcrHistory = snapshot.zcrHistory
        let pitchCents = snapshot.pitchCents
        let activeFrames = snapshot.activeFrames
        let tonalFrames = snapshot.tonalFrames
        let onsetTimes = snapshot.onsetTimes
        let rollIOIs = snapshot.rollIOIs
        let techniqueObsTotal = snapshot.techniqueObsTotal
        let techniqueObsKnown = snapshot.techniqueObsKnown
        let postureScores = snapshot.postureScores
        let postureHandShapeScores = snapshot.postureHandShapeScores
        let postureTigerMouthScores = snapshot.postureTigerMouthScores
        let worstPitch = snapshot.worstPitch
        let worstOnsetIndex = snapshot.worstOnsetIndex

        // ===== 视频手型评估（智能指法教练真实使用的信号）=====
        let handShapeAvg = postureHandShapeScores.isEmpty
            ? (postureScores.isEmpty ? 75 : postureScores.reduce(0, +) / Double(postureScores.count))
            : postureHandShapeScores.reduce(0, +) / Double(postureHandShapeScores.count)
        let tigerMouthAvg = postureTigerMouthScores.isEmpty
            ? 75
            : postureTigerMouthScores.reduce(0, +) / Double(postureTigerMouthScores.count)
        let videoPosture = (handShapeAvg + tigerMouthAvg) / 2   // 视频手型综合（手型 + 虎口）
        let postureStability: Double = postureScores.isEmpty ? 75 : {
            let m = postureScores.reduce(0, +) / Double(postureScores.count)
            let cv = m > 0 ? stddev(postureScores) / m : 1
            return max(0, 100 - cv * 150)
        }()
        let techniqueCorrectness: Double = techniqueObsTotal == 0
            ? (techniqueObsKnown > 0 ? 90 : 60)
            : min(100, Double(techniqueObsKnown) / Double(techniqueObsTotal) * 100)

        // ===== 音频：音准（用于「指法准确度」的次级信号）=====
        let meanAbsCents = pitchCents.isEmpty ? nil :
            pitchCents.map { abs($0) }.reduce(0, +) / Double(pitchCents.count)
        let inTuneRate = pitchCents.isEmpty ? 0 :
            Double(pitchCents.filter { abs($0) <= 15 }.count) / Double(pitchCents.count) * 100
        let outOfTuneCount = pitchCents.filter { abs($0) > 25 }.count
        let intonationScore: Double = meanAbsCents == nil ? 70 :
            max(40, 100 - meanAbsCents! * 3)

        // ===== 维度一：指法准确度（视频手型主导 + 技法识别 + 音准）=====
        let fingeringScore = clamp(videoPosture * 0.5 + techniqueCorrectness * 0.3 + intonationScore * 0.2)

        // ===== 维度二：演奏颗粒度（音频）=====
        let noteCleanliness = activeFrames == 0 ? 70 :
            Double(tonalFrames) / Double(activeFrames) * 100
        let noiseEnergyPct = 100 - noteCleanliness
        let rollUniformity: Double
        if rollIOIs.count >= 3 {
            let mean = rollIOIs.reduce(0, +) / Double(rollIOIs.count)
            let cv = (stddev(rollIOIs) / mean)
            rollUniformity = max(0, 100 - cv * 250)
        } else {
            rollUniformity = 75
        }
        let articulationScore = clamp(noteCleanliness * 0.7 + rollUniformity * 0.3)

        // ===== 维度三：节奏准确性（音频）=====
        var rhythmScore = 70.0
        var avgBeatDevMs = 0.0
        var noteValueAcc = 0.0
        var rushDragCount = 0
        var consistency = 75.0
        if onsetTimes.count >= 4 {
            let iois = zip(onsetTimes, onsetTimes.dropFirst()).map { $1 - $0 }
            let meanIOI = iois.reduce(0, +) / Double(iois.count)
            let std = stddev(iois)
            avgBeatDevMs = std * 1000
            let cv = meanIOI > 0 ? std / meanIOI : 1
            consistency = max(0, 100 - cv * 250)
            let tempo = 60 / meanIOI
            let tempoCloseness: Double = piece.targetTempoBPM == nil ? 85 :
                max(0, 100 - abs(tempo - piece.targetTempoBPM!) / piece.targetTempoBPM! * 100)
            rhythmScore = clamp(consistency * 0.7 + tempoCloseness * 0.3)
            noteValueAcc = max(0, 100 - cv * 200)
            rushDragCount = iois.filter { abs($0 - (iois.median ?? meanIOI)) > (iois.median ?? meanIOI) * 0.35 }.count
        }

        // ===== 维度四：演奏稳定性（音频 + 视频手型稳定度）=====
        let pitchStability: Double = pitchCents.isEmpty ? 75 :
            max(0, 100 - stddev(pitchCents.map { abs($0) }) * 4)
        let activeRMS = rmsHistory.filter { $0 > 0.02 }
        let dynStability: Double = activeRMS.isEmpty ? 75 : {
            let m = activeRMS.reduce(0, +) / Double(activeRMS.count)
            let cv = m > 0 ? stddev(activeRMS) / m : 1
            return max(0, 100 - cv * 150)
        }()
        let timbreStability: Double = zcrHistory.isEmpty ? 75 : {
            let m = zcrHistory.reduce(0, +) / Double(zcrHistory.count)
            let cv = m > 0 ? stddev(zcrHistory) / m : 1
            return max(0, 100 - cv * 200)
        }()
        let rhythmConsistency = onsetTimes.count >= 4 ? consistency : 75
        let stabilityScore = clamp(
            (pitchStability + dynStability + timbreStability + rhythmConsistency + postureStability) / 5
        )

        // ===== 综合（权重：指法 30 / 颗粒 25 / 节奏 25 / 稳定 20）=====
        let overall = 0.30 * fingeringScore + 0.25 * articulationScore + 0.25 * rhythmScore + 0.20 * stabilityScore

        // ===== 维度卡片 =====
        let dimensions = [
            CoachReport.DimensionScore(title: L("指法准确度"), score: fingeringScore, weight: 30, comment: gradeComment(fingeringScore)),
            CoachReport.DimensionScore(title: L("演奏颗粒度"), score: articulationScore, weight: 25, comment: gradeComment(articulationScore)),
            CoachReport.DimensionScore(title: L("节奏准确性"), score: rhythmScore, weight: 25, comment: gradeComment(rhythmScore)),
            CoachReport.DimensionScore(title: L("演奏稳定性"), score: stabilityScore, weight: 20, comment: gradeComment(stabilityScore)),
        ]

        // ===== 详细分析 =====
        let details: [CoachReport.DimensionDetail] = [
            CoachReport.DimensionDetail(title: L("详细分析：指法准确度"), metrics: [
                CoachReport.Metric(label: L("视频手型评分"), value: String(format: "%.1f", handShapeAvg), note: L("来自 21 关键点手型评估")),
                CoachReport.Metric(label: L("虎口角度达标"), value: String(format: "%.1f", tigerMouthAvg), note: L("虎口自然张开程度")),
                CoachReport.Metric(label: L("技法识别正确率"), value: String(format: "%.1f%%", techniqueCorrectness), note: L("综合技法掌握度")),
                CoachReport.Metric(label: L("平均音高偏差"), value: meanAbsCents == nil ? L("—") : String(format: "±%.1f 音分", meanAbsCents!), note: L("合格标准: ≤±15 音分")),
                CoachReport.Metric(label: L("按弦到位率"), value: String(format: "%.1f%%", inTuneRate), note: L("音准达标比例")),
                CoachReport.Metric(label: L("错品/虚按次数"), value: "\(outOfTuneCount)", note: L("需重点关注的误差来源")),
            ]),
            CoachReport.DimensionDetail(title: L("详细分析：演奏颗粒度"), metrics: [
                CoachReport.Metric(label: L("音符干净率"), value: String(format: "%.1f%%", noteCleanliness), note: L("表现良好")),
                CoachReport.Metric(label: L("杂音能量占比"), value: String(format: "%.1f%%", noiseEnergyPct), note: L("合格标准: ≤ 5%")),
                CoachReport.Metric(label: L("轮指均匀度"), value: String(format: "%.1f%%", rollUniformity), note: L("有待提升")),
            ]),
            CoachReport.DimensionDetail(title: L("详细分析：节奏准确性"), metrics: [
                CoachReport.Metric(label: L("平均节拍偏差"), value: String(format: "%.0f ms", avgBeatDevMs), note: L("合格标准: ≤30ms")),
                CoachReport.Metric(label: L("音符时值准确率"), value: String(format: "%.1f%%", noteValueAcc), note: L("对音符长短把控精准度")),
                CoachReport.Metric(label: L("抢拍/拖拍次数"), value: "\(rushDragCount)", note: L("整体律动稳定性")),
            ]),
            CoachReport.DimensionDetail(title: L("详细分析：演奏稳定性"), metrics: [
                CoachReport.Metric(label: L("手型稳定度"), value: String(format: "%.0f", postureStability), note: L("视频手型维度")),
                CoachReport.Metric(label: L("音高稳定性"), value: String(format: "%.0f", pitchStability), note: L("音频音高维度")),
                CoachReport.Metric(label: L("力度稳定性"), value: String(format: "%.0f", dynStability), note: L("音频力度维度")),
                CoachReport.Metric(label: L("音色稳定性"), value: String(format: "%.0f", timbreStability), note: L("音频音色维度")),
                CoachReport.Metric(label: L("节奏一致性"), value: String(format: "%.0f", rhythmConsistency), note: L("音频节奏维度")),
            ]),
        ]

        // ===== 乐曲维度（仅指定曲目有）=====
        // 力度对比 / 戏剧张力 / 整体能量，均从活跃帧 RMS 序列派生
        let activeRMSValues = rmsHistory.filter { $0 > 0.02 }
        let dynContrast: Double = activeRMSValues.count < 2 ? 60 : {
            let mx = activeRMSValues.max()!, mn = activeRMSValues.min()!
            let mean = activeRMSValues.reduce(0, +) / Double(activeRMSValues.count)
            let spread = (mx - mn) / max(mean, 1e-6)
            // 力度层次：相对跨度约 0.6 为最佳，过平或过炸降分
            return clamp(100 - abs(spread - 0.6) * 120)
        }()
        let dramaticContrast: Double = activeRMSValues.count < 2 ? 60 : {
            let mx = activeRMSValues.max()!, mn = activeRMSValues.min()!
            let mean = activeRMSValues.reduce(0, +) / Double(activeRMSValues.count)
            let spread = (mx - mn) / max(mean, 1e-6)
            return clamp(spread * 80)   // 跨度越大越戏剧化
        }()
        let energyScore: Double = activeRMSValues.isEmpty ? 60 : {
            let mean = activeRMSValues.reduce(0, +) / Double(activeRMSValues.count)
            return clamp(mean / 0.25 * 100)
        }()

        let pieceDimension: CoachReport.DimensionScore?
        let pieceDetail: CoachReport.DimensionDetail?
        switch piece {
        case .etude:
            pieceDimension = nil
            pieceDetail = nil
        case .springRiver, .bigWaves, .yangChun, .pingSha, .lvYao:
            let flow = (pitchStability + timbreStability) / 2          // 旋律流畅度
            let shading = dynContrast                                   // 力度层次
            let phrasing = (postureStability + noteCleanliness) / 2    // 乐句连贯
            let score = clamp(flow * 0.4 + shading * 0.35 + phrasing * 0.25)
            pieceDimension = CoachReport.DimensionScore(
                title: L("乐曲表现力"), score: score, weight: 0, comment: gradeComment(score))
            pieceDetail = CoachReport.DimensionDetail(title: L("乐曲维度：") + piece.displayName, metrics: [
                CoachReport.Metric(label: L("旋律流畅度"), value: String(format: "%.1f", flow), note: L("音高与音色连贯平滑")),
                CoachReport.Metric(label: L("力度层次"), value: String(format: "%.1f", shading), note: L("强弱对比与表情起伏")),
                CoachReport.Metric(label: L("乐句连贯"), value: String(format: "%.1f", phrasing), note: L("手型与音符分离稳定")),
            ])
        case .ambush, .tashikuergan, .caoyuan:
            let drive = consistency                                     // 节奏驱动力
            let contrast = dramaticContrast                             // 戏剧性对比
            let power = clamp(noteCleanliness * 0.5 + energyScore * 0.5) // 扫拂气势与清晰度
            let score = clamp(drive * 0.4 + contrast * 0.35 + power * 0.25)
            pieceDimension = CoachReport.DimensionScore(
                title: L("乐曲张力与气势"), score: score, weight: 0, comment: gradeComment(score))
            pieceDetail = CoachReport.DimensionDetail(title: L("乐曲维度：") + piece.displayName, metrics: [
                CoachReport.Metric(label: L("节奏驱动力"), value: String(format: "%.1f", drive), note: L("稳定而推进的节拍律动")),
                CoachReport.Metric(label: L("戏剧性对比"), value: String(format: "%.1f", contrast), note: L("强弱戏剧张力")),
                CoachReport.Metric(label: L("扫拂气势与清晰度"), value: String(format: "%.1f", power), note: L("快速扫拂的力量与干净度")),
            ])
        case .kingUnarm, .zhaoJun, .weiShui:
            let phraseCoherence = (postureStability + noteCleanliness) / 2    // 乐句连贯
            let dynShading = dynContrast                                      // 力度层次
            let emotionalLayer = clamp(dramaticContrast * 0.5 + phraseCoherence * 0.5) // 情感层次
            let score = clamp(emotionalLayer * 0.4 + dynShading * 0.35 + phraseCoherence * 0.25)
            pieceDimension = CoachReport.DimensionScore(
                title: L("乐曲情感深度"), score: score, weight: 0, comment: gradeComment(score))
            pieceDetail = CoachReport.DimensionDetail(title: L("乐曲维度：") + piece.displayName, metrics: [
                CoachReport.Metric(label: L("情感层次"), value: String(format: "%.1f", emotionalLayer), note: L("强弱与情绪的起伏对比")),
                CoachReport.Metric(label: L("力度层次"), value: String(format: "%.1f", dynShading), note: L("强弱对比与表情起伏")),
                CoachReport.Metric(label: L("乐句连贯"), value: String(format: "%.1f", phraseCoherence), note: L("手型与音符分离稳定")),
            ])
        }

        // ===== 首部乐曲介绍 + 情感把握正面激励评价 =====
        let intro = piece.introduction
        let emotionalComment: String
        switch piece {
        case .etude:
            emotionalComment = L("你对基础技法的踏实与稳定令人欣喜，保持这份专注，进步会显而易见。")
        case .springRiver:
            emotionalComment = L("你用连贯的乐句传递出月夜的静谧与流动，已初见意境；继续用心去“唱”这根弦，情感会更饱满。")
        case .ambush:
            emotionalComment = L("你在激越处爆发张力、在收束处懂得克制，已触摸到这首武曲的精气神，气势越来越足。")
        case .kingUnarm:
            emotionalComment = L("你在慢板里注入了难得的沉静与悲悯，把英雄末路的情绪慢慢讲清楚了，这份共情很打动人。")
        case .bigWaves:
            emotionalComment = L("你在舒缓的长音里守住了难得的沉静，声音越来越有江水的深度，这份定力很可贵。")
        case .yangChun:
            emotionalComment = L("你的演奏明亮而不浮躁，弹挑干净、气息轻盈，把春天的清爽劲儿带出来了。")
        case .zhaoJun:
            emotionalComment = L("你在推拉吟揉间注入了细腻的情绪，慢板里的牵挂与不舍让人动容，很有感染力。")
        case .pingSha:
            emotionalComment = L("你肯在音乐里「留白」，让声音静下来，这份淡远从容正是这首曲子的味道。")
        case .lvYao:
            emotionalComment = L("你的乐句流畅而有分寸，古韵里带着生动的舞意，气度越来越好。")
        case .tashikuergan:
            emotionalComment = L("你的演奏像高原的阳光一样透亮，节奏向前、情绪饱满，听得出心里的那份火热。")
        case .caoyuan:
            emotionalComment = L("你在风雪般的急奏里守住了力量与控制的平衡，把小姐妹的勇敢一点点奏出来了，很有画面感。")
        case .weiShui:
            emotionalComment = L("你的吟揉里带着黄土高原的厚意，慢板处的乡愁真挚动人，越弹越有味道了。")
        }

        // ===== 错误定位 =====
        var errorPoints: [CoachReport.ErrorPoint] = []
        if let wp = worstPitch, abs(wp.cents) > 25 {
            errorPoints.append(CoachReport.ErrorPoint(
                timeLabel: String(format: L("约第 %.0f 秒"), wp.time),
                issue: wp.cents > 0 ? L("音准偏高") : L("音准偏低"),
                detail: String(format: L("音分偏差 %+.1f"), wp.cents)))
        }
        if let idx = worstOnsetIndex, idx < onsetTimes.count {
            errorPoints.append(CoachReport.ErrorPoint(
                timeLabel: String(format: L("约第 %.0f 秒"), onsetTimes[idx]),
                issue: L("节奏不稳"),
                detail: L("该处抢拍或拖拍明显")))
        }
        if handShapeAvg < 70 {
            errorPoints.append(CoachReport.ErrorPoint(
                timeLabel: L("全程"),
                issue: L("手型待改进"),
                detail: L("部分片段手型评分偏低，注意手指自然弯曲与触弦角度")))
        }
        if noteCleanliness < 80 {
            errorPoints.append(CoachReport.ErrorPoint(
                timeLabel: L("演奏中段"),
                issue: L("颗粒度下降"),
                detail: L("杂音占比偏高，音符分离度不足")))
        }
        if errorPoints.isEmpty {
            errorPoints.append(CoachReport.ErrorPoint(
                timeLabel: L("全程"),
                issue: L("未检出明显错误"),
                detail: L("各项指标均在良好区间内")))
        }

        // ===== 建议 =====
        var suggestions: [String] = []
        if handShapeAvg < 80 {
            suggestions.append(L("注意手指自然弯曲、虎口自然张开，让手型更接近标准演奏姿势。"))
        }
        if tigerMouthAvg < 80 {
            suggestions.append(L("调整虎口打开程度，使拇指与食指之间的夹角保持在自然张开范围。"))
        }
        if intonationScore < 80 {
            suggestions.append(L("加强左手按弦力度与品位定位训练，将音准偏差严格控制在 ±15 音分以内。"))
        }
        if articulationScore < 80 {
            suggestions.append(L("强化轮指与弹挑的均匀性练习，提升音符分离度与颗粒干净度，减少指甲刮弦杂音。"))
        }
        if rhythmScore < 80 {
            suggestions.append(L("演奏时保持速度稳定，有意识地避免无意识渐快或节奏松弛；可用节拍器辅助。"))
        }
        if postureStability < 80 {
            suggestions.append(L("关注演奏中段的力量与情绪稳定，减少手型与音高的无谓波动。"))
        }
        if techniqueCorrectness < 70 {
            suggestions.append(L("明确每种技法的手型与发力方式，减少误识别与技法切换的突兀。"))
        }

        // 乐曲维度专属建议
        switch piece {
        case .springRiver:
            if (pitchStability + timbreStability) / 2 < 80 {
                suggestions.append(L("《春江花月夜》注重旋律的连贯与气息感，练习时以连奏与揉弦让乐句如歌般流畅。"))
            }
            if dynContrast < 70 {
                suggestions.append(L("《春江花月夜》加强力度层次，用渐强渐弱表现月夜的起伏与意境。"))
            }
        case .ambush:
            if consistency < 80 {
                suggestions.append(L("《十面埋伏》需强化稳定而推进的节奏律动，让扫拂段落更具战场压迫感。"))
            }
            if dramaticContrast < 70 {
                suggestions.append(L("《十面埋伏》放大戏剧性对比，在激战场面用强奏、伏笔处收为弱奏以突出张力。"))
            }
        case .kingUnarm:
            if dramaticContrast < 70 {
                suggestions.append(L("《霸王卸甲》重在情绪的层层递进，可在英雄末路的段落用更明显的强弱对比烘托悲壮。"))
            }
            if (postureStability + noteCleanliness) / 2 < 80 {
                suggestions.append(L("《霸王卸甲》的慢板最考验气息，保持手型稳定与音符干净，让悲情更从容地流淌。"))
            }
        case .bigWaves, .yangChun, .zhaoJun, .pingSha, .lvYao, .tashikuergan, .caoyuan, .weiShui:
            if (pitchStability + timbreStability) / 2 < 80 {
                suggestions.append(L("注重旋律的连贯与气息感，练习时以连奏与揉弦让乐句如歌般流畅。"))
            }
            if dynContrast < 70 {
                suggestions.append(L("加强力度层次，用渐强渐弱突出乐曲的表现与意境。"))
            }
        case .etude:
            break
        }

        while suggestions.count < 5 {
            suggestions.append(L("针对弱项做专项慢练，先求准再求快，循序渐进。"))
        }
        suggestions = Array(suggestions.prefix(5))

        return CoachReport(
            piece: piece,
            duration: duration,
            date: Date(),
            overallScore: overall,
            grade: overallGrade(overall),
            dimensions: dimensions,
            details: details,
            pieceDimension: pieceDimension,
            pieceDetail: pieceDetail,
            errorPoints: errorPoints,
            suggestions: suggestions,
            intro: intro,
            emotionalComment: emotionalComment
        )
    }

    // MARK: - 工具

    private static func clamp(_ v: Double) -> Double { min(100, max(0, v)) }

    private static func gradeComment(_ score: Double) -> String {
        if score >= 90 { return L("优秀") }
        if score >= 80 { return L("良好") }
        if score >= 70 { return L("基本达标") }
        return L("未达标")
    }

    private static func overallGrade(_ score: Double) -> String {
        if score >= 85 { return L("本次演奏整体完成度较高，各维度表现均衡且亮点突出，继续保持。") }
        if score >= 75 { return L("整体表现良好，少数维度仍有提升空间，可针对性打磨。") }
        if score >= 65 { return L("基础扎实，但部分技法掌握度与演奏稳定性需重点加强。") }
        return L("尚处起步阶段，建议从基础技法、音准与节奏稳定性入手系统练习。")
    }

    private static func stddev(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}

private extension Array where Element == Double {
    var median: Double? {
        guard !isEmpty else { return nil }
        let sorted = sorted()
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        }
        return sorted[count / 2]
    }
}
