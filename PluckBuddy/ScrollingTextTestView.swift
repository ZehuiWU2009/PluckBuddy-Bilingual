//
//  ScrollingTextTestView.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/7/29.
//

import SwiftUI

/// 滚动字幕测试视图 - 用于独立测试滚动效果
struct ScrollingTextTestView: View {
    @State private var selectedTechnique: TechniqueType = .roll
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                // 技法选择器
                VStack(spacing: 12) {
                    Text(L("选择技法查看要求"))
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Picker(L("技法"), selection: $selectedTechnique) {
                        Text(L("🎵 轮指")).tag(TechniqueType.roll)
                        Text(L("🌊 扫弦")).tag(TechniqueType.sweep)
                        Text(L("🎸 弹挑")).tag(TechniqueType.pluck)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // 技法图标和名称
                VStack(spacing: 12) {
                    Image(systemName: selectedTechnique.icon)
                        .font(.system(size: 80))
                        .foregroundStyle(selectedTechnique.color)
                    
                    Text(selectedTechnique.displayName)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    
                    Text(selectedTechnique.description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
                
                // 滚动字幕区域
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                        Text(L("核心要求 - 简洁滚动条"))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // 简洁滚动条
                    ScrollingTextView(
                        text: TechniqueRequirementsManager.getScrollingText(
                            for: selectedTechnique
                        ),
                        technique: selectedTechnique
                    )
                    .frame(height: 50)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // 卡片轮播（备选方案）
                VStack(spacing: 8) {
                    Text(L("备选方案 - 卡片轮播"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    
                    EnhancedScrollingBanner(technique: selectedTechnique)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // 说明文字
                VStack(spacing: 8) {
                    Text(L("💡 提示"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.yellow)
                    
                    Text(L("切换上方选择器查看不同技法的核心要求"))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .padding(.top, 20)
        }
        .navigationTitle(L("滚动字幕测试"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ScrollingTextTestView()
    }
}
