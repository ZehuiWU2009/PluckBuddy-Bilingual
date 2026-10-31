//
//  TechniqueRequirementsManager.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/7/29.
//

import Foundation

/// 技法要求管理器 - 提供各种技法的核心要求内容
class TechniqueRequirementsManager {
    
    // MARK: - 核心要求内容库
    
    /// 获取指定技法的核心要求列表
    static func getRequirements(for technique: TechniqueType) -> [String] {
        switch technique {
        case .roll:
            return [
                L("✅ 保持手腕放松，不要过度抬起"),
                L("✅ 四指（食、中、无名、小）依次快速弹出"),
                L("✅ 每个手指独立运动，避免连带"),
                L("✅ 触弦角度 45-60 度为佳"),
                L("✅ 保持匀速，节奏稳定最重要"),
                L("✅ 手指自然弯曲，不要僵硬"),
                L("✅ 从慢到快循序渐进练习"),
                L("✅ 注意音量均衡，避免某指过轻或过重")
            ]
            
        case .sweep:
            return [
                L("✅ 手臂带动，整体发力，不只是手腕"),
                L("✅ 保持动作流畅连贯，一气呵成"),
                L("✅ 扫弦轨迹呈弧线，不要直线硬扫"),
                L("✅ 触弦深度适中，不要过深或过浅"),
                L("✅ 上行下行力度一致"),
                L("✅ 肩部放松，避免耸肩"),
                L("✅ 呼吸配合动作，节奏自然"),
                L("✅ 多指同时触弦，声音饱满")
            ]
            
        case .pluck:
            return [
                L("✅ 手指第一关节主动发力"),
                L("✅ 触弦后迅速离弦，动作干净利落"),
                L("✅ 弹挑交替时保持匀速节奏"),
                L("✅ 手腕自然摆动配合，幅度不宜过大"),
                L("✅ 拇指弹：向外拨弦，力量来自第一关节"),
                L("✅ 食指挑：向内勾弦，发力点在指尖"),
                L("✅ 保持肩、臂、腕放松，力量集中在指尖"),
                L("✅ 音色清晰明亮，避免闷音")
            ]
            
        case .unknown:
            return [
                L("💡 请开始弹奏，系统将自动识别您的练习指法"),
                L("💡 确保光线充足，手部清晰可见"),
                L("💡 建议将摄像头放置在侧前方 45° 角")
            ]
        }
    }
    
    /// 获取完整的滚动文本（用于滚动字幕）
    /// - Parameter technique: 技法类型
    /// - Returns: 拼接后的完整文本（带分隔符）
    static func getScrollingText(for technique: TechniqueType) -> String {
        let requirements = getRequirements(for: technique)
        let separator = "  •  "
        
        // 拼接所有要求，并在末尾添加分隔符以实现循环
        return requirements.joined(separator: separator) + separator
    }
    
    /// 获取指定序号的要求（用于轮播模式）
    /// - Parameters:
    ///   - index: 要求序号
    ///   - technique: 技法类型
    /// - Returns: 单条要求文本
    static func getRequirement(at index: Int, for technique: TechniqueType) -> String? {
        let requirements = getRequirements(for: technique)
        guard index >= 0 && index < requirements.count else {
            return nil
        }
        return requirements[index]
    }
    
    /// 获取要求总数
    static func getRequirementsCount(for technique: TechniqueType) -> Int {
        return getRequirements(for: technique).count
    }
}

// MARK: - 扩展：智能推荐（可选）

extension TechniqueRequirementsManager {
    
    /// 根据评估结果智能排序要求（未来实现）
    /// 优先显示用户需要改进的方面
    static func getPrioritizedRequirements(
        for technique: TechniqueType,
        weakAspects: [String] = []
    ) -> [String] {
        // TODO: 根据弱项调整顺序
        // 目前返回默认顺序
        return getRequirements(for: technique)
    }
}
