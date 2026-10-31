//
//  PracticeDataManager.swift
//  PluckBuddy
//
//  Created by Zehui Wu on 2026/7/16.
//

import Foundation
import CoreData
import Combine

/// 练习数据管理器
@MainActor
class PracticeDataManager: ObservableObject {
    static let shared = PracticeDataManager()
    
    private let viewContext: NSManagedObjectContext
    
    // MARK: - Published Statistics
    @Published var totalSessions: Int = 0
    @Published var totalDuration: TimeInterval = 0 // 总时长（秒）
    @Published var totalScore: Int = 0
    @Published var currentStreak: Int = 0 // 连续练习天数
    
    private init() {
        self.viewContext = PersistenceController.shared.container.viewContext
        updateStatistics()
    }
    
    // MARK: - Create Session
    
    /// 创建调音会话记录
    func saveTuningSession(
        duration: TimeInterval,
        accuracy: Double,
        tuningCount: Int
    ) {
        let session = PracticeSession(context: viewContext)
        session.id = UUID()
        session.sessionType = "tuner"
        session.startTime = Date().addingTimeInterval(-duration)
        session.endTime = Date()
        session.duration = duration
        session.score = Int32(calculateTuningScore(accuracy: accuracy, count: tuningCount))
        session.tuningAccuracy = accuracy
        session.tuningCount = Int32(tuningCount)
        
        saveContext()
    }
    
    /// 创建弹挑跑步会话记录
    func saveRunningSession(
        duration: TimeInterval,
        pluckCount: Int,
        averageBPM: Double,
        stability: Double,
        distance: Double,
        score: Int
    ) {
        let session = PracticeSession(context: viewContext)
        session.id = UUID()
        session.sessionType = "running"
        session.startTime = Date().addingTimeInterval(-duration)
        session.endTime = Date()
        session.duration = duration
        session.score = Int32(score)
        session.pluckCount = Int32(pluckCount)
        session.averageBPM = averageBPM
        session.stability = stability
        session.distance = distance
        
        saveContext()
    }
    
    /// 创建轮指花开会话记录
    func saveFlowerSession(
        duration: TimeInterval,
        rollCount: Int,
        rollSpeed: Double,
        score: Int
    ) {
        let session = PracticeSession(context: viewContext)
        session.id = UUID()
        session.sessionType = "flower"
        session.startTime = Date().addingTimeInterval(-duration)
        session.endTime = Date()
        session.duration = duration
        session.score = Int32(score)
        session.rollCount = Int32(rollCount)
        session.rollSpeed = rollSpeed
        
        saveContext()
    }
    
    /// 创建扫弦水波会话记录
    func saveWaveSession(
        duration: TimeInterval,
        sweepCount: Int,
        averageStrength: Double,
        score: Int
    ) {
        let session = PracticeSession(context: viewContext)
        session.id = UUID()
        session.sessionType = "wave"
        session.startTime = Date().addingTimeInterval(-duration)
        session.endTime = Date()
        session.duration = duration
        session.score = Int32(score)
        session.sweepCount = Int32(sweepCount)
        session.averageStrength = averageStrength
        
        saveContext()
    }
    
    // MARK: - Fetch Sessions
    
    /// 获取所有会话
    func fetchAllSessions() -> [PracticeSession] {
        let request = PracticeSession.allSessionsRequest()
        return (try? viewContext.fetch(request)) ?? []
    }
    
    /// 获取特定类型的会话
    func fetchSessions(type: String) -> [PracticeSession] {
        let request = PracticeSession.sessionsRequest(type: type)
        return (try? viewContext.fetch(request)) ?? []
    }
    
    /// 获取最近 N 天的会话
    func fetchRecentSessions(days: Int) -> [PracticeSession] {
        let request = PracticeSession.recentSessionsRequest(days: days)
        return (try? viewContext.fetch(request)) ?? []
    }
    
    // MARK: - Statistics
    
    /// 更新统计数据
    func updateStatistics() {
        let sessions = fetchAllSessions()
        
        totalSessions = sessions.count
        totalDuration = sessions.reduce(0) { $0 + $1.duration }
        totalScore = sessions.reduce(0) { $0 + Int($1.score) }
        currentStreak = calculateCurrentStreak(sessions: sessions)
        
        objectWillChange.send()
    }
    
    /// 计算连续练习天数
    private func calculateCurrentStreak(sessions: [PracticeSession]) -> Int {
        guard !sessions.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        let sortedSessions = sessions.sorted { $0.startTime > $1.startTime }
        
        var streak = 0
        var currentDate = calendar.startOfDay(for: Date())
        
        for session in sortedSessions {
            let sessionDate = calendar.startOfDay(for: session.startTime)
            
            if sessionDate == currentDate {
                streak = max(streak, 1)
            } else if sessionDate == calendar.date(byAdding: .day, value: -1, to: currentDate) {
                streak += 1
                currentDate = sessionDate
            } else {
                break
            }
        }
        
        return streak
    }
    
    /// 计算调音得分
    private func calculateTuningScore(accuracy: Double, count: Int) -> Int {
        let baseScore = count * 10
        let accuracyBonus = Int(accuracy * 100)
        return baseScore + accuracyBonus
    }
    
    /// 获取每日练习统计（最近 7 天）
    func getDailyStats(days: Int = 7) -> [DailyStats] {
        let sessions = fetchRecentSessions(days: days)
        let calendar = Calendar.current
        
        var statsDict: [Date: DailyStats] = [:]
        
        // 初始化最近 N 天的数据
        for i in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let dayStart = calendar.startOfDay(for: date)
                statsDict[dayStart] = DailyStats(date: dayStart, sessionCount: 0, totalDuration: 0, totalScore: 0)
            }
        }
        
        // 填充实际数据
        for session in sessions {
            let dayStart = calendar.startOfDay(for: session.startTime)
            if var stats = statsDict[dayStart] {
                stats.sessionCount += 1
                stats.totalDuration += session.duration
                stats.totalScore += Int(session.score)
                statsDict[dayStart] = stats
            }
        }
        
        return statsDict.values.sorted { $0.date < $1.date }
    }
    
    // MARK: - Delete
    
    /// 删除会话
    func deleteSession(_ session: PracticeSession) {
        viewContext.delete(session)
        saveContext()
    }
    
    /// 删除所有会话
    func deleteAllSessions() {
        let sessions = fetchAllSessions()
        sessions.forEach { viewContext.delete($0) }
        saveContext()
    }
    
    // MARK: - Private
    
    private func saveContext() {
        if viewContext.hasChanges {
            do {
                try viewContext.save()
                updateStatistics()
            } catch {
                print("Failed to save context: \(error)")
            }
        }
    }
}

// MARK: - DailyStats
struct DailyStats: Identifiable {
    let id = UUID()
    let date: Date
    var sessionCount: Int
    var totalDuration: TimeInterval
    var totalScore: Int
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
    
    var weekday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}
