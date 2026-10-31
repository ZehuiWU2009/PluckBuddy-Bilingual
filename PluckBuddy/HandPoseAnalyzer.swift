//
//  HandPoseAnalyzer.swift
//  PluckBuddy
//
//  手部姿态工具类 - 提供手部姿态平滑、可视化和几何计算工具
//  注意：HandPoseExtractor 和 HandKeypoint 已在 HandPoseExtractor.swift 中定义
//  注意：HandPoseData 和 HandPoseAnalyzer 已在 TechniqueCoachViewModel.swift 中定义
//  Created by Zehui Wu on 2026/8/31.
//

import Vision
import AVFoundation
import CoreImage
import UIKit
// MARK: - 手部姿态平滑器（卡尔曼滤波器）

/// 手部姿态平滑器 - 使用简化的卡尔曼滤波器减少抖动
/// 用于平滑手部关键点的位置，提高稳定性
class HandPoseSmoother {
    
    // MARK: - Kalman Filter State
    
    /// 每个关键点的卡尔曼滤波器状态
    private var filterStates: [String: KalmanFilterState] = [:]
    
    /// 卡尔曼滤波器状态
    private struct KalmanFilterState {
        var position: CGPoint
        var velocity: CGVector
        var lastUpdate: Date
    }
    
    // MARK: - Parameters
    
    /// 过程噪声协方差（值越大，越信任测量值）
    private let processNoise: CGFloat = 0.01
    
    /// 测量噪声协方差（值越大，越信任预测值）
    private let measurementNoise: CGFloat = 0.1
    
    // MARK: - Public Methods
    
    /// 平滑手部关键点位置
    /// - Parameter keypoints: 原始关键点数组
    /// - Returns: 平滑后的关键点数组
    func smooth(keypoints: [HandKeypoint]) -> [HandKeypoint] {
        let now = Date()
        
        return keypoints.map { keypoint in
            // 获取或创建滤波器状态
            if var state = filterStates[keypoint.name] {
                // 计算时间间隔
                let dt = CGFloat(now.timeIntervalSince(state.lastUpdate))
                
                // 预测步骤
                let predictedPosition = CGPoint(
                    x: state.position.x + state.velocity.dx * dt,
                    y: state.position.y + state.velocity.dy * dt
                )
                
                // 更新步骤（简化的卡尔曼增益计算）
                let kalmanGain = processNoise / (processNoise + measurementNoise)
                
                let smoothedPosition = CGPoint(
                    x: predictedPosition.x + kalmanGain * (keypoint.location.x - predictedPosition.x),
                    y: predictedPosition.y + kalmanGain * (keypoint.location.y - predictedPosition.y)
                )
                
                // 更新速度估计
                let newVelocity = CGVector(
                    dx: (smoothedPosition.x - state.position.x) / dt,
                    dy: (smoothedPosition.y - state.position.y) / dt
                )
                
                // 保存状态
                state.position = smoothedPosition
                state.velocity = newVelocity
                state.lastUpdate = now
                filterStates[keypoint.name] = state
                
                return HandKeypoint(
                    name: keypoint.name,
                    location: smoothedPosition,
                    confidence: keypoint.confidence
                )
                
            } else {
                // 首次检测到，初始化状态
                filterStates[keypoint.name] = KalmanFilterState(
                    position: keypoint.location,
                    velocity: .zero,
                    lastUpdate: now
                )
                return keypoint
            }
        }
    }
    
    /// 重置滤波器（当手部离开画面后调用）
    func reset() {
        filterStates.removeAll()
        print("🔄 已重置手部姿态平滑器")
    }
}

// MARK: - 手部姿态可视化（调试工具）

/// 手部姿态可视化工具 - 用于调试和展示
class HandPoseVisualizer {
    
