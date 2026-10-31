//
//  TechniqueCoachViewModel.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/7/29.
//

import Foundation
import SwiftUI
import AVFoundation
import Vision
import Combine
import CoreML

@MainActor
class TechniqueCoachViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 是否正在分析
    @Published var isAnalyzing = false
    
    /// 检测到的技法类型
    @Published var detectedTechnique: TechniqueType = .unknown
    
    /// 当前手部姿势数据
    @Published var handPose: HandPoseData?
    
    /// 是否检测到用户左手（用于界面显示双手识别状态）
    @Published var leftHandDetected: Bool = false
    /// 是否检测到用户右手（指法分类以右手为准）
    @Published var rightHandDetected: Bool = false
    
    /// 姿势评估结果
    @Published var currentEvaluation: PostureEvaluation?
    
    /// 状态消息
    @Published var statusMessage = L("准备开始")
    
    /// 摄像头权限状态
    @Published var cameraPermissionGranted = false
    
    /// Core ML 声音分类给出的当前声音类别（中文，便于直接展示）
    @Published var soundSceneLabel = "未开始"
    
    /// Core ML 判定当前声音属于琵琶的概率（0~1，最近三次平滑）
    @Published var pipaConfidence: Double = 0
    
    /// 当前听到的是否为琵琶声
    @Published var isPipaSoundDetected = false
    
    /// 分析会话时长
    @Published var sessionDuration: TimeInterval = 0
    
    /// 手部骨骼覆盖图像（用于显示在视频上）
    @Published var skeletonOverlayImage: UIImage?
    
    /// 当前选择的练习曲目（默认「练习曲」）
    @Published var selectedPiece: PracticePiece = .etude
    
    /// 演奏结束后生成的分析评价报告
    @Published var report: CoachReport?
    
    /// 报告因未听到琵琶声 / 演奏证据不足而无法生成时，弹框提示用户的原因；为 nil 则不弹框
    @Published var reportBlockedReason: String?
    
    // MARK: - Internal Properties
    
    /// 视频捕获管理器（供 View 访问预览图层）
    var videoCapture: VideoCaptureManager?
    
    // MARK: - Private Properties
    
    private var handPoseAnalyzer = HandPoseAnalyzer()
    private var motionFeatureExtractor = MotionFeatureExtractor()
    private var techniqueClassifier = TechniqueClassifier()
    /// 基于 Vision 21 关键点的指法分类器（残差分解 + 决策树），用于与旧规则法 A/B
    private var visionTechniqueClassifier = VisionTechniqueClassifier()
    /// true：用 Vision 分类器驱动判定；false：退回旧规则法。便于真机 A/B 校准。
    private let useVisionClassifier = true
    
    private var rollEvaluator = RollPostureEvaluator()
    private var sweepEvaluator = SweepPostureEvaluator()
    private var pluckEvaluator = PluckPostureEvaluator()
    
    /// 端侧音频分析器：复用声音分类同一路采样，演奏结束后生成评价报告
    private let audioAnalyzer = SessionAudioAnalyzer()
    
    /// Core ML 声音分类引擎（加载 PipaSoundClassifier）
    private let soundClassifier = PipaSoundClassifierEngine()
    
    /// 声音分类是否已产出过结果——没结果前不做门控，避免开局就把画面判死
    private var hasSoundResult = false

    /// 「持续听到琵琶声」的判定参数。
    /// 模型窗口 15600 @16 kHz ≈ 0.98 秒、重叠一半，即约每 0.49 秒出一个分类结果；
    /// 连续 3 次判为琵琶声 ≈ 持续 1.5 秒以上，足以排除敲桌子、说话、清嗓子等瞬态。
    private static let minConsecutivePipaWindows = 3

    /// 累计判据：整场练习里判为琵琶声的窗口总数下限。
    /// 只看「最长连续段」会误杀慢板乐曲——乐句本身短于 1.5 秒时凑不满 3 个连续窗，
    /// 但整首曲子明明弹得很完整。所以再加一条通道：累计够多的琵琶声窗口也算通过。
    /// 8 个窗口约合 4 秒实际琵琶声，敲桌子这类瞬态凑不到这个量。
    private static let minTotalPipaWindows = 8

    /// 当前连续判为琵琶声的分类窗口数
    private var consecutivePipaWindows = 0
    /// 本次会话里最长的一段连续琵琶声（窗口数）
    private var longestPipaRun = 0
    /// 本次会话里累计判为琵琶声的窗口总数
    private var totalPipaWindows = 0
    /// 最近的分类窗口判定结果（true = 琵琶声），用于实时门的累计判据
    private var recentPipaFlags: [Bool] = []
    
    // MARK: - 技法去抖
    /// 分类器在中间帧会抖动（同一段演奏在「轮指/弹挑/扫弦/未识别」之间跳），
    /// 直接把每帧结果抛给界面会导致核心要求面板不停切换。
    /// 这里用「近期窗口众数」判定：统计最近若干非 unknown 帧里出现最多的技法，
    /// 只要它占过半（扫弦瞬时动作门槛更低）即提交，从而抗两类间的抖动——
    /// 否则一旦轮指先 commit，弹挑就再难凑满连续 6 帧来翻盘，UI 会卡死在轮指。
    private var recentTechniques: [TechniqueType] = []
    private let techniqueWindowSize = 9   // 约 0.3 秒（按 30 fps 计），缩小窗口以降低 UI 滞后
    private var coachDebugFrameCounter = 0   // 调试日志限频计数（虎口角/手腕速度分布，待真机标定）
    
    private var startTime: Date?
    private var durationTimer: Timer?
    
    // MARK: - Initialization
    
    init() {
        print("🎥 智能指法教练初始化")
    }
    
    // MARK: - Lifecycle
    
    /// 开始视频分析
    func startAnalysis() async {
        print("🎥 开始视频分析...")
        
        // 1. 请求摄像头权限
        let authorized = await requestCameraPermission()
        guard authorized else {
            print("❌ 摄像头权限被拒绝")
            statusMessage = L("需要摄像头权限")
            return
        }
        
        cameraPermissionGranted = true
        print("✅ 摄像头权限已授予")

        // 开始新一轮分析前清空上一次的评价报告与分析器累积数据
        audioAnalyzer.reset()
        motionFeatureExtractor.reset()
        techniqueClassifier.reset()
        visionTechniqueClassifier.reset()
        report = nil

        // 持续琵琶声的连续计数也要清零，否则上一轮的记录会让本轮开局就通过判定
        consecutivePipaWindows = 0
        longestPipaRun = 0
        totalPipaWindows = 0
        recentPipaFlags.removeAll()
        isPipaSoundDetected = false
        
        // 2. 初始化视频捕获
        videoCapture = VideoCaptureManager()
        
        videoCapture?.onFrameCaptured = { [weak self] pixelBuffer in
            Task { @MainActor in
                await self?.processFrame(pixelBuffer)
            }
        }
        
        // 3. 启动捕获
        do {
            try videoCapture?.startCapture()
            
            isAnalyzing = true
            startTime = Date()
            statusMessage = L("请开始弹奏")
            
            // 启动时长计时器
            startDurationTimer()
            
            print("✅ 视频捕获已启动")
            
            // 🧪 临时测试代码：模拟技法识别
            // startSimulatedDetection()  // ⚠️ 已禁用模拟数据，等待真实算法实现
            
            // 4. 启动 Core ML 声音分类，与视觉通道交叉验证
            await startSoundClassification()
            
        } catch {
            print("❌ 启动捕获失败: \(error.localizedDescription)")
            statusMessage = L("摄像头启动失败")
        }
    }
    
    /// 停止视频分析
    func stopAnalysis() {
        print("⏹️ 停止视频分析")
        
        // 清除上一次可能的弹框标志
        reportBlockedReason = nil
        
        videoCapture?.stopCapture()
        isAnalyzing = false
        
        // 停止声音分类
        soundClassifier.stop()
        hasSoundResult = false
        soundSceneLabel = "已停止"

        // 停止计时器
        stopDurationTimer()

        if let start = startTime {
            sessionDuration = Date().timeIntervalSince(start)
            print("   - 分析时长: \(String(format: "%.1f", sessionDuration))秒")
        }

        // 「持续听到琵琶声」规则：本次会话里必须真正在弹琵琶。
        // 整段练习都只有零散瞬态（敲桌子、清嗓子、背景音）时一律视为没听到琵琶声，
        // 不出报告——宁可不给分，也不要给一个建立在误判上的高分。
        //
        // 两条通道任一成立即通过：
        //   ① 连续通道：存在一段连续的琵琶声（≥3 个分类窗，约 1.5 秒）；
        //   ② 累计通道：整场累计判为琵琶声的窗口数 ≥8（约 4 秒实际琵琶声）。
        // ② 是为乐曲停顿兜底的——慢板曲目的乐句往往短于 1.5 秒，
        // 乐句之间的休止会打断连续段，只看连续就会把完整演奏误判成没在弹。
        let continuousOK = longestPipaRun >= Self.minConsecutivePipaWindows
        let cumulativeOK = totalPipaWindows >= Self.minTotalPipaWindows
        let sustainedPipaHeard = continuousOK || cumulativeOK
        print("🎼 持续琵琶声判定：最长连续 \(longestPipaRun) 窗（需 ≥ \(Self.minConsecutivePipaWindows)）| 累计 \(totalPipaWindows) 窗（需 ≥ \(Self.minTotalPipaWindows)）→ \(sustainedPipaHeard ? "通过" : "不通过")")

        // 没有足够的琵琶声音与手型证据时不生成分数，避免静音也得到 70+。
        guard sustainedPipaHeard && audioAnalyzer.hasSufficientEvidence(duration: sessionDuration) else {
            report = nil
            reportBlockedReason = L("未检测到持续的琵琶声，无法生成评价报告。请连续弹奏一段后再试。")
            statusMessage = L("未听到持续的琵琶声，请连续弹奏一段后再试")
            detectedTechnique = .unknown
            handPose = nil
            leftHandDetected = false
            rightHandDetected = false
            currentEvaluation = nil
            recentTechniques.removeAll()
            motionFeatureExtractor.reset()
            techniqueClassifier.reset()
        visionTechniqueClassifier.reset()
            print("⚠️ 未听到持续的琵琶声（或有效演奏数据不足），本次不生成评分报告")
            return
        }

        // 用累积的视频手型 + 音频数据生成分析评价报告
        let generated = audioAnalyzer.finalize(piece: selectedPiece, duration: sessionDuration)
        report = generated
        // 写入「我的成绩 - 历史」
        CoachReportStore.shared.append(generated)
        print("📊 已生成分析评价报告，综合得分 \(String(format: "%.1f", generated.overallScore))")
        
        // 重置状态
        detectedTechnique = .unknown
        handPose = nil
        leftHandDetected = false
        rightHandDetected = false
        currentEvaluation = nil
        statusMessage = L("分析已停止")
        
        // 重置技法去抖计数，下次开始时重新累积
        recentTechniques.removeAll()
        motionFeatureExtractor.reset()
        techniqueClassifier.reset()
        visionTechniqueClassifier.reset()
    }
    
    // MARK: - Frame Processing
    
    /// 处理每一帧视频
    private func processFrame(_ pixelBuffer: CVPixelBuffer) async {
        // 1. 检测双手（最多 2 只）
        let hands = await handPoseAnalyzer.analyzeHands(in: pixelBuffer)
        guard !hands.isEmpty else {
            // 未检测到手部
            if detectedTechnique != .unknown {
                print("⚠️ 手部检测丢失")
            }
            statusMessage = L("未检测到手部")
            skeletonOverlayImage = nil  // 清空骨骼图像
            leftHandDetected = false
            rightHandDetected = false
            return
        }

        // 记录左右手识别状态（供界面显示双手均已检测）
        leftHandDetected = hands.contains { $0.hand == .left }
        rightHandDetected = hands.contains { $0.hand == .right }

        // ✨ 生成双手骨骼覆盖图像（双手都画）
        generateSkeletonOverlay(from: hands, pixelBuffer: pixelBuffer)

        // 指法分类以右手为准（用户明确要求：指法分类依据右手）
        guard let rightHand = hands.first(where: { $0.hand == .right }) else {
            statusMessage = L("未检测到右手（指法分析依据右手）")
            return
        }
        handPose = rightHand

        // 2. 提取右手运动特征
        let features = motionFeatureExtractor.extractFeatures(from: rightHand)

        // 3. 分类技法
        // 旧规则法（保留做 A/B 对照）
        let ruleTechnique = techniqueClassifier.classify(features: features)
        // Vision 21 点分类器（残差分解 + 决策树）
        let visionResult = visionTechniqueClassifier.push(keypoints: rightHand.keypoints, timestamp: Date().timeIntervalSince1970)
        let technique: TechniqueType = useVisionClassifier ? visionResult.technique : ruleTechnique
        // 调试：打印 Vision 分类特征，便于真机校准阈值
        if visionResult.technique != .unknown {
            print("🔬 Vision 分类: \(visionResult.technique.rawValue) (conf=\(String(format: "%.2f", visionResult.confidence)), trans=\(String(format: "%.2f", visionResult.features.wristTransSpeed)), rot=\(String(format: "%.2f", visionResult.features.wristRotSpeed)), res=\(String(format: "%.2f", visionResult.features.meanResidual)), ndom=\(visionResult.features.distinctDominant))")
        }
        // A/B 对照：两者不一致时记录，帮助判断 Vision 分类器是否优于旧规则法
        if ruleTechnique != visionResult.technique {
            print("⚖️ 规则法=\(ruleTechnique.rawValue) vs Vision=\(visionResult.technique.rawValue)")
        }

        // 3.5 音频侧门控（仅影响评分，不阻断视觉显示）
        // 视觉通道（Vision 21 点）的技法判定始终提交到 detectedTechnique，
        // 保证前端“检测到：”实时刷新；只有声音分类确认是琵琶声时，
        // 才计算并录入姿势评分，避免“不发声也拿高分”。
        // 之前这里直接 return 会丢弃视觉判定，导致音频分类一旦判非琵琶声，
        // 前端技法标签就卡死不动（与“后台日志准但 UI 不刷新”的现象一致）。
        let audioGatePassed = !hasSoundResult || isPipaSoundDetected

        // 3.6 技法去抖：近期窗口众数（仅统计非 unknown 帧）
        // 用「最近 N 帧出现最多的技法」提交，而非「连续 N 帧相同」，
        // 这样分类器在弹挑/轮指之间抖动时，UI 跟随真实占优的技法，
        // 不会因轮指先 commit、弹挑凑不满连续帧而卡死在轮指。
        if technique != .unknown {
            recentTechniques.append(technique)
            if recentTechniques.count > techniqueWindowSize {
                recentTechniques.removeFirst()
            }
        }
        let counts = recentTechniques.reduce(into: [TechniqueType: Int]()) { $0[$1, default: 0] += 1 }
        let (mode, modeCount): (TechniqueType, Int)
        if let m = counts.max(by: { $0.value < $1.value }) {
            (mode, modeCount) = m
        } else {
            (mode, modeCount) = (.unknown, 0)
        }
        // 扫弦是一次性瞬态动作，门槛更低（约 3/12 即提交）；
        // 其余持续动作需占窗口过半，避免两类抖动或单帧噪声误判。
        let requiredStable = (mode == .sweep) ? 3 : (techniqueWindowSize / 2 + 1)
        let stableTechnique = (modeCount >= requiredStable) ? mode : detectedTechnique

        // 每个有效视频帧都记录（包括 unknown），报告中的“技法识别率”才是真实比例；
        // 旧逻辑只记录已识别帧，会让该指标几乎恒为 100%。
        audioAnalyzer.recordTechnique(stableTechnique)

        // 技法改变时打印日志
        if stableTechnique != .unknown && stableTechnique != detectedTechnique {
            print("🎯 检测到技法: \(stableTechnique.rawValue)")
            detectedTechnique = stableTechnique
        } else if stableTechnique == .unknown && detectedTechnique != .unknown {
            print("⚠️ 技法识别丢失")
            detectedTechnique = .unknown
        }

        // 4. 评估姿势（基于右手）—— 受音频门控：非琵琶声时不评分、不录入报告
        if stableTechnique != .unknown {
            if audioGatePassed {
                currentEvaluation = evaluatePosture(
                    technique: stableTechnique,
                    features: features
                )

                // 把真实视频手型评估喂给报告分析器（后续与音频分析融合生成评价报告）
                audioAnalyzer.recordPosture(evaluation: currentEvaluation!)

                // 🔬 调试：打印真实虎口角与手腕速度分布，供真机标定阈值（条目 9、10）
                coachDebugFrameCounter += 1
                if coachDebugFrameCounter % 30 == 0 {
                    let ws = hypot(Double(features.wristVelocity.dx), Double(features.wristVelocity.dy))
                    let avgFinger = features.fingerVelocities.map { hypot(Double($0.dx), Double($0.dy)) }.reduce(0, +) / Double(features.fingerVelocities.count)
                    print("📐 虎口角: \(String(format: "%.1f", features.tigerMouthAngle))°  手腕速度: \(String(format: "%.3f", ws))  指尖均速: \(String(format: "%.3f", avgFinger))")
                }

                updateStatusMessage()
            } else {
                currentEvaluation = nil
                statusMessage = L("未听到琵琶声（") + L(soundSceneLabel) + L("）— 技法仍按视觉显示")
            }
        }
    }
    
    // MARK: - Skeleton Overlay Generation

    /// 生成双手骨骼覆盖图像（每只手按左右用不同颜色，并在手腕处标注「L / R」）
    private func generateSkeletonOverlay(from hands: [HandPoseData], pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let imageSize = CGSize(width: width, height: height)

        skeletonOverlayImage = drawHandsSkeleton(hands: hands, imageSize: imageSize)
    }

    /// 在单个绘图上下文里画出所有被检测到的手
    private func drawHandsSkeleton(hands: [HandPoseData], imageSize: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }

        context.setLineCap(.round)
        context.setLineJoin(.round)

        for pose in hands {
            // 右手用粉、左手用青，便于区分用户左右手
            let stroke = pose.hand == .right ? UIColor.systemPink : UIColor.systemTeal
            drawOneHandSkeleton(pose: pose, context: context, imageSize: imageSize, stroke: stroke)
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }

    /// 画出单只手的骨架、指尖与手腕，并在手腕旁标注「L / R」
    private func drawOneHandSkeleton(
        pose: HandPoseData,
        context: CGContext,
        imageSize: CGSize,
        stroke: UIColor
    ) {
        context.setStrokeColor(stroke.cgColor)
        context.setLineWidth(2.5)

        func findPoint(_ name: String) -> CGPoint? {
            pose.keypoints.first(where: { $0.name == name })?.location
        }

        // 1) 5 条指骨连线（每个手指 4 个关节连成一根）
        let fingerBones: [(String, String, String, String)] = [
            ("thumbCMC",   "thumbMP",   "thumbIP",   "thumbTip"),
            ("indexMCP",   "indexPIP",  "indexDIP",  "indexTip"),
            ("middleMCP",  "middlePIP", "middleDIP", "middleTip"),
            ("ringMCP",    "ringPIP",   "ringDIP",   "ringTip"),
            ("littleMCP",  "littlePIP", "littleDIP", "littleTip"),
        ]
        for (a, b, c, d) in fingerBones {
            let raw = [findPoint(a), findPoint(b), findPoint(c), findPoint(d)]
            var lastUI: CGPoint?
            for p in raw {
                guard let p = p else { continue }
                let ui = convertVisionPointToUIKit(p, imageSize: imageSize)
                if let last = lastUI {
                    context.move(to: last)
                    context.addLine(to: ui)
                }
                lastUI = ui
            }
        }

        // 2) 手掌：手腕 → 各指 MCP/CMC 的连线
        if let wristRaw = findPoint("wrist") {
            let wristUI = convertVisionPointToUIKit(wristRaw, imageSize: imageSize)
            let palmRoots = ["thumbCMC", "indexMCP", "middleMCP", "ringMCP", "littleMCP"]
            for name in palmRoots {
                if let p = findPoint(name) {
                    let ui = convertVisionPointToUIKit(p, imageSize: imageSize)
                    context.move(to: wristUI)
                    context.addLine(to: ui)
                }
            }
        }
        context.strokePath()

        // 3) 5 指尖彩色大圆（与旧版配色一致）
        let tipStyles: [(String, UIColor, CGFloat)] = [
            ("thumbTip",  .systemPink,   10),
            ("indexTip",  .systemGreen,  10),
            ("middleTip", .systemOrange, 10),
            ("ringTip",   .systemYellow, 10),
            ("littleTip", .systemPurple, 10),
        ]
        for (name, color, r) in tipStyles {
            if let p = findPoint(name) {
                drawCircle(at: p, context: context, imageSize: imageSize, color: color, radius: r)
            }
        }

        // 4) 手腕：用本手配色圆（左手青 / 右手粉），直观区分左右
        if let wristRaw = findPoint("wrist") {
            drawCircle(at: wristRaw, context: context, imageSize: imageSize, color: stroke, radius: 8)
        }

        // 5) 15 个中间关节白色小圆（CMC / MP / IP / MCP / PIP / DIP）
        let jointNames = [
            "thumbCMC",  "thumbMP",  "thumbIP",
            "indexMCP",  "indexPIP", "indexDIP",
            "middleMCP", "middlePIP","middleDIP",
            "ringMCP",   "ringPIP",  "ringDIP",
            "littleMCP", "littlePIP","littleDIP",
        ]
        let jointColor = UIColor.white.withAlphaComponent(0.85)
        for name in jointNames {
            if let p = findPoint(name) {
                drawCircle(at: p, context: context, imageSize: imageSize, color: jointColor, radius: 4)
            }
        }

        // 6) 在手腕旁标注「L / R」
        if let wristRaw = findPoint("wrist") {
            let ui = convertVisionPointToUIKit(wristRaw, imageSize: imageSize)
            let label = pose.hand == .right ? "R" : "L"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: stroke
            ]
            // 右手标注放腕点右侧；左手放左侧，避免压在手心/指关节上被遮住
            let labelSize = (label as NSString).size(withAttributes: attrs)
            let offsetX: CGFloat = pose.hand == .right
                ? 14
                : -14 - labelSize.width
            (label as NSString).draw(
                at: CGPoint(x: ui.x + offsetX, y: ui.y - 26),
                withAttributes: attrs
            )
        }
    }
    
    /// 将 Vision 坐标系转换为 UIKit 坐标系
    private func convertVisionPointToUIKit(_ point: CGPoint, imageSize: CGSize) -> CGPoint {
        return CGPoint(
            x: point.x * imageSize.width,
            y: (1 - point.y) * imageSize.height
        )
    }
    
    /// 在指定位置绘制圆形
    private func drawCircle(at point: CGPoint, context: CGContext, imageSize: CGSize, color: UIColor, radius: CGFloat) {
        let uiPoint = convertVisionPointToUIKit(point, imageSize: imageSize)
        context.setFillColor(color.cgColor)
        let rect = CGRect(
            x: uiPoint.x - radius,
            y: uiPoint.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fillEllipse(in: rect)
    }
    
    /// 将 HandPoseData 转换为 HandKeypoint 数组
    private func convertToKeypoints(from pose: HandPoseData) -> [HandKeypoint] {
        var keypoints: [HandKeypoint] = []
        
        // 从 HandPoseData 提取手指尖端和手腕位置
        let fingerTips: [(CGPoint?, String)] = [
            (pose.wrist, "wrist"),
            (pose.thumbTip, "thumbTip"),
            (pose.indexTip, "indexTip"),
            (pose.middleTip, "middleTip"),
            (pose.ringTip, "ringTip"),
            (pose.littleTip, "littleTip")
        ]
        
        // 提取每个有效的关键点
        for (location, name) in fingerTips {
            if let loc = location {
                keypoints.append(HandKeypoint(
                    name: name,
                    location: loc,
                    confidence: Double(pose.confidence)
                ))
            }
        }
        
        return keypoints
    }
    
    // MARK: - Posture Evaluation
    
    /// 评估姿势
    private func evaluatePosture(
        technique: TechniqueType,
        features: HandMotionFeatures
    ) -> PostureEvaluation {
        switch technique {
        case .roll:
            return rollEvaluator.evaluate(features: features)
            
        case .sweep:
            return sweepEvaluator.evaluate(features: features)
            
        case .pluck:
            return pluckEvaluator.evaluate(features: features)
            
        case .unknown:
            return PostureEvaluation(
                overallScore: 0,
                aspects: [],
                suggestions: [L("请开始弹奏")]
            )
        }
    }
    
    // MARK: - UI Updates
    
    private func updateStatusMessage() {
        guard let evaluation = currentEvaluation else {
            statusMessage = L("分析中...")
            return
        }
        
        let score = evaluation.overallScore
        
        if score >= 90 {
            statusMessage = L("🌟 姿势优秀！")
        } else if score >= 80 {
            statusMessage = L("👍 姿势良好！")
        } else if score >= 70 {
            statusMessage = L("👌 继续保持！")
        } else if score >= 60 {
            statusMessage = L("💪 注意调整姿势")
        } else {
            statusMessage = L("⚠️ 需要改进姿势")
        }
    }
    
    // MARK: - Timer Management
    
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.startTime else { return }
                self.sessionDuration = Date().timeIntervalSince(start)
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
    
    // MARK: - Simulated Detection (临时测试功能)
    
    /// 启动模拟技法检测
    /// 注意：这是临时测试代码，用于在 Vision 检测实现前验证 UI 功能
    private func startSimulatedDetection() {
        print("🧪 [测试模式] 启动模拟技法检测")
        print("   2秒后将自动模拟检测到\"轮指\"技法")
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒延迟
            
            await MainActor.run {
                guard isAnalyzing else { return }
                
                // 模拟检测到轮指
                detectedTechnique = .roll
                print("🧪 [测试模式] 模拟检测到技法: \(detectedTechnique.rawValue)")
                
                // 模拟评估结果
                currentEvaluation = PostureEvaluation(
                    overallScore: 85,
                    aspects: [
                        EvaluationAspect(
                            category: .handShape,
                            score: 90,
                            description: L("手型自然")
                        ),
                        EvaluationAspect(
                            category: .tigerMouth,
                            score: 80,
                            description: L("虎口自然")
                        ),
                        EvaluationAspect(
                            category: .rhythm,
                            score: 85,
                            description: L("节奏稳定")
                        )
                    ],
                    suggestions: [L("保持当前节奏"), L("注意手指独立性")]
                )
                
                updateStatusMessage()
                print("🧪 [测试模式] 滚动字幕应该已显示")
            }
        }
    }
    
    /// 手动设置技法（供测试菜单使用）
    func setTechnique(_ technique: TechniqueType) {
        print("🧪 [测试模式] 手动切换技法: \(technique.rawValue)")
        detectedTechnique = technique
        
        if technique != .unknown {
            // 根据不同技法提供不同的模拟评分
            let score: Double
            switch technique {
            case .roll:
                score = 85
            case .sweep:
                score = 78
            case .pluck:
                score = 82
            case .unknown:
                score = 0
            }
            
            currentEvaluation = PostureEvaluation(
                overallScore: score,
                aspects: [
                    EvaluationAspect(
                        category: .handShape,
                        score: score + 5,
                        description: L("手型") + (score > 80 ? L("优秀") : L("良好"))
                    ),
                    EvaluationAspect(
                        category: .rhythm,
                        score: score,
                        description: L("节奏") + (score > 80 ? L("稳定") : L("一般"))
                    )
                ],
                suggestions: [L("继续保持")]
            )
            
            updateStatusMessage()
        } else {
            currentEvaluation = nil
            statusMessage = L("请开始弹奏")
        }
    }
    
    // MARK: - Core ML 声音分类
    
    /// 启动端侧声音分类，为技法识别提供音频侧佐证
    private func startSoundClassification() async {
        guard soundClassifier.isAvailable else {
            print("⚠️ PipaSoundClassifier 未加载成功，本次仅使用视觉通道识别技法")
            soundSceneLabel = "声音模型不可用"
            return
        }
        
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission(completionHandler: { granted in
                continuation.resume(returning: granted)
            })
        }
        
        guard granted else {
            print("❌ 麦克风权限被拒绝，声音分类未启用")
            soundSceneLabel = "未授权麦克风"
            return
        }
        
        soundClassifier.setResultHandler { [weak self] label, probability in
            Task { @MainActor in
                self?.applySoundResult(label: label, pipaProbability: probability)
            }
        }

        // 同一路 16 kHz 采样转发给端侧分析器（生成评价报告用），零额外采集成本
        soundClassifier.onSamples = { [weak self] samples in
            self?.audioAnalyzer.process(samples)
        }
        
        do {
            try soundClassifier.start()
            print("🎧 声音分类已启动：Core ML PipaSoundClassifier，16 kHz 端侧推理")
        } catch {
            print("❌ 声音分类启动失败: \(error.localizedDescription)")
            soundSceneLabel = "麦克风启动失败"
        }
    }
    
    /// 记录声音分类结果
    private func applySoundResult(label: String, pipaProbability: Double) {
        hasSoundResult = true
        soundSceneLabel = label
        pipaConfidence = pipaProbability

        let isPipaNow = label == "琵琶声" && pipaProbability >= 0.5

        // 「持续听到琵琶声」：单次分类为琵琶声不算数，必须连续若干个窗口都判为琵琶声。
        // 模型窗口约 0.98 秒、重叠一半，即每 ~0.49 秒出一个结果；
        // 连续 3 次即代表约 1.5 秒以上的持续琵琶声，足以排除敲桌子、说话等瞬态误判。
        if isPipaNow {
            consecutivePipaWindows += 1
            totalPipaWindows += 1
        } else {
            consecutivePipaWindows = 0
        }

        // 历史连续段最长值：用于「整段练习里至少有一段持续的琵琶声」的判定
        longestPipaRun = max(longestPipaRun, consecutivePipaWindows)

        // 最近的判定序列：用于实时门的累计判据（乐曲停顿会打断连续段，
        // 但不代表整场没在弹，所以额外保留一条累计通道）
        recentPipaFlags.append(isPipaNow)
        if recentPipaFlags.count > 20 { recentPipaFlags.removeFirst() }

        // 实时显示用的瞬时状态：连续成立后才置位，避免界面标签抖动。
        // 判定放宽为「连续 3 窗」或「最近 20 窗（约 9.8 秒）内累计 4 窗」——
        // 后者让慢板乐曲（乐句短、停顿长）也能正常启动实时评分。
        // 20 窗的跨度要能覆盖慢板曲目的一个完整乐句周期，
        // 否则乐句之间的休止会把累计数压到阈值以下。
        let recentPipaCount = recentPipaFlags.filter { $0 }.count
        isPipaSoundDetected = consecutivePipaWindows >= Self.minConsecutivePipaWindows
            || (recentPipaFlags.count >= 20 && recentPipaCount >= 4)
    }
    
    // MARK: - Permissions
    
    /// 请求摄像头权限
    private func requestCameraPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

