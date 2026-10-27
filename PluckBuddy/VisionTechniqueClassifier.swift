//
//  VisionTechniqueClassifier.swift
//  PluckBuddy
//
//  基于 Apple Vision 21 关键点的指法分类器，区分三类指法：
//    弹挑 (pluck)  —— 食指与拇指交替拨动，手腕基本不动、转动很小；
//                     残差只集中在食/拇（ndom≈2，噪声偶使第三指记 1 帧→ndom≈3）。
//    轮指 (roll)   —— 手腕几乎不动，食→中→无名→小→拇 依次主动运动，
//                     任意时刻仅一根手指在动。
//    扫弦 (sweep)  —— 大臂带动小臂斜划，整只手显著平移（手腕平移量是三类里最大的），
//                     食指触弦划过、手指主动跨弦。
//
//  判别核心：把每根指尖的运动分解为
//    · 刚性分量：由手腕平移 + 手腕旋转推得的“手整体带着手指动”的部分
//    · 残差分量：指尖实际位置与刚性预测之差 —— 这才是真正的“手指在主动动”
//  三类指法在「手腕平移量」上区分最干净（真机实测，归一化坐标/秒）：
//    扫弦 → 短窗手腕平移 0.18–0.55（整手大幅平移，手指也在动 → 残差偏高）
//    弹挑 → 平移仅 0.05–0.13（前臂/手腕小幅，主要靠食拇指尖动）
//    轮指 → 平移仅 0.06–0.11（手腕几乎不动，五指依次主动）
//  残差分量的分布也辅助判定：弹挑仅食/拇有残差，轮指五指依次出现残差。
//
//  抗噪设计（仿真验证了在真实 Vision 噪声下 ~100% 准确）：
//    1) 关键点先单极点低通平滑（smoothAlpha），滤掉高频抖动；
//    2) 残差再做时间 EMA（resEmaAlpha），抑制逐帧抖动；
//    3) 用“窗口内持续活跃帧占比”与“出现过的不同主导手指数”判定，
//       单帧噪声不会污染活跃集与切换计数。
//
//  阈值由 sim_vision_technique.py 在合成轨迹（含 Vision 级噪声）上网格搜索得到。
//

import CoreGraphics
import Foundation

/// 基于 Vision 21 关键点的指法分类器
final class VisionTechniqueClassifier {

    // MARK: - 对外结果
    struct Result {
        let technique: TechniqueType
        let confidence: Double
        let features: Features
    }

    /// 窗口聚合特征（调试用，可在日志里打印以校准真机）
    struct Features {
        var wristTransSpeed: Double = 0      // 手腕平移速度均值（归一化坐标/秒）
        var wristRotSpeed: Double = 0        // 手腕旋转角速度均值（rad/s）
        var meanResidual: Double = 0         // 五指残差速度均值（主动运动强度）
        var activeFingerSetSize: Int = 0     // 窗口内持续活跃手指数
        var fingerSwitchRate: Double = 0     // 主导手指切换率（次/秒，调试）
        var distinctDominant: Int = 0        // 窗口内出现过的不同主导手指数
    }

    // MARK: - 可调参数（仿真网格搜索回填）
    private let windowDuration: Double = 1.2
    private let maxWindowFrames: Int = 90
    private let minWindowFrames: Int = 8
    private let smoothAlpha: Double = 0.5       // 关键点低通平滑（逐帧）
    private let resEmaAlpha: Double = 0.25      // 残差时间 EMA（抑制逐帧抖动）
    private let residualThreshold: Double = 0.25 // 单指主动残差速度阈值
    private let activeFracMin: Double = 0.12    // 窗口内持续活跃帧占比门槛

    // 扫弦：大臂带动小臂斜划 → 手腕平移显著（这是与弹挑/轮指最干净的区分特征）。
    // 真机实测：扫弦期间短窗手腕平移 0.18–0.55（归一化坐标/秒），
    //          而弹挑仅 0.05–0.13、轮指仅 0.06–0.11 —— 平移量差一个数量级。
    // 旧假设“扫弦=整手刚性平移、残差≈0、ndom≤1”与真机不符：
    // 真实扫弦是食指触弦划过、手指主动跨弦，残差反而偏高（0.38–0.47）、ndom≈2。
    // 故扫弦只认“短窗平移足够大且不像轮指（ndom<4）”，不再卡残差/ndom。
    private let sweepTransMin: Double = 0.18
    // 用短窗（0.5s）算平移均值，避免 1.2s 长窗把一次性扫弦稀释到阈值以下。
    private let shortWindowFrames: Int = 15

    // 弹挑：手指在动、但既不是大平移（扫弦）也不是五指轮动（轮指）。
    // 真机实测弹挑手腕转动很小（rot≈0.3），不能用“旋转角速度大”做判定，
    // 否则直接漏判；这里改为“低平移 + 有主动手指（ndom 1~3）”即判弹挑。
    // pluckResMin 滤掉静止手（残差近 0）避免误报。
    private let pluckResMin: Double = 0.08

