//
//  MainMenuExample.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026-09-08.
//  主界面集成示例 - 展示如何添加社交广场入口
//

import SwiftUI

// 这是一个示例文件，展示如何在主界面中集成社交广场模块
// 请根据你实际的主界面结构进行调整

struct MainMenuExample: View {
    @State private var showSocialSquare = false
    @State private var showFlowerPractice = false
    @State private var showRunningPractice = false
    @State private var showWavePractice = false
    @State private var showTuner = false
    @State private var showTechniqueCoach = false
    @State private var showMyResults = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // App 标题
                    headerSection
                    
                    // 功能网格
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        // 智能调音
                        MenuCard(
                            icon: "tuningfork",
                            title: L("智能调音"),
                            color: .blue,
                            action: { showTuner = true }
                        )
                        
                        // 弹挑跑步
                        MenuCard(
                            icon: "figure.run",
                            title: L("弹挑跑步"),
                            color: .green,
                            action: { showRunningPractice = true }
                        )
                        
                        // 轮指花开
                        MenuCard(
                            icon: "leaf.fill",
                            title: L("轮指花开"),
                            color: .pink,
                            action: { showFlowerPractice = true }
                        )
                        
                        // 扫弦水波
                        MenuCard(
                            icon: "waveform.path",
                            title: L("扫弦水波"),
                            color: .cyan,
                            action: { showWavePractice = true }
                        )
                        
                        // 智能指法教练
                        MenuCard(
                            icon: "video.fill",
                            title: L("智能指法教练"),
                            color: .orange,
                            action: { showTechniqueCoach = true }
                        )
                        
                        // 我的成绩
                        MenuCard(
                            icon: "chart.bar.fill",
                            title: L("我的成绩"),
                            color: .indigo,
                            action: { showMyResults = true }
                        )
                    }
                    
                    // 社交广场 - 特别展示（宽卡片）
                    socialSquareSection
                }
                .padding()
            }
            .navigationTitle("PluckBuddy")
            .background(Color(.systemGroupedBackground))
            
            // 全屏覆盖弹窗
            .fullScreenCover(isPresented: $showSocialSquare) {
                SocialSquareView()
            }
            .fullScreenCover(isPresented: $showFlowerPractice) {
                FlowerPracticeView()
            }
            .fullScreenCover(isPresented: $showRunningPractice) {
                RunningPracticeView()
            }
            // ... 其他视图的 fullScreenCover
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 50))
                .foregroundStyle(.blue.gradient)
            
            Text("PluckBuddy")
                .font(.system(size: 32, weight: .bold))
            
            Text(L("智能琵琶练习助手"))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical)
    }
    
    private var socialSquareSection: some View {
        Button(action: { showSocialSquare = true }) {
            HStack(spacing: 16) {
                // 图标
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                
                // 文字信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("社交广场"))
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("NEW")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                    }
                    
                    Text(L("排行榜 · 成就 · 好友PK"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "wifi.slash")
                            .font(.caption2)
                        Text(L("离线体验版"))
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.title3)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .purple.opacity(0.2), radius: 10, x: 0, y: 5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 菜单卡片组件
struct MenuCard: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.gradient)
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview
struct MainMenuExample_Previews: PreviewProvider {
    static var previews: some View {
        MainMenuExample()
    }
}