// MARK: - 手部姿势数据模型

struct HandPoseData {
    let timestamp: Date
    /// 这只手是用户的左（.left）还是右（.right）手
    let hand: HandChirality
    let thumbTip: CGPoint?
    let indexTip: CGPoint?
    let middleTip: CGPoint?
    let ringTip: CGPoint?
    let littleTip: CGPoint?
    let wrist: CGPoint?
    /// Vision 框架检测到的全部 21 个关键点（含中间关节）。
    /// 用于在画面上画出完整手指骨架，而不仅限指尖 + 手腕。
    let keypoints: [HandKeypoint]
    let confidence: Float
}

// MARK: - 运动特征

struct HandMotionFeatures {
    // 位置特征
    var fingerTipPositions: [CGPoint]
    var wristPosition: CGPoint
    
    // 速度特征
    var fingerVelocities: [CGVector]
    var wristVelocity: CGVector
    
    // 角度特征
    var tigerMouthAngle: Double   // 虎口角度（度）：手腕处拇指方向与食指方向的夹角
    var wristAngle: Double
    
    // 节奏特征
    var movementFrequency: Double
    var sequencePattern: [Int]
}

// MARK: - 姿势评估结果

/// 姿势评估结果。
/// 显式声明 Equatable：视图层用 `.onChange(of: currentEvaluation)` 观察它，
/// SwiftUI 的 onChange 要求被观察值满足 Equatable，否则编译报
/// "Referencing instance method 'onChange(of:initial:_:)' on 'Optional' requires that ... conform to 'Equatable'"。
/// 成员均为 Double / String / 枚举与数组，合成 == 即可。
struct PostureEvaluation: Equatable {
    var overallScore: Double        // 0-100 总分
    var aspects: [EvaluationAspect] // 各维度评分
    var suggestions: [String]       // 改进建议
}

