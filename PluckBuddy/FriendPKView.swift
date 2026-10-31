//
//  FriendPKView.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026-09-08.
//  好友PK视图
//

import SwiftUI
import AVKit

struct FriendPKView: View {
    @State private var friends = MockData.friends
    @State private var selectedFriend: Friend?
    @State private var showVideoDetail = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 说明横幅
                infoBanner
                
                // 好友列表
                ForEach(friends) { friend in
                    FriendPKCard(friend: friend) {
                        selectedFriend = friend
                        showVideoDetail = true
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showVideoDetail) {
            if let friend = selectedFriend {
                FriendVideoDetailView(friend: friend)
            }
        }
    }
    
    private var infoBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text(L("好友PK说明"))
                    .font(.headline)
            }
            
            Text(L("好友可以上传练习视频，与你比拼技巧。点击卡片查看好友的练习视频和数据对比。"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
    }
}

// MARK: - 好友PK卡片
struct FriendPKCard: View {
    let friend: Friend
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                // 头部信息
                HStack(spacing: 12) {
                    // 好友头像
                    Circle()
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Text(String(friend.name.prefix(1)))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(friend.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                                .font(.caption)
                            Text(friend.videoTitle)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                
                Divider()
                
                // 数据对比
                HStack(spacing: 0) {
                    statColumn(title: L("分数"), value: "\(friend.score)", color: .blue)
                    
                    Divider()
                        .frame(height: 50)
                    
                    statColumn(title: L("速度"), value: "\(friend.speed) BPM", color: .orange)
                    
                    Divider()
                        .frame(height: 50)
                    
                    statColumn(title: L("稳定性"), value: "\(friend.stability)%", color: .green)
                }
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 5)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func statColumn(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 好友视频详情视图
struct FriendVideoDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let friend: Friend
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 视频占位符（实际项目中可以播放真实视频）
                    videoPlaceholder
                    
                    // 好友信息
                    friendInfoSection
                    
                    // 数据对比
                    comparisonSection
                    
                    // 评论区占位
                    commentSection
                }
                .padding()
            }
            .navigationTitle(L("好友视频"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("完成")) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var videoPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(Color.black)
                .aspectRatio(16/9, contentMode: .fit)
                .cornerRadius(12)
            
            VStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
                
                Text(L("点击播放视频"))
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text(L("(离线模式暂不支持)"))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    private var friendInfoSection: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(friend.name.prefix(1)))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(friend.name)
                    .font(.headline)
                
                Text(friend.videoTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(L("3天前上传"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("数据对比"))
                .font(.headline)
            
            VStack(spacing: 12) {
                comparisonRow(title: L("得分"), myValue: "1850", friendValue: "\(friend.score)", unit: L("分"))
                comparisonRow(title: L("速度"), myValue: "115", friendValue: "\(friend.speed)", unit: "BPM")
                comparisonRow(title: L("稳定性"), myValue: "82", friendValue: "\(friend.stability)", unit: "%")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
    }
    
    private func comparisonRow(title: String, myValue: String, friendValue: String, unit: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(L("我"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(myValue) \(unit)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue)
            }
            
            Text("vs")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(friendValue) \(unit)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.purple)
            }
        }
    }
    
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("评论"))
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<3) { index in
                    commentRow(username: L("用户") + "\(index + 1)", comment: L("弹得真好！向你学习 🎵"))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            
            Text(L("评论功能在线版本中可用"))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    private func commentRow(username: String, comment: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 30, height: 30)
                .overlay(
                    Text(String(username.prefix(1)))
                        .font(.caption)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(username)
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text(comment)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview
struct FriendPKView_Previews: PreviewProvider {
    static var previews: some View {
        FriendPKView()
    }
}
