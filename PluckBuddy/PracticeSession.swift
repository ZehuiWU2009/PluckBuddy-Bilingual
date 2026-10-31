//
//  PracticeSession.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/7/16.
//

import Foundation
import CoreData

/// 练习会话数据模型
@objc(PracticeSession)
public class PracticeSession: NSManagedObject {
    
    @NSManaged public var id: UUID
    @NSManaged public var sessionType: String // "tuner", "running", "flower", "wave"
    @NSManaged public var startTime: Date
    @NSManaged public var endTime: Date
    @NSManaged public var duration: Double // 秒
    
    // 通用统计
    @NSManaged public var score: Int32
    @NSManaged public var notes: String? // 备注
    
    // 调音器专用
    @NSManaged public var tuningAccuracy: Double // 平均音准准确度
    @NSManaged public var tuningCount: Int32 // 调音次数
    
    // 弹挑跑步专用
    @NSManaged public var pluckCount: Int32 // 弹拨次数
    @NSManaged public var averageBPM: Double // 平均速度
    @NSManaged public var stability: Double // 节奏稳定性
    @NSManaged public var distance: Double // 跑步距离（米）
    
    // 轮指花开专用
    @NSManaged public var rollCount: Int32 // 轮指次数
    @NSManaged public var rollSpeed: Double // 平均速度
    
    // 扫弦水波专用
    @NSManaged public var sweepCount: Int32 // 扫弦次数
    @NSManaged public var averageStrength: Double // 平均力度
}

extension PracticeSession {
    
    /// 获取会话的类型名称
    var typeName: String {
        switch sessionType {
        case "tuner": return L("智能调音")
        case "running": return L("弹挑跑步")
        case "flower": return L("轮指花开")
        case "wave": return L("扫弦水波")
        default: return L("未知")
        }
    }
    
    /// 获取会话的图标
    var icon: String {
        switch sessionType {
        case "tuner": return "🎵"
        case "running": return "🏃"
        case "flower": return "🌸"
        case "wave": return "🌊"
        default: return "📝"
        }
    }
    
    /// 格式化的时长
    var formattedDuration: String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
    
    /// 格式化的日期
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: startTime)
    }
}

// MARK: - Fetch Request
extension PracticeSession {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PracticeSession> {
        return NSFetchRequest<PracticeSession>(entityName: "PracticeSession")
    }
    
    /// 获取所有会话，按时间倒序
    static func allSessionsRequest() -> NSFetchRequest<PracticeSession> {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PracticeSession.startTime, ascending: false)]
        return request
    }
    
    /// 获取特定类型的会话
    static func sessionsRequest(type: String) -> NSFetchRequest<PracticeSession> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "sessionType == %@", type)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PracticeSession.startTime, ascending: false)]
        return request
    }
    
    /// 获取最近 N 天的会话
    static func recentSessionsRequest(days: Int) -> NSFetchRequest<PracticeSession> {
        let request = fetchRequest()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        request.predicate = NSPredicate(format: "startTime >= %@", startDate as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PracticeSession.startTime, ascending: false)]
        return request
    }
}