struct EvaluationAspect: Equatable {
    enum Category: String, Equatable {
        // rawValue 只能是字面量，保持中文原文；界面展示统一走 displayName
        case handShape = "手型"
        case tigerMouth = "虎口角度"
        case wristPosition = "手腕位置"
        case rhythm = "节奏稳定性"
        case relaxation = "放松程度"

        /// 本地化显示名（中文原文即英文表的 key）
        var displayName: String { L(rawValue) }
    }
    
    let category: Category
    let score: Double       // 0-100
    let description: String
}

// MARK: - Placeholder 实现（待完善）

/// 手部姿势分析器
class HandPoseAnalyzer {
    private let extractor = HandPoseExtractor()
    
    /// 分析视频帧中的所有手，返回每只手的 HandPoseData（含左右标记）
    func analyzeHands(in pixelBuffer: CVPixelBuffer) async -> [HandPoseData] {
        // 使用 Vision 框架检测手部关键点（最多 2 只手）
        guard let hands = try? await extractor.extractHands(from: pixelBuffer),
              !hands.isEmpty else {
            print("⚠️ 未检测到手部关键点")  // 调试日志
            return []
        }

        return hands.map { detected in
            let kp = detected.keypoints
            let thumbTip = kp.first(where: { $0.name == "thumbTip" })?.location
            let indexTip = kp.first(where: { $0.name == "indexTip" })?.location
            let middleTip = kp.first(where: { $0.name == "middleTip" })?.location
            let ringTip = kp.first(where: { $0.name == "ringTip" })?.location
            let littleTip = kp.first(where: { $0.name == "littleTip" })?.location
            let wrist = kp.first(where: { $0.name == "wrist" })?.location

            let avgConfidence = Float(kp.map { $0.confidence }.reduce(0, +) / Double(kp.count))

            return HandPoseData(
                timestamp: Date(),
                hand: detected.chirality,
                thumbTip: thumbTip,
                indexTip: indexTip,
                middleTip: middleTip,
                ringTip: ringTip,
                littleTip: littleTip,
                wrist: wrist,
                keypoints: kp,
                confidence: avgConfidence
            )
        }
    }
}

