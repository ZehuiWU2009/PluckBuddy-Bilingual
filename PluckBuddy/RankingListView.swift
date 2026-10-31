//
//  RankingListView.swift
//  PluckBuddy
//
//  Created by Zehui Wu on 2026-09-08.
//  排行榜视图
//

import SwiftUI

struct RankingListView: View {
    @State private var selectedMode: PracticeMode = .running
    
    var body: some View {
        VStack(spacing: 0) {
            // 模式选择器
            modePicker
            
            // 离线提示横幅
            offlineBanner
            
            // 排行榜列表
            ScrollView {
                VStack(spacing: 12) {
                    // 前三名特殊展示
                    topThreeSection
                    
                    // 其他排名
                    ForEach(4...10, id: \.self) { rank in
                        RankingRow(
                            rank: rank,
                            player: MockData.getPlayer(for: rank, mode: selectedMode),
                            isCurrentUser: rank == 7
                        )
                    }
                }
                .padding()
            }
        }
    }
    
    private var modePicker: some View {
        Picker(L("练习模式"), selection: $selectedMode) {
            Text(L("弹挑跑步")).tag(PracticeMode.running)
            Text(L("轮指花开")).tag(PracticeMode.flower)
            Text(L("扫弦水波")).tag(PracticeMode.wave)
        }
        .pickerStyle(.segmented)
        .padding()
    }
    
    private var offlineBanner: some View {
        HStack {
            Image(systemName: "wifi.slash")
                .foregroundColor(.orange)
            Text(L("离线模拟数据 · 仅供演示"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
    
    private var topThreeSection: some View {
        HStack(alignment: .bottom, spacing: 16) {
            // 第二名
            TopPlayerCard(rank: 2, player: MockData.getPlayer(for: 2, mode: selectedMode))
            
            // 第一名（高亮）
            TopPlayerCard(rank: 1, player: MockData.getPlayer(for: 1, mode: selectedMode))
                .padding(.bottom, 20)
            
            // 第三名
            TopPlayerCard(rank: 3, player: MockData.getPlayer(for: 3, mode: selectedMode))
        }
        .padding(.vertical)
    }
}

// MARK: - 前三名卡片
struct TopPlayerCard: View {
    let rank: Int
    let player: RankingPlayer
    
    var medalColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .clear
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 奖牌
            ZStack {
                Circle()
                    .fill(medalColor.gradient)
                    .frame(width: rank == 1 ? 60 : 50, height: rank == 1 ? 60 : 50)
                
                Image(systemName: "crown.fill")
                    .foregroundColor(.white)
                    .font(.system(size: rank == 1 ? 24 : 20))
            }
            
            // 排名数字
            Text("\(rank)")
                .font(.system(size: rank == 1 ? 20 : 16, weight: .bold))
                .foregroundColor(medalColor)
            
            // 头像
            Circle()
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: rank == 1 ? 70 : 60, height: rank == 1 ? 70 : 60)
                .overlay(
                    Text(String(player.name.prefix(1)))
                        .font(.system(size: rank == 1 ? 28 : 24, weight: .bold))
                        .foregroundColor(.white)
                )
            
            // 名字
            Text(player.name)
                .font(.system(size: rank == 1 ? 16 : 14, weight: .semibold))
                .lineLimit(1)
            
            // 分数
            Text("\(player.score)")
                .font(.system(size: rank == 1 ? 24 : 20, weight: .bold))
                .foregroundColor(.blue)
            
            Text(L("分"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: medalColor.opacity(0.3), radius: rank == 1 ? 10 : 5)
        )
    }
}

// MARK: - 排名行
struct RankingRow: View {
    let rank: Int
    let player: RankingPlayer
    let isCurrentUser: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // 排名
            Text("\(rank)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(isCurrentUser ? .blue : .secondary)
                .frame(width: 30)
            
            // 头像
            Circle()
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(player.name.prefix(1)))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                )
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(player.name)
                        .font(.system(size: 16, weight: .semibold))
                    
                    if isCurrentUser {
                        Text(L("(我)"))
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                Text(L("练习") + " \(player.practiceCount) " + L("次"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 分数
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(player.score)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.blue)
                Text(L("分"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrentUser ? Color.blue.opacity(0.05) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrentUser ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Preview
struct RankingListView_Previews: PreviewProvider {
    static var previews: some View {
        RankingListView()
    }
}
