//
//  PipaSoundGate.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/9/30.
//
//  智能调音模块的「琵琶声」判门。复用指法教练里的 PipaSoundClassifier CoreML 模型，
//  但不接管 AVAudioEngine 和音频会话——麦克风数据由 AudioManager 提供（避免和指法教练/陪练模块抢 tap）。
//
//  输入：来自 AudioManager 的 AVAudioPCMBuffer（硬件格式，通常 48 kHz）
//  流程：硬件缓冲 → 单声道 → 软件降采样到 16 kHz → 累积到 15600 帧（约 0.975s）→ 跑模型推理
//  状态：最近一次判定的「是否是琵琶」+ 概率，对外暴露只读 Published
//
//  实现说明：可变状态全部在 inferenceQueue 上串行访问，Published 输出通过 DispatchQueue.main
//  派发回主线程。标记 @unchecked Sendable 因为所有共享状态都受 inferenceQueue 串行保护。
//

import Foundation
import AVFoundation
import CoreML
import Combine

final class PipaSoundGate: ObservableObject, @unchecked Sendable {

    // MARK: - 模型规格（和指法教练的 PipaSoundClassifierEngine 保持一致）
    /// 模型需要的采样率
    private static let modelSampleRate: Double = 16000
    /// 模型窗口长度：15600 个采样点 = 16 kHz × 0.975 秒
    private static let windowLength = 15600
    /// 重叠推理步长：8000 帧 ≈ 0.5 秒（窗口 15600，步长 8000 → 50% 重叠）
    /// 重叠后同一发声片段会被 2~3 次推理覆盖，提升命中率；CPU 压力翻倍但仍在可接受范围
    private static let windowStep = 8000
    /// 能量门控：窗口 RMS 低于此值视为安静帧，跳过模型推理、直接判 background（不污染滑动平均）
    /// 真机麦克风实测：环境噪声 RMS≈0.001~0.005，弹琵琶 RMS≈0.05~0.3，说话≈0.01~0.05
    private static let energyFloor: Float = 0.01
    /// 输出标签（pipa 是四分类中的「琵琶」类）
    private static let pipaLabel = "pipa"

    // MARK: - 模型（推理队列内只读）
    private let model: MLModel?
    private let inputName: String

    // MARK: - 推理调度
    /// 后台推理队列。所有可变状态都只在它上面访问（受其串行保护）。
    private let inferenceQueue = DispatchQueue(label: "com.pluckbuddy.tuner.soundgate", qos: .userInitiated)
    /// 16 kHz 样本累积缓冲（按推理顺序追加）
    private var pending16kSamples: [Float] = []
    /// 最近 3 次推理的 pipa 概率，用于滑动平均抑制单帧抖动
    private var recentPipaProbs: [Double] = []
    /// 滑动平均窗口：取最近 N 次推理的 pipa 概率平均后判断。N=2 足够稳定又不至于把高概率平均下来。
    private let recentWindow = 2

    // MARK: - 对外 Published 状态（主线程派发更新）
    /// 模型是否成功加载。失败时本门退化为「全放行」，等价于关闭过滤。
    @Published private(set) var isAvailable: Bool = false
    /// 最近一次推理是否判定为琵琶声（pipa 概率 ≥ 阈值，且平滑后仍在阈值上）
    @Published private(set) var isPipa: Bool = false
    /// 最近一次推理的 pipa 概率（滑动平均后）
    @Published private(set) var pipaProb: Double = 0.0
    /// 最近一次判定为「琵琶声」的时间戳；调音用它做「0.5s 内有琵琶 → 才判音高」
    private(set) var lastDetectedAt: Date?

    /// 判定为「琵琶声」的最低概率阈值（0.35 是真机调试后确定的折中值——模型在四分类下真琵琶概率多在 0.3~0.7 区间，0.5 偏严）。
    /// 若真机 console 显示 pipa 平滑概率常 ≥0.6，可上调到 0.5 以求严；若弹琵琶还常被判 ≤0.2，说明模型对当前麦克风音质判别力不足，需重训或换模型。
    private let threshold: Double = 0.35