/// 运动特征提取器
class MotionFeatureExtractor {
    // 历史姿势队列（用于计算速度和运动模式）
    private var poseHistory: [HandPoseData] = []
    private let maxHistorySize = 10 // 保留最近 10 帧
    
    func extractFeatures(from handPose: HandPoseData) -> HandMotionFeatures {
        // 1. 添加到历史队列
        poseHistory.append(handPose)
        if poseHistory.count > maxHistorySize {
            poseHistory.removeFirst()
        }
        
        // 2. 提取位置特征
        let fingerPositions = [
            handPose.thumbTip ?? .zero,
            handPose.indexTip ?? .zero,
            handPose.middleTip ?? .zero,
            handPose.ringTip ?? .zero,
            handPose.littleTip ?? .zero
        ]
        let wristPos = handPose.wrist ?? .zero
        
        // 3. 计算速度特征
        let velocities = calculateFingerVelocities()
        let wristVel = calculateWristVelocity()
        
        // 4. 计算角度特征
        let tigerAngle = calculateTigerMouthAngle(handPose: handPose)
        let wristAngle = calculateWristAngle(handPose: handPose)

        // 5. 计算节奏特征
        let frequency = calculateMovementFrequency()
        let pattern = detectSequencePattern()

        return HandMotionFeatures(
            fingerTipPositions: fingerPositions,
            wristPosition: wristPos,
            fingerVelocities: velocities,
            wristVelocity: wristVel,
            tigerMouthAngle: tigerAngle,
            wristAngle: wristAngle,
            movementFrequency: frequency,
            sequencePattern: pattern
        )
    }
    
