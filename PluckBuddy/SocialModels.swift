//
//  SocialModels.swift
//  PluckBuddy
//
//  Created on 2026-09-08.
//  社交模块数据模型
//

import SwiftUI

// MARK: - 练习模式
enum PracticeMode {
    case running  // 弹挑跑步
    case flower   // 轮指花开
    case wave     // 扫弦水波
    
    var name: String {
        switch self {
        case .running: return L("弹挑跑步")
        case .flower: return L("轮指花开")
        case .wave: return L("扫弦水波")
        }
    }
}

// MARK: - 排行榜玩家
struct RankingPlayer: Identifiable {
    let id = UUID()
    let name: String
    let score: Int
    let practiceCount: Int
    let mode: PracticeMode
}

// MARK: - 成就类别
enum AchievementCategory: CaseIterable, Hashable {
    case beginner    // 新手
    case practice    // 练习
    case skill       // 技巧
    case persistence // 坚持
    
    var title: String {
        switch self {
        case .beginner: return L("新手入门")
        case .practice: return L("刻苦练习")
        case .skill: return L("技巧精湛")
        case .persistence: return L("持之以恒")
        }
    }
    
    var icon: String {
        switch self {
        case .beginner: return "star.fill"
        case .practice: return "flame.fill"
        case .skill: return "crown.fill"
        case .persistence: return "calendar.badge.clock"
        }
    }
    
    var color: Color {
        switch self {
        case .beginner: return .green
        case .practice: return .orange
        case .skill: return .purple
        case .persistence: return .blue
        }
    }
}

// MARK: - 成就
struct Achievement: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let category: AchievementCategory
    let unlocked: Bool
    let progress: Double  // 0.0 - 1.0
}

// MARK: - 好友
struct Friend: Identifiable {
    let id = UUID()
    let name: String
    let videoTitle: String
    let score: Int
    let speed: Int
    let stability: Int
    let thumbnailName: String?  // 预留视频缩略图
}

// MARK: - 模拟数据
struct MockData {
    // 玩家名字池
    private static let names = [
        L("琵琶大师"), L("音乐之星"), L("节奏高手"), L("练习达人"), L("弹拨高手"),
        L("轮指王者"), L("速度之王"), L("稳定狂魔"), L("勤奋小蜜蜂"), L("天才少女")
    ]
    
    // 根据排名和模式生成玩家数据
    static func getPlayer(for rank: Int, mode: PracticeMode) -> RankingPlayer {
        let baseScore: Int
        switch mode {
        case .running:
            baseScore = 5000 - (rank - 1) * 300
        case .flower:
            baseScore = 4500 - (rank - 1) * 280
        case .wave:
            baseScore = 4000 - (rank - 1) * 250
        }
        
        let name = rank <= names.count ? names[rank - 1] : L("玩家") + "\(rank)"
        let practiceCount = 100 - (rank - 1) * 5
        
        return RankingPlayer(
            name: name,
            score: baseScore,
            practiceCount: practiceCount,
            mode: mode
        )
    }
    
    // 成就数据
    static let achievements: [Achievement] = [
        // 新手入门
        Achievement(
            title: L("初次尝试"),
            description: L("完成第一次练习"),
            icon: "hand.wave.fill",
            category: .beginner,
            unlocked: true,
            progress: 1.0
        ),
        Achievement(
            title: L("小试身手"),
            description: L("完成10次练习"),
            icon: "star.circle.fill",
            category: .beginner,
            unlocked: true,
            progress: 1.0
        ),
        Achievement(
            title: L("熟能生巧"),
            description: L("完成50次练习"),
            icon: "sparkles",
            category: .beginner,
            unlocked: false,
            progress: 0.6
        ),
        Achievement(
            title: L("百炼成钢"),
            description: L("完成100次练习"),
            icon: "flame.circle.fill",
            category: .beginner,
            unlocked: false,
            progress: 0.3
        ),
        
        // 刻苦练习
        Achievement(
            title: L("勤奋之星"),
            description: L("连续练习7天"),
            icon: "calendar.badge.plus",
            category: .practice,
            unlocked: true,
            progress: 1.0
        ),
        Achievement(
            title: L("坚持不懈"),
            description: L("连续练习30天"),
            icon: "calendar.badge.checkmark",
            category: .practice,
            unlocked: false,
            progress: 0.4
        ),
        Achievement(
            title: L("马拉松选手"),
            description: L("单次练习30分钟"),
            icon: "figure.run",
            category: .practice,
            unlocked: false,
            progress: 0.7
        ),
        Achievement(
            title: L("时间管理大师"),
            description: L("累计练习10小时"),
            icon: "clock.badge.checkmark",
            category: .practice,
            unlocked: false,
            progress: 0.45
        ),
        
        // 技巧精湛
        Achievement(
            title: L("稳定高手"),
            description: L("稳定性达到90%"),
            icon: "waveform.path.ecg",
            category: .skill,
            unlocked: true,
            progress: 1.0
        ),
        Achievement(
            title: L("速度之王"),
            description: L("速度达到150 BPM"),
            icon: "gauge.badge.plus",
            category: .skill,
            unlocked: false,
            progress: 0.8
        ),
        Achievement(
            title: L("完美轮指"),
            description: L("轮指均匀度95%"),
            icon: "circle.grid.cross.fill",
            category: .skill,
            unlocked: false,
            progress: 0.55
        ),
        Achievement(
            title: L("技艺超群"),
            description: L("单次得分超过3000"),
            icon: "trophy.circle.fill",
            category: .skill,
            unlocked: false,
            progress: 0.65
        ),
        
        // 持之以恒
        Achievement(
            title: L("早起的鸟儿"),
            description: L("早晨6点前练习"),
            icon: "sunrise.fill",
            category: .persistence,
            unlocked: true,
            progress: 1.0
        ),
        Achievement(
            title: L("夜猫子"),
            description: L("晚上10点后练习"),
            icon: "moon.stars.fill",
            category: .persistence,
            unlocked: true,
            progress: 1.0
        ),
        Achievement(
            title: L("全能选手"),
            description: L("三种模式都练习过"),
            icon: "square.grid.3x3.fill",
            category: .persistence,
            unlocked: false,
            progress: 0.67
        ),
        Achievement(
            title: L("社交达人"),
            description: L("添加5位好友"),
            icon: "person.3.fill",
            category: .persistence,
            unlocked: false,
            progress: 0.4
        ),
    ]
    
    // 好友数据
    static let friends: [Friend] = [
        Friend(
            name: L("李小明"),
            videoTitle: L("轮指练习 - 100 BPM挑战"),
            score: 2350,
            speed: 105,
            stability: 88,
            thumbnailName: nil
        ),
        Friend(
            name: L("王晓芳"),
            videoTitle: L("弹挑速度训练记录"),
            score: 2150,
            speed: 120,
            stability: 85,
            thumbnailName: nil
        ),
        Friend(
            name: L("张伟"),
            videoTitle: L("扫弦水波 - 新手进阶"),
            score: 1950,
            speed: 95,
            stability: 90,
            thumbnailName: nil
        ),
        Friend(
            name: L("刘思雨"),
            videoTitle: L("轮指花开 - 稳定性提升"),
            score: 2280,
            speed: 110,
            stability: 92,
            thumbnailName: nil
        ),
        Friend(
            name: L("陈浩然"),
            videoTitle: L("弹挑跑步 - 速度突破"),
            score: 2420,
            speed: 125,
            stability: 87,
            thumbnailName: nil
        )
    ]
}