    /// 在图像上绘制手部骨骼
    /// - Parameters:
    ///   - keypoints: 手部关键点
    ///   - imageSize: 图像尺寸
    /// - Returns: 带有骨骼标注的图像
    static func drawSkeleton(
        keypoints: [HandKeypoint],
        imageSize: CGSize
    ) -> UIImage? {
        // 创建绘图上下文
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        // 设置绘图属性
        context.setStrokeColor(UIColor.systemPink.cgColor)
        context.setLineWidth(2.0)
        context.setLineCap(.round)
        
        // 定义手部骨骼连接关系
        let connections: [(String, String)] = [
            // 手腕到各手指根部
            ("wrist", "thumbCMC"),
            ("wrist", "indexMCP"),
            ("wrist", "middleMCP"),
            ("wrist", "ringMCP"),
            ("wrist", "littleMCP"),
            
            // 拇指
            ("thumbCMC", "thumbMP"),
            ("thumbMP", "thumbIP"),
            ("thumbIP", "thumbTip"),
            
            // 食指
            ("indexMCP", "indexPIP"),
            ("indexPIP", "indexDIP"),
            ("indexDIP", "indexTip"),
            
            // 中指
            ("middleMCP", "middlePIP"),
            ("middlePIP", "middleDIP"),
            ("middleDIP", "middleTip"),
            
            // 无名指
            ("ringMCP", "ringPIP"),
            ("ringPIP", "ringDIP"),
            ("ringDIP", "ringTip"),
            
            // 小指
            ("littleMCP", "littlePIP"),
            ("littlePIP", "littleDIP"),
            ("littleDIP", "littleTip")
        ]
        
        // 创建关键点查找字典
        let keypointDict = Dictionary(
            uniqueKeysWithValues: keypoints.map { ($0.name, $0.location) }
        )
        
        // 绘制连接线
        for (start, end) in connections {
            guard let startLoc = keypointDict[start],
                  let endLoc = keypointDict[end] else {
                continue
            }
            
            // Vision 坐标系转换到 UIKit 坐标系
            let startPoint = CGPoint(
                x: startLoc.x * imageSize.width,
                y: (1 - startLoc.y) * imageSize.height
            )
            let endPoint = CGPoint(
                x: endLoc.x * imageSize.width,
                y: (1 - endLoc.y) * imageSize.height
            )
            
            context.move(to: startPoint)
            context.addLine(to: endPoint)
            context.strokePath()
        }
        
        // 绘制关键点
        context.setFillColor(UIColor.systemBlue.cgColor)
        for keypoint in keypoints {
            let point = CGPoint(
                x: keypoint.location.x * imageSize.width,
                y: (1 - keypoint.location.y) * imageSize.height
            )
            
            // 根据置信度调整点的大小
            let radius = CGFloat(4 + keypoint.confidence * 3)
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            
            context.fillEllipse(in: rect)
        }
        
        // 获取结果图像
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image
    }
}

// MARK: - 手部特征计算工具

/// 手部特征计算工具 - 提供常用的几何计算
enum HandGeometry {
    
    /// 计算两点之间的欧几里得距离
    static func distance(from point1: CGPoint, to point2: CGPoint) -> Double {
        let dx = Double(point2.x - point1.x)
        let dy = Double(point2.y - point1.y)
        return hypot(dx, dy)
    }
    
    /// 计算向量的角度（弧度）
    static func angle(from point1: CGPoint, to point2: CGPoint) -> Double {
        let dx = Double(point2.x - point1.x)
        let dy = Double(point2.y - point1.y)
        return atan2(dy, dx)
    }
    
    /// 计算三点之间的夹角（弧度）
    /// - Parameters:
    ///   - point1: 第一个点
    ///   - vertex: 顶点
    ///   - point2: 第二个点
    /// - Returns: 夹角（0 到 π）
    static func angle(point1: CGPoint, vertex: CGPoint, point2: CGPoint) -> Double {
        let vector1 = CGVector(
            dx: point1.x - vertex.x,
            dy: point1.y - vertex.y
        )
        let vector2 = CGVector(
            dx: point2.x - vertex.x,
            dy: point2.y - vertex.y
        )
        
        let dotProduct = Double(vector1.dx * vector2.dx + vector1.dy * vector2.dy)
        let magnitude1 = hypot(Double(vector1.dx), Double(vector1.dy))
        let magnitude2 = hypot(Double(vector2.dx), Double(vector2.dy))
        
        guard magnitude1 > 0, magnitude2 > 0 else { return 0 }
        
        let cosAngle = dotProduct / (magnitude1 * magnitude2)
        return acos(max(-1, min(1, cosAngle)))
    }
    
    /// 判断手指是否弯曲
    /// - Parameters:
    ///   - mcp: 掌指关节
    ///   - pip: 近端指间关节
    ///   - dip: 远端指间关节
    ///   - tip: 指尖
    /// - Returns: 是否弯曲
    static func isFingerBent(mcp: CGPoint, pip: CGPoint, dip: CGPoint, tip: CGPoint) -> Bool {
        // 计算三个关节的夹角
        let angle1 = angle(point1: mcp, vertex: pip, point2: dip)
        let angle2 = angle(point1: pip, vertex: dip, point2: tip)
        
        // 如果夹角小于 150 度（2.618 弧度），认为手指弯曲
        return angle1 < 2.618 || angle2 < 2.618
    }
}

