//
//  HomeView.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/7/15.
//

import SwiftUI

struct HomeView: View {
    @State private var showLangSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部固定的品牌标题，不随功能列表滚动
                brandHeader
                
                Divider()
                
                // 功能列表
                ScrollView {
                    VStack(spacing: 16) {
                        // 智能调音
                        NavigationLink {
                            TunerView()
                        } label: {
                            FeatureCard(
                                icon: "🎵",
                                title: L("智能调音"),
                                subtitle: L("琵琶四弦定音助手"),
                                color: .blue
                            )
                        }
                        
                        // 弹挑跑步
                        NavigationLink {
                            RunningPracticeView()
                        } label: {
                            FeatureCard(
                                icon: "🏃",
                                title: L("弹挑跑步"),
                                subtitle: L("弹挑练习变身跑步游戏"),
                                color: .green
                            )
                        }
                        
                        // 轮指花开
                        NavigationLink {
                            FlowerPracticeView()
                        } label: {
                            FeatureCard(
                                icon: "🌸",
                                title: L("轮指花开"),
                                subtitle: L("轮指练习看花朵绽放"),
                                color: .pink
                            )
                        }
                        
                        // 扫弦水波
                        NavigationLink {
                            WavePracticeView()
                        } label: {
                            FeatureCard(
                                icon: "🌊",
                                title: L("扫弦水波"),
                                subtitle: L("扫弦力量可视化"),
                                color: .cyan
                            )
                        }
                        
                        // 智能指法教练（新增）
                        NavigationLink {
                            TechniqueCoachView()
                        } label: {
                            FeatureCard(
                                icon: "🎥",
                                title: L("智能指法教练"),
                                subtitle: L("AI 实时分析你的演奏质量"),
                                color: .purple
                            )
                        }
                        
                        // 我的成绩
                        NavigationLink {
                            ResultView()
                        } label: {
                            FeatureCard(
                                icon: "🏆",
                                title: L("我的成绩"),
                                subtitle: L("查看练习历史与进步"),
                                color: .orange
                            )
                        }
                        
                        // 社交广场（新增）
                        NavigationLink {
                            SocialSquareView()
                        } label: {
                            FeatureCard(
                                icon: "👥",
                                title: L("社交广场"),
                                subtitle: L("排行榜 · 成就 · 好友PK\n（离线版）"),
                                color: .purple
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                }
            }
            .background(Color(.systemGroupedBackground))
            // 首页只保留七大功能模块，顶部标题栏整体隐藏；
            // push 进子页面后各页自带 navigationTitle，返回按钮不受影响
            .toolbar(.hidden, for: .navigationBar)
        }
    }
    
    // MARK: - 顶部品牌标题
    
    /// 固定在列表上方，不随 ScrollView 滚动
    private var brandHeader: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.55, green: 0.36, blue: 0.90), Color(red: 0.23, green: 0.51, blue: 0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 26)
            
            Text(L("弹拨搭子"))
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button {
                showLangSheet = true
            } label: {
                Image(systemName: "globe")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
            }
            .sheet(isPresented: $showLangSheet) {
                LanguageSettingView()
                    .environmentObject(LanguageManager.shared)
            }
            .padding(.trailing, 8)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(.systemBackground))
    }
}

// MARK: - Feature Card Component
struct FeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            // 图标
            Text(icon)
                .font(.system(size: 40))
                .frame(width: 60, height: 60)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // 文字
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    // 显式指定左侧对齐：卡片给文字留的宽度不足时会换行，
                    // 不锁定的话多行文本会回退到居中
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
            
            // 箭头
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.body.weight(.semibold))
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    HomeView()
}