    // MARK: - 生命周期
    init() {
        if let loaded = Self.loadModel() {
            self.model = loaded.model
            self.inputName = loaded.inputName
            self.isAvailable = true
            print("✅ PipaSoundGate 模型已加载（输入：\(loaded.inputName), 窗口：\(Self.windowLength) 帧 @ \(Int(Self.modelSampleRate)) Hz）")
        } else {
            self.model = nil
            self.inputName = "audioSamples"
            self.isAvailable = false
            print("⚠️ PipaSoundGate 模型加载失败，门控降级为全放行")
        }
    }

    // MARK: - 模型加载（参考指法教练 PipaSoundClassifierEngine.loadModel）

    private struct LoadedModel {
        let model: MLModel
        let inputName: String
    }

    private static func loadModel() -> LoadedModel? {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        var modelURL = Bundle.main.url(forResource: "PipaSoundClassifier", withExtension: "mlmodelc")
        if modelURL == nil,
           let rawURL = Bundle.main.url(forResource: "PipaSoundClassifier", withExtension: "mlmodel") {
            modelURL = try? MLModel.compileModel(at: rawURL)
        }

        guard let url = modelURL,
              let model = try? MLModel(contentsOf: url, configuration: configuration) else {
            return nil
        }

        let inputs = model.modelDescription.inputDescriptionsByName
        let inputName = inputs["audioSamples"] != nil ? "audioSamples" : (inputs.keys.first ?? "audioSamples")
        return LoadedModel(model: model, inputName: inputName)
    }

    // MARK: - 喂入音频缓冲（每帧从 AudioManager 回调里调用一次）
    /// 接收来自 AudioManager 的硬件格式缓冲，把它降采样后塞进累积队列；
  /// 凑满一窗（15600 帧 @16kHz）就在后台跑一次推理，结果回主线程更新 Published 状态。
    func feed(buffer: AVAudioPCMBuffer) {
        let samples = Self.monoSamples(from: buffer, targetSampleRate: Self.modelSampleRate)
        guard !samples.isEmpty else { return }

        inferenceQueue.async { [weak self] in
            guard let self else { return }
            self.append(samples)
        }
    }

    // 推理队列上：追加样本、凑窗、推理
    private func append(_ samples: [Float]) {
        guard model != nil else { return }
        pending16kSamples.append(contentsOf: samples)

        // ✅ 重叠窗口推理：累积 ≥1 窗就推理一次，每次步进 windowStep（50% 重叠）
        while pending16kSamples.count >= Self.windowLength {
            let window = Array(pending16kSamples.prefix(Self.windowLength))
            pending16kSamples.removeFirst(Self.windowStep)

            // ✅ 能量门控：安静帧直接判 background，不污染滑动平均
            let windowRMS = Self.rms(of: window)
            let label: String
            let pipaProb: Double
            let skipped = windowRMS < Self.energyFloor
            if skipped {
                label = "background"
                pipaProb = 0
            } else if let result = classify(window) {
                (label, pipaProb, _) = result
            } else {
                continue
            }

            // 滑动平均（抑制单帧抖动）
            recentPipaProbs.append(pipaProb)
            if recentPipaProbs.count > recentWindow {
                recentPipaProbs.removeFirst()
            }
            let smoothed = recentPipaProbs.reduce(0, +) / Double(max(recentPipaProbs.count, 1))
            let smoothedIsPipa = (label == Self.pipaLabel) && (smoothed >= threshold)

            // 诊断输出：每次推理都打印概率分布与判定结果，便于真机调试
            let tag = skipped ? "[静音跳过]" : ""
            print("🎵 [PipaGate]\(tag) rms=\(String(format: "%.4f", windowRMS)) label=\(label) pipa=\(String(format: "%.3f", pipaProb)) smoothed=\(String(format: "%.3f", smoothed)) -> pipa:\(smoothedIsPipa ? "✅" : "❌")")

            // 派发到主线程更新 Published（Combine 会自动通知 View）
            let detectedAt = Date()
            let rawIsPipa = (label == Self.pipaLabel) && (pipaProb >= threshold)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pipaProb = smoothed
                self.isPipa = smoothedIsPipa
                if rawIsPipa || smoothedIsPipa {
                    self.lastDetectedAt = detectedAt
                }
            }
        }

