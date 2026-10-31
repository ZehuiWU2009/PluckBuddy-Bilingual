//
//  AchievementView.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026-09-08.
//  成就勋章视图
//

import SwiftUI

struct AchievementView: View {
    let achievements = MockData.achievements
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 总览卡片
                achievementSummary
                
                // 成就分类
                ForEach(AchievementCategory.allCases, id: \.self) { category in
                    categorySection(category)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private var achievementSummary: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("我的成就"))
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(L("继续努力解锁更多勋章"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text("\(achievements.filter { $0.unlocked }.count)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.blue)
                    
                    Text("/ \(achievements.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * progress, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8)
        )
    }
    
    private var progress: CGFloat {
        let unlocked = achievements.filter { $0.unlocked }.count
        return CGFloat(unlocked) / CGFloat(achievements.count)
    }
    
    private func categorySection(_ category: AchievementCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(category.color)
                Text(category.title)
                    .font(.headline)
            }
            .padding(.horizontal, 4)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(achievements.filter { $0.category == category }) { achievement in
                    SocialAchievementCard(achievement: achievement)
                }
            }
        }
    }
}

// MARK: - 成就卡片
struct SocialAchievementCard: View {
    let achievement: Achievement
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if achievement.unlocked {
                    Circle()
                        .fill(achievement.category.color.gradient)
                        .frame(width: 70, height: 70)
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 70, height: 70)
                }
                
                Image(systemName: achievement.icon)
                    .font(.system(size: 32))
                    .foregroundColor(achievement.unlocked ? .white : .gray)
            }
            
            VStack(spacing: 4) {
                Text(achievement.title)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(achievement.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            
            if achievement.unlocked {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(L("已解锁"))
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            } else {
                ProgressView(value: achievement.progress)
                    .tint(achievement.category.color)
                    .frame(height: 4)
                
                Text("\(Int(achievement.progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
        .opacity(achievement.unlocked ? 1.0 : 0.6)
    }
}

// MARK: - Preview
struct AchievementView_Previews: PreviewProvider {
    static var previews: some View {
        AchievementView()
    }
}