    // MARK: - 速度计算
    
    private func calculateFingerVelocities() -> [CGVector] {
        guard poseHistory.count >= 2 else {
            return Array(repeating: .zero, count: 5)
        }
        
        let current = poseHistory.last!
        let previous = poseHistory[poseHistory.count - 2]
        let timeDiff = current.timestamp.timeIntervalSince(previous.timestamp)
        
        guard timeDiff > 0 else {
            return Array(repeating: .zero, count: 5)
        }
        
        let fingers = [
            (current.thumbTip, previous.thumbTip),
            (current.indexTip, previous.indexTip),
            (current.middleTip, previous.middleTip),
            (current.ringTip, previous.ringTip),
            (current.littleTip, previous.littleTip)
        ]
        
        return fingers.map { curr, prev in
            guard let curr = curr, let prev = prev else { return .zero }
            let dx = (curr.x - prev.x) / CGFloat(timeDiff)
            let dy = (curr.y - prev.y) / CGFloat(timeDiff)
            return CGVector(dx: dx, dy: dy)
        }
    }
    
    private func calculateWristVelocity() -> CGVector {
        guard poseHistory.count >= 2 else { return .zero }
        
        let current = poseHistory.last!
        let previous = poseHistory[poseHistory.count - 2]
        let timeDiff = current.timestamp.timeIntervalSince(previous.timestamp)
        
        guard timeDiff > 0,
              let currWrist = current.wrist,
              let prevWrist = previous.wrist else {
            return .zero
        }
        
        let dx = (currWrist.x - prevWrist.x) / CGFloat(timeDiff)
        let dy = (currWrist.y - prevWrist.y) / CGFloat(timeDiff)
        return CGVector(dx: dx, dy: dy)
    }
    