        // 防止积压：累积超过 4 窗就丢老数据
        if pending16kSamples.count > Self.windowLength * 4 {
            pending16kSamples.removeFirst(pending16kSamples.count - Self.windowLength)
        }
    }

    // 推理队列上调用：单次推理，返回 (原始英文标签, pipa 概率, 完整概率字典)
    private func classify(_ window: [Float]) -> (String, Double, [String: Double])? {
        guard let model, window.count == Self.windowLength else { return nil }
        let shape = [NSNumber(value: Self.windowLength)]
        guard let array = try? MLMultiArray(shape: shape, dataType: .float32) else { return nil }
        for index in 0..<Self.windowLength {
            array[index] = NSNumber(value: window[index])
        }
        let value = MLFeatureValue(multiArray: array)
        let provider: MLFeatureProvider
        do {
            provider = try MLDictionaryFeatureProvider(dictionary: [inputName: value])
        } catch {
            return nil
        }
        guard let output = try? model.prediction(from: provider) else { return nil }
        let rawLabel = output.featureValue(for: "target")?.stringValue ?? "background"
        let probDict = output.featureValue(for: "targetProbability")?.dictionaryValue ?? [:]
        // dictionaryValue 的 key 是 AnyHashable，需转回 String
        var probs: [String: Double] = [:]
        for (k, v) in probDict {
            let key = (k.base as? String) ?? String(describing: k)
            if let n = v as? NSNumber { probs[key] = n.doubleValue }
        }
        let pipaProb = probs[Self.pipaLabel] ?? 0
        return (rawLabel, pipaProb, probs)
    }

    // MARK: - 公开判定接口（供调音主线程在音频回调里快速检查）

    /// 「最近一次判定是否落在『琵琶声』有效窗口内」。默认 0.5 秒，调音音高判定时调用。
    /// - Parameter window: 判定窗口长度，默认 0.5 秒
    /// - Returns: 模型加载失败时返回 true（降级为全放行），否则只要「窗口内曾判为琵琶」即放行。
    ///
    /// ⚠️ 关键语义：只检查 `lastDetectedAt`，不要再加 `isPipa` 当前值的约束。
    /// 判门推理是重叠窗口（约每 0.5s 一次），真琵琶声在临界概率附近会抖动，
    /// 某一帧被抖成 `isPipa = false` 时若还要求「当前仍为 pipa」就会把音高分析反复掐断，
    /// 导致「顶部显示已检测到琵琶声、但音高三角形几乎不出现」。正确做法是：
    /// 只要最近一次 `lastDetectedAt` 落在窗口内（即最近一直在听到琵琶），就持续放行音高分析。
    func isPipaRecent(within window: TimeInterval = 0.5) -> Bool {
        guard isAvailable else { return true } // 模型不可用 → 全放行
        guard let t = lastDetectedAt else { return false }
        return Date().timeIntervalSince(t) <= window
    }

    /// 重置内部状态（停止练习时调用，避免下次开局前残留上一次的「最近判定」）
    func reset() {
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            self.pending16kSamples.removeAll()
            self.recentPipaProbs.removeAll()
            DispatchQueue.main.async {
                self.isPipa = false
                self.pipaProb = 0
                self.lastDetectedAt = nil
            }
        }
    }

    // MARK: - 工具：单声道 + 软件降采样（参考指法教练的同名方法）

    /// 计算样本数组的 RMS（均方根能量）。用于能量门控判断窗口内是否有显著声音。
    /// 静音帧 RMS 通常 < 0.005，弹琵琶 ≈0.05~0.3，说话 ≈0.01~0.05。
    private static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sumSq: Float = 0
        for s in samples {
            sumSq += s * s
        }
        return (sumSq / Float(samples.count)).squareRoot()
    }

    /// 把任意 PCM 缓冲混合成单声道，并按目标采样率重采样（线性插值，避免直接抽点引入高频失真）
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

        // 48 kHz → 16 kHz 软件降采样：线性插值
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
}