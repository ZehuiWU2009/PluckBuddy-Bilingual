//
//  HandPoseExtractor.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/8/17.
//

import Vision
import AVFoundation
import CoreImage

/// 手部姿态提取器
/// 使用 Apple Vision Framework 提取手部 21 个关键点
class HandPoseExtractor {
    
    // MARK: - Properties
    private var handPoseRequest: VNDetectHumanHandPoseRequest
    
    // 21 个关键点名称（按顺序）
    private let jointNames: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]
    
    // MARK: - Initialization
    init() {
        handPoseRequest = VNDetectHumanHandPoseRequest()
        handPoseRequest.maximumHandCount = 2  // 检测最多 2 只手
    }
    
    // MARK: - Public Methods
    
    /// 从视频帧中提取所有检测到的手（最多 2 只），并为每只手标记用户的真实左右手。
    /// - Parameter buffer: 视频帧缓冲区
    /// - Returns: 每只手的关键点数组（含左右标记）
    func extractHands(from buffer: CVPixelBuffer) async throws -> [DetectedHand] {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        try handler.perform([handPoseRequest])

        guard let observations = handPoseRequest.results,
              !observations.isEmpty else {
            // 未检测到手部，返回空数组
            return []
        }

        // 遍历 Vision 检测到的每只手（前置摄像头已镜像，左右需按 videoIsMirrored 翻转）
        return observations.compactMap { observation -> DetectedHand? in
            var keypoints: [HandKeypoint] = []
            for jointName in jointNames {
                if let point = try? observation.recognizedPoint(jointName) {
                    keypoints.append(HandKeypoint(
                        name: getSimpleName(for: jointName),
                        location: point.location,
                        confidence: Double(point.confidence)
                    ))
                }
            }
            guard !keypoints.isEmpty else { return nil }
            let chirality = Self.mapToUserHand(observation.chirality)
            print("✅ 检测到 \(keypoints.count) 个关键点（\(chirality == .left ? "左手" : "右手")）")
            return DetectedHand(chirality: chirality, keypoints: keypoints)
        }
    }

    /// 摄像头为前置且开启镜像（isVideoMirrored=true），Vision 在镜像缓冲里看到的
    /// 「左手」实际是真实用户的右手，故此处翻转一次。若真机实测左右相反，改 false 即可。
    private static let videoIsMirrored = true

    /// 把 Vision 报告的左右手翻转到用户的真实左右手
    private static func mapToUserHand(_ chirality: VNChirality) -> HandChirality {
        switch chirality {
        case .unknown: return .right  // 识别不出左右时按右手处理（指法分类以右手为准）
        case .left:  return videoIsMirrored ? HandChirality.right : HandChirality.left
        case .right: return videoIsMirrored ? HandChirality.left : HandChirality.right
        }
    }
    
    /// 获取关键点的简化名称
    private func getSimpleName(for jointName: VNHumanHandPoseObservation.JointName) -> String {
        switch jointName {
        case .wrist: return "wrist"
        case .thumbCMC: return "thumbCMC"
        case .thumbMP: return "thumbMP"
        case .thumbIP: return "thumbIP"
        case .thumbTip: return "thumbTip"
        case .indexMCP: return "indexMCP"
        case .indexPIP: return "indexPIP"
        case .indexDIP: return "indexDIP"
        case .indexTip: return "indexTip"
        case .middleMCP: return "middleMCP"
        case .middlePIP: return "middlePIP"
        case .middleDIP: return "middleDIP"
        case .middleTip: return "middleTip"
        case .ringMCP: return "ringMCP"
        case .ringPIP: return "ringPIP"
        case .ringDIP: return "ringDIP"
        case .ringTip: return "ringTip"
        case .littleMCP: return "littleMCP"
        case .littlePIP: return "littlePIP"
        case .littleDIP: return "littleDIP"
        case .littleTip: return "littleTip"
        default: return "unknown"
        }
    }
    
    /// 从关键点数组提取扁平化特征向量（用于模型输入）
    /// - Parameter keypoints: 关键点数组
    /// - Returns: 特征向量 [x1, y1, x2, y2, ..., x21, y21]
    func extractFeatureVector(from keypoints: [HandKeypoint]) -> [Double] {
        var features: [Double] = []
        
        for keypoint in keypoints {
            features.append(Double(keypoint.location.x))
            features.append(Double(keypoint.location.y))
        }
        
        return features
    }
    
    /// 归一化关键点坐标（相对于手腕）
    /// - Parameter keypoints: 原始关键点
    /// - Returns: 归一化后的关键点
    func normalizeKeypoints(_ keypoints: [HandKeypoint]) -> [HandKeypoint] {
        guard !keypoints.isEmpty else { return [] }
        
        // 以手腕为参考点
        let wrist = keypoints[0].location
        
        return keypoints.map { keypoint in
            HandKeypoint(
                name: keypoint.name,
                location: CGPoint(
                    x: keypoint.location.x - wrist.x,
                    y: keypoint.location.y - wrist.y
                ),
                confidence: keypoint.confidence
            )
        }
    }
}

// MARK: - 左右手与单手结果

/// 用户真实左右手（已根据摄像头镜像做翻转校正）
enum HandChirality: String, CaseIterable {
    case left
    case right
}

/// 单只被检测到的手：带左右标记 + 21 个关键点
struct DetectedHand {
    let chirality: HandChirality
    let keypoints: [HandKeypoint]
}

// MARK: - Data Structures

/// 手部关键点数据结构
struct HandKeypoint {
    let name: String
    let location: CGPoint
    let confidence: Double
}

/// 手部姿态数据（包含完整的关键点序列）
struct HandPose {
    let keypoints: [HandKeypoint]
    let timestamp: Date
    
    /// 是否有效（至少检测到 50% 的关键点）
    var isValid: Bool {
        let validCount = keypoints.filter { $0.confidence > 0.3 }.count
        return Double(validCount) / Double(keypoints.count) > 0.5
    }
}