    // MARK: - 角度计算
    
    private func calculateTigerMouthAngle(handPose: HandPoseData) -> Double {
        // 虎口角度：手腕处，拇指方向 vs 食指方向的夹角（度数）
        // 三个端点：wrist（参考点）、thumbTip（拇指端）、indexTip（食指端）
        // 用拇指 + 食指 + 手腕关节连线形成的夹角，反映虎口的打开程度
        guard let wrist = handPose.wrist,
              let thumbTip = handPose.thumbTip,
              let indexTip = handPose.indexTip else {
            return 0
        }

        // 两条向量：wrist -> thumbTip, wrist -> indexTip
        let v1x = Double(thumbTip.x - wrist.x)
        let v1y = Double(thumbTip.y - wrist.y)
        let v2x = Double(indexTip.x - wrist.x)
        let v2y = Double(indexTip.y - wrist.y)

        let len1 = sqrt(v1x * v1x + v1y * v1y)
        let len2 = sqrt(v2x * v2x + v2y * v2y)

        // 任一向量长度过短（识别失败/夹在同一处）则返回 0
        guard len1 > 0.001, len2 > 0.001 else { return 0 }

        let dot = v1x * v2x + v1y * v2y
        let cosTheta = dot / (len1 * len2)
        let clamped = max(-1.0, min(1.0, cosTheta))
        return acos(clamped) * 180.0 / .pi
    }
    
    private func calculateWristAngle(handPose: HandPoseData) -> Double {
        // 计算手腕相对于水平线的角度
        guard let wrist = handPose.wrist,
              let middleTip = handPose.middleTip else {
            return 0
        }
        
        let dx = middleTip.x - wrist.x
        let dy = middleTip.y - wrist.y
        return atan2(Double(dy), Double(dx))
    }
    
    // MARK: - 节奏分析
    
    private func calculateMovementFrequency() -> Double {
        guard poseHistory.count >= 5 else { return 0 }
        
        // 计算最近 5 帧的平均运动速度
        var totalSpeed: Double = 0
        for i in 1..<min(5, poseHistory.count) {
            let curr = poseHistory[poseHistory.count - i]
            let prev = poseHistory[poseHistory.count - i - 1]
            
            if let currIndex = curr.indexTip, let prevIndex = prev.indexTip {
                let distance = hypot(Double(currIndex.x - prevIndex.x), Double(currIndex.y - prevIndex.y))
                totalSpeed += distance
            }
        }
        
        return totalSpeed / Double(min(4, poseHistory.count - 1))
    }
    
    private func detectSequencePattern() -> [Int] {
        // 检测手指运动顺序（0=拇指, 1=食指, 2=中指, 3=无名指, 4=小指）
        guard poseHistory.count >= 3 else { return [] }
        
        var pattern: [Int] = []
        
        // 比较最近几帧，找出哪个手指移动最快
        // 至少观察约 0.2 秒的运动；仅两个相邻帧无法区分弹挑交替和轮指。
        for i in 1..<min(8, poseHistory.count) {
            let curr = poseHistory[poseHistory.count - i]
            let prev = poseHistory[poseHistory.count - i - 1]
            
            let fingers = [
                (curr.thumbTip, prev.thumbTip, 0),
                (curr.indexTip, prev.indexTip, 1),
                (curr.middleTip, prev.middleTip, 2),
                (curr.ringTip, prev.ringTip, 3),
                (curr.littleTip, prev.littleTip, 4)
            ]
            
            var maxMovement: Double = 0
            var movingFinger = -1
            
            for (currTip, prevTip, index) in fingers {
                guard let curr = currTip, let prev = prevTip else { continue }
                let distance = hypot(Double(curr.x - prev.x), Double(curr.y - prev.y))
                if distance > maxMovement && distance > 0.01 { // 阈值：1% 的屏幕
                    maxMovement = distance
                    movingFinger = index
                }
            }
            
            if movingFinger >= 0 {
                pattern.append(movingFinger)
            }
        }
        
        return pattern
    }
    
    /// 重置历史数据
    func reset() {
        poseHistory.removeAll()
    }
}

/// 技法分类器
class TechniqueClassifier {
    private var classificationHistory: [TechniqueType] = []
    private let historySize = 5 // 使用最近 5 次分类结果进行平滑
    
    func classify(features: HandMotionFeatures) -> TechniqueType {
        let technique = classifyBasedOnRules(features: features)
        
        // 添加到历史并进行平滑处理
        classificationHistory.append(technique)
        if classificationHistory.count > historySize {
            classificationHistory.removeFirst()
        }
        
        // 返回最常见的分类（防止抖动）
        return mostFrequentTechnique() ?? technique
    }
    