    // 轮指：五指依次主动 → 主导手指数 ≥ 4（顺序经过多指），手腕平移/旋转都小。
    // 注意 ndom 必须 ≥ 4：弹挑只动食/拇（ndom≈2），偶尔第三指因残差噪声被记 1 帧
    // 会变成 ndom≈3，若把轮指门槛设在 3 会把弹挑误判成轮指（见真机日志）。
    private let rollActiveMin: Int = 4
    private let rollRotMax: Double = 1.1
    private let rollTransMax: Double = 0.55

    // MARK: - 状态
    private struct Frame {
        let t: Double
        let wTrans: Double
        let wRot: Double
        let resEMA: [Double]   // 每指主动残差速度 EMA（5）
        let active: [Bool]
        let dominant: Int      // -1 表示无主动手指
    }

    private var window: [Frame] = []
    private var prevWrist: CGPoint?
    private var prevTips: [String: CGPoint] = [:]
    private var prevAngle: Double?
    private var prevT: Double = 0
    private var sm: [String: CGPoint] = [:]   // 平滑后的关键点
    private var resEMA: [Double] = [0,0,0,0,0]

    private let tipNames = ["thumbTip", "indexTip", "middleTip", "ringTip", "littleTip"]

    func reset() {
        window.removeAll()
        prevWrist = nil
        prevTips.removeAll()
        prevAngle = nil
        prevT = 0
        sm.removeAll()
        resEMA = [0,0,0,0,0]
    }

    // MARK: - 主入口
    /// 喂入一帧 21 关键点 + 时间戳（秒），返回当前分类结果
    func push(keypoints: [HandKeypoint], timestamp: TimeInterval) -> Result {
        guard let wristRaw = point(named: "wrist", in: keypoints) else {
            return Result(technique: .unknown, confidence: 0, features: Features())
        }
        let kp = smooth(keypoints)
        guard let wrist = point(named: "wrist", in: kp) else {
            return Result(technique: .unknown, confidence: 0, features: Features())
        }
        let tips = tipNames.map { point(named: $0, in: kp) }
        let middle = point(named: "middleTip", in: kp)
        let angle = handAngle(wrist: wrist, middle: middle)
        let dt = prevWrist == nil ? 0 : max(0, timestamp - prevT)

        if dt > 0, let pw = prevWrist, let pa = prevAngle {
            let wTrans = distance(wrist, pw) / dt
            var dTheta = angle - pa
            while dTheta > .pi { dTheta -= 2 * .pi }
            while dTheta < -.pi { dTheta += 2 * .pi }
            let wRot = abs(dTheta) / dt

            var inst = [Double](repeating: 0, count: 5)
            for f in 0..<5 {
                guard let cur = tips[f], let prev = prevTips[tipNames[f]] else { continue }
                // 刚性预测：上一帧指尖相对上一帧手腕，经旋转后落到当前手腕处
                let rx = Double(prev.x - pw.x)
                let ry = Double(prev.y - pw.y)
                let gx = Double(wrist.x) + (rx * cos(dTheta) - ry * sin(dTheta))
                let gy = Double(wrist.y) + (rx * sin(dTheta) + ry * cos(dTheta))
                let dx = Double(cur.x) - gx
                let dy = Double(cur.y) - gy
                inst[f] = hypot(dx, dy) / dt
            }
            // 残差时间 EMA：抑制逐帧抖动，保留真实主动运动
            for f in 0..<5 {
                resEMA[f] = resEmaAlpha * inst[f] + (1 - resEmaAlpha) * resEMA[f]
            }
            let active = resEMA.map { $0 > residualThreshold }
            var dom = -1, best = -1.0
            for f in 0..<5 where active[f] && resEMA[f] > best {
                best = resEMA[f]; dom = f
            }
            window.append(Frame(t: timestamp, wTrans: wTrans, wRot: wRot, resEMA: resEMA, active: active, dominant: dom))
        } else {
            // 首帧：仅记录，给出零特征
            let zeros = [Double](repeating: 0, count: 5)
            window.append(Frame(t: timestamp, wTrans: 0, wRot: 0, resEMA: zeros, active: [Bool](repeating: false, count: 5), dominant: -1))
        }

        trimWindow()
        prevWrist = wrist
        prevTips = Dictionary(uniqueKeysWithValues: zip(tipNames, tips.compactMap { $0 }))
        prevAngle = angle
        prevT = timestamp
        return classify()
    }

    // MARK: - 窗口聚合 + 决策
    private func classify() -> Result {
        guard window.count >= minWindowFrames else {
            return Result(technique: .unknown, confidence: 0, features: Features())
        }
        let duration = max(window.last!.t - window.first!.t, 1e-3)

        let meanTrans = window.map { $0.wTrans }.reduce(0, +) / Double(window.count)
        let meanRot = window.map { $0.wRot }.reduce(0, +) / Double(window.count)
        let meanRes = window.map { $0.resEMA.reduce(0, +) / 5.0 }.reduce(0, +) / Double(window.count)

        // 持续活跃手指：窗口内活跃帧占比超过门槛才算（消除单帧噪声抖动）
        var activeFrac = [Double](repeating: 0, count: 5)
        for fr in window {
            for i in 0..<5 where fr.active[i] { activeFrac[i] += 1 }
        }
        for i in 0..<5 { activeFrac[i] /= Double(window.count) }
        let activeSet = Set((0..<5).filter { activeFrac[$0] >= activeFracMin })

        // 主导手指切换（调试用）
        var switches = 0, last = -1
        for fr in window {
            if fr.dominant >= 0 && last >= 0 && fr.dominant != last { switches += 1 }
            if fr.dominant >= 0 { last = fr.dominant }
        }
        let switchRate = Double(switches) / duration

        // 窗口内出现过的不同主导手指数：轮指≈5、弹挑≈2、扫弦≈0（比活跃集更稳健）
        let distinctDominant = Set(window.map { $0.dominant }.filter { $0 >= 0 }).count

        let feats = Features(wristTransSpeed: meanTrans, wristRotSpeed: meanRot,
                             meanResidual: meanRes,
                             activeFingerSetSize: activeSet.count,
                             fingerSwitchRate: switchRate,
                             distinctDominant: distinctDominant)

        // 短窗手腕平移（0.5s）：专用于捕捉一次性扫弦，避免被长窗稀释。
        let shortCount = min(window.count, shortWindowFrames)
        let shortTrans = window.suffix(shortCount).map { $0.wTrans }.reduce(0, +) / Double(shortCount)

        // —— 决策树（阈值按真机实测重新标定）——
        // 1) 扫弦：短窗平移显著（0.18–0.55，远超弹挑 0.05–0.13 / 轮指 0.06–0.11），
        //    且不像轮指（ndom<4）。真机扫弦残差偏高、ndom≈2，不再卡残差/ndom。
        if shortTrans >= sweepTransMin, distinctDominant < rollActiveMin {
            return Result(technique: .sweep,
                          confidence: clamp01((shortTrans - sweepTransMin) / 0.4 * 0.4 + 0.6),
                          features: feats)
        }
        // 2) 轮指：五指依次主动 → 主导手指数 ≥ 4，手腕平移/旋转都小。
        //    必须 ≥ 4 才能和弹挑（ndom≈2~3）区分，否则弹挑会被误判成轮指。
        if distinctDominant >= rollActiveMin, meanRot < rollRotMax, meanTrans < rollTransMax {
            return Result(technique: .roll,
                          confidence: clamp01((Double(distinctDominant) - Double(rollActiveMin)) * 0.1 + 0.6),
                          features: feats)
        }
        // 3) 弹挑：手指在动、但既不是大平移（扫弦）也不是五指轮动（轮指）。
        //    真机实测弹挑手腕转动很小（rot≈0.3），故不再要求旋转角速度大；
        //    只要低平移、低旋转、有主动手指（ndom≥1）且残差超过静止阈值即判弹挑。
        if meanTrans < rollTransMax, meanRot < rollRotMax, distinctDominant >= 1, meanRes > pluckResMin {
            return Result(technique: .pluck,
                          confidence: clamp01(0.6 + min(meanRes, 0.4) * 0.5),
                          features: feats)
        }
        return Result(technique: .unknown, confidence: 0, features: feats)
    }

    private func trimWindow() {
        while window.count > maxWindowFrames { window.removeFirst() }
        while let first = window.first, window.last!.t - first.t > windowDuration {
            window.removeFirst()
        }
    }

    // MARK: - 几何工具
    private func point(named name: String, in kps: [HandKeypoint]) -> CGPoint? {
        kps.first { $0.name == name }?.location
    }

    private func handAngle(wrist: CGPoint, middle: CGPoint?) -> Double {
        guard let m = middle else { return 0 }
        return atan2(Double(m.y - wrist.y), Double(m.x - wrist.x))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }

    private func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// 关键点单极点低通平滑（逐帧），抑制 Vision 高频抖动
    private func smooth(_ kps: [HandKeypoint]) -> [HandKeypoint] {
        kps.map { kp in
            if let prev = sm[kp.name] {
                let x = smoothAlpha * kp.location.x + (1 - smoothAlpha) * prev.x
                let y = smoothAlpha * kp.location.y + (1 - smoothAlpha) * prev.y
                let out = CGPoint(x: x, y: y)
                sm[kp.name] = out
                return HandKeypoint(name: kp.name, location: out, confidence: kp.confidence)
            } else {
                sm[kp.name] = kp.location
                return kp
            }
        }
    }
}