    // MARK: - 基于规则的分类
    
    private func classifyBasedOnRules(features: HandMotionFeatures) -> TechniqueType {
        // 检查是否有足够的数据
        guard !features.fingerVelocities.isEmpty,
              !features.sequencePattern.isEmpty else {
            return .unknown
        }
        
        // 计算手指平均速度
        let avgSpeed = features.fingerVelocities.map { hypot(Double($0.dx), Double($0.dy)) }
            .reduce(0, +) / Double(features.fingerVelocities.count)
        
        // 计算手腕移动速度
        let wristSpeed = hypot(Double(features.wristVelocity.dx), Double(features.wristVelocity.dy))
        
        // 1️⃣ 判断是否为"扫弦" (Sweep)
        // 特征：所有手指同时快速移动 + 手腕也在动
        let fastFingers = features.fingerVelocities.filter { 
            hypot(Double($0.dx), Double($0.dy)) > 0.5 
        }.count
        if fastFingers >= 4 && wristSpeed > 0.3 {
            print("🎸 规则匹配：扫弦 (快速手指:\(fastFingers), 手腕速度:\(String(format: "%.2f", wristSpeed)))")
            return .sweep
        }
        
        let observedFingers = Set(features.sequencePattern)
        let isThumbIndexAlternation = observedFingers.isSubset(of: Set([0, 1]))
            && observedFingers.count >= 1

        // 2️⃣ 判断是否为"弹挑" (Pluck)
        // 弹挑主要由拇指、食指单独或交替运动。必须在轮指之前判断，避免 [0,1]
        // 这种短序列被误认为轮指。
        let movingFingers = features.fingerVelocities.enumerated().filter { _, velocity in
            hypot(Double(velocity.dx), Double(velocity.dy)) > 0.32
        }
        if isThumbIndexAlternation && movingFingers.count <= 2 && avgSpeed > 0.10 {
            print("👆 规则匹配：弹挑 (模式:\(features.sequencePattern), 活跃手指数:\(movingFingers.count))")
            return .pluck
        }

        // 3️⃣ 判断是否为"轮指" (Roll)
        // 至少观察到 3 根不同手指和 3 次连续转换，才视为完整轮指序列。
        if observedFingers.count >= 3,
           features.sequencePattern.count >= 4,
           isSequentialPattern(features.sequencePattern),
           avgSpeed > 0.2 {
            print("🔄 规则匹配：轮指 (顺序模式:\(features.sequencePattern), 平均速度:\(String(format: "%.2f", avgSpeed)))")
            return .roll
        }
        
        // 4️⃣ 判断是否为一般弹挑：仅 1～2 根手指明显活跃。
        // 特征：单个手指快速运动，其他手指相对静止
        if movingFingers.count == 1 || movingFingers.count == 2 {
            print("👆 规则匹配：弹挑 (活跃手指数:\(movingFingers.count))")
            return .pluck
        }
        
        // 模糊动作不猜测为轮指，等待更多帧证据。
        return .unknown
    }
    
    // MARK: - 辅助方法
    
    /// 判断是否为顺序模式（如 [1,2,3] 或 [4,3,2,1]）
    private func isSequentialPattern(_ pattern: [Int]) -> Bool {
        guard pattern.count >= 2 else { return false }
        
        // 允许轮指循环回绕（4→0 或 0→4），但大部分相邻动作必须沿同一方向。
        let deltas = zip(pattern, pattern.dropFirst()).compactMap { previous, current -> Int? in
            guard previous != current else { return nil }
            if current == (previous + 1) % 5 { return 1 }
            if previous == (current + 1) % 5 { return -1 }
            return 0
        }
        guard deltas.count >= 3 else { return false }
        let forward = deltas.filter { $0 == 1 }.count
        let backward = deltas.filter { $0 == -1 }.count
        return max(forward, backward) >= Int(ceil(Double(deltas.count) * 0.75))
    }
    
    /// 返回历史记录中最常见的技法（平滑处理）
    private func mostFrequentTechnique() -> TechniqueType? {
        guard !classificationHistory.isEmpty else { return nil }
        
        // 统计每种技法出现的次数
        var counts: [TechniqueType: Int] = [:]
        for technique in classificationHistory {
            counts[technique, default: 0] += 1
        }
        
        // 找出出现次数最多的
        let sorted = counts.sorted { $0.value > $1.value }
        let mostCommon = sorted.first?.key
        
        return mostCommon
    }
    
    /// 重置分类历史
    func reset() {
        classificationHistory.removeAll()
    }
}

// MARK: - Core ML 声音分类引擎

/// 加载 Create ML 自训的声音分类模型 PipaSoundClassifier，
/// 用 AVAudioEngine 采集 16 kHz 音频，在设备本地做四分类推理（琵琶 / 其它乐器 / 人声 / 环境噪声）。
/// 全流程不联网、不落盘、不上传：音频只在内存里滑动，推理在端侧完成。
final class PipaSoundClassifierEngine: @unchecked Sendable {
    
    /// 模型要求的输入采样率
    static let sampleRate: Double = 16000
    
    /// 模型是否成功加载——加载失败时调用方应降级为纯视觉识别
    private(set) var isAvailable: Bool = false
    
    private let model: MLModel?
    private let inputName: String
    private let inputShape: [NSNumber]
    private let windowLength: Int
    private let hopLength: Int
    
    private let queue = DispatchQueue(label: "com.pluckbuddy.soundclassifier", qos: .userInitiated)
    private var resultHandler: (@Sendable (String, Double) -> Void)?
    /// 把同一路 16 kHz 单声道采样转发给外部（供智能指法教练的端侧分析器复用，零额外采集成本）
    var onSamples: (([Float]) -> Void)?
    private var engine: AVAudioEngine?
    private var pendingSamples: [Float] = []
    private var recentProbabilities: [Double] = []
    private var isRunning = false
    private var didActivateSession = false
    
    init() {
        let loaded = Self.loadModel()
        model = loaded?.model
        inputName = loaded?.inputName ?? "audioSamples"
        inputShape = loaded?.shape ?? [NSNumber(value: 15600)]
        windowLength = loaded?.length ?? 15600
        hopLength = max((loaded?.length ?? 15600) / 2, 1)
        isAvailable = loaded != nil
    }
    
    deinit {
        stop()
    }
    
    // MARK: - 模型加载
    
    private struct LoadedModel {
        let model: MLModel
        let inputName: String
        let shape: [NSNumber]
        let length: Int
    }
    
    private static func loadModel() -> LoadedModel? {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        
        // Xcode 会把 .mlmodel 编译成 Bundle 里的 .mlmodelc；找不到时现场编译兜底
        var modelURL = Bundle.main.url(forResource: "PipaSoundClassifier", withExtension: "mlmodelc")
        if modelURL == nil,
           let rawURL = Bundle.main.url(forResource: "PipaSoundClassifier", withExtension: "mlmodel") {
            modelURL = try? MLModel.compileModel(at: rawURL)
        }
        
        guard let url = modelURL,
              let model = try? MLModel(contentsOf: url, configuration: configuration) else {
            print("❌ PipaSoundClassifier 加载失败：Bundle 中找不到可用模型")
            return nil
        }
        
        let inputs = model.modelDescription.inputDescriptionsByName
        let inputName = inputs["audioSamples"] != nil ? "audioSamples" : (inputs.keys.first ?? "audioSamples")
        let shape = inputs[inputName]?.multiArrayConstraint?.shape ?? [NSNumber(value: 15600)]
        let length = shape.reduce(1) { $0 * $1.intValue }
        
        print("✅ PipaSoundClassifier 已加载")
        print("   输入: \(inputName) \(shape.map { $0.intValue }) → \(length) 个采样点")
        print("   输出: \(model.modelDescription.outputDescriptionsByName.keys.sorted())")
        
        return LoadedModel(model: model, inputName: inputName, shape: shape, length: length)
    }
    
    // MARK: - 采集控制
    
    /// 设置推理结果回调（中文类别 + 琵琶概率）
    func setResultHandler(_ handler: @escaping @Sendable (String, Double) -> Void) {
        queue.sync { resultHandler = handler }
    }
    
    func start() throws {
        var failure: Error?
        
        queue.sync {
            guard !isRunning, model != nil else { return }
            
            let session = AVAudioSession.sharedInstance()
            do {
                // 与调音器 AudioManager 使用同一套会话配置：可录音也可外放（节拍器/示范音），
                // 且允许与其他音频混播，避免把会话切成纯录音后打断正在播放的声音
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
                try session.setActive(true)
                didActivateSession = true
            } catch {
                failure = error
                return
            }
            
            let audioEngine = AVAudioEngine()
            let input = audioEngine.inputNode
            // 关键点：tap 必须使用输入节点自身的输出格式（真机实测为 48 kHz）。
            // 若在这里指定成模型需要的 16 kHz，AVAudioEngine 会抛
            // "Failed to create tap due to format mismatch" 并终止进程。
            // 因此改为按硬件格式采集，降到 16 kHz 的步骤放到回调里用软件完成。
            let inputFormat = input.outputFormat(forBus: 0)
            print("🎤 声音分类采集格式：\(inputFormat.sampleRate) Hz / \(inputFormat.channelCount) 声道")
            
            let sampleHandler = self.onSamples
            input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                guard let self else { return }
                let samples = Self.monoSamples(from: buffer, targetSampleRate: Self.sampleRate)
                sampleHandler?(samples)
                self.queue.async { self.append(samples) }
            }
            
            do {
                try audioEngine.start()
            } catch {
                input.removeTap(onBus: 0)
                failure = error
                return
            }
            
            engine = audioEngine
            pendingSamples.removeAll()
            recentProbabilities.removeAll()
            isRunning = true
        }
        
        if let failure {
            throw failure
        }
    }
    
    func stop() {
        queue.sync {
            guard isRunning else { return }
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            engine = nil
            pendingSamples.removeAll()
            recentProbabilities.removeAll()
            isRunning = false
            // 只有这次采集确实是我们激活的会话才去关闭，避免误伤调音器还在用的会话
            if didActivateSession {
                try? AVAudioSession.sharedInstance().setActive(false)
                didActivateSession = false
            }
        }
    }
    
    // MARK: - 推理
    
    /// 累积到一整窗后推理一次，窗口之间保留一半重叠
    private func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        pendingSamples.append(contentsOf: samples)
        
        while pendingSamples.count >= windowLength {
            let window = Array(pendingSamples.prefix(windowLength))
            pendingSamples.removeFirst(min(hopLength, pendingSamples.count))
            classify(window)
        }
        
        // 推理跟不上采集时丢弃积压，避免内存无限增长
        if pendingSamples.count > windowLength * 4 {
            pendingSamples.removeFirst(pendingSamples.count - windowLength)
        }
    }
    
    private func classify(_ window: [Float]) {
        guard let model, window.count == windowLength else { return }
        guard let array = try? MLMultiArray(shape: inputShape, dataType: .float32) else { return }
        for index in 0..<windowLength {
            array[index] = NSNumber(value: window[index])
        }
        let value = MLFeatureValue(multiArray: array)
        
        let provider: MLFeatureProvider
        do {
            provider = try MLDictionaryFeatureProvider(dictionary: [inputName: value])
        } catch {
            return
        }
        
        guard let output = try? model.prediction(from: provider) else { return }
        
        let rawLabel = output.featureValue(for: "target")?.stringValue ?? "background"
        let probability = (output.featureValue(for: "targetProbability")?.dictionaryValue["pipa"] as? NSNumber)?.doubleValue ?? 0
        
        // 最近三次结果取平均，抑制单帧抖动
        recentProbabilities.append(probability)
        if recentProbabilities.count > 3 {
            recentProbabilities.removeFirst()
        }
        let smoothed = recentProbabilities.reduce(0, +) / Double(recentProbabilities.count)
        
        resultHandler?(Self.chineseLabel(for: rawLabel), smoothed)
    }
    
    // MARK: - 音频处理
    
    /// 把任意格式的 PCM 缓冲混合成单声道，并按模型采样率重采样
    private static func monoSamples(from buffer: AVAudioPCMBuffer, targetSampleRate: Double) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return [] }
        
        let channelCount = max(Int(buffer.format.channelCount), 1)
        var mono = [Float](repeating: 0, count: frameCount)
        
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let data = buffer.floatChannelData else { return [] }
            for channel in 0..<channelCount {
                let source = data[channel]
                for i in 0..<frameCount { mono[i] += source[i] }
            }
            
        case .pcmFormatInt16:
            guard let data = buffer.int16ChannelData else { return [] }
            for channel in 0..<channelCount {
                let source = data[channel]
                for i in 0..<frameCount { mono[i] += Float(source[i]) / 32768 }
            }
            
        case .pcmFormatInt32:
            guard let data = buffer.int32ChannelData else { return [] }
            for channel in 0..<channelCount {
                let source = data[channel]
                for i in 0..<frameCount { mono[i] += Float(source[i]) / 2147483648 }
            }
            
        default:
            return []
        }
        
        if channelCount > 1 {
            let scale = 1 / Float(channelCount)
            for i in 0..<frameCount { mono[i] *= scale }
        }
        
        let sourceRate = buffer.format.sampleRate
        guard sourceRate > 0, abs(sourceRate - targetSampleRate) > 1 else { return mono }
        
        // 48 kHz → 16 kHz 的软件重采样：线性插值，直接抽点会引入高频失真、影响分类置信度
        let step = sourceRate / targetSampleRate
        let targetCount = max(Int((Double(frameCount) - 1) / step), 1)
        var resampled = [Float](repeating: 0, count: targetCount)
        for i in 0..<targetCount {
            let position = Double(i) * step
            let index = min(Int(position), frameCount - 1)
            let next = min(index + 1, frameCount - 1)
            let fraction = Float(position - Double(index))
            resampled[i] = mono[index] + (mono[next] - mono[index]) * fraction
        }
        return resampled
    }
    
    private static func chineseLabel(for raw: String) -> String {
        switch raw {
        case "pipa": return "琵琶声"
        case "other_instrument": return "其它乐器"
        case "speech": return "人声"
        case "background": return "环境噪声"
        default: return raw
        }
    }
}

// MARK: - 注意：
// RollPostureEvaluator, SweepPostureEvaluator, PluckPostureEvaluator
// 这些类现在定义在 TechniqueEvaluators.swift 文件中
