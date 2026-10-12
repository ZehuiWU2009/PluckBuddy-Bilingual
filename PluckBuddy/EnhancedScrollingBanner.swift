//
//  EnhancedScrollingBanner.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/7/29.
//

import SwiftUI

/// 增强型滚动字幕 - 卡片轮播模式（可选方案）
struct EnhancedScrollingBanner: View {
    let technique: TechniqueType
    
    @State private var currentIndex = 0
    @State private var offset: CGFloat = 0
    @State private var timer: Timer?
    
    private let switchInterval: TimeInterval = 4.0 // 每4秒切换
    
    private var requirements: [String] {
        TechniqueRequirementsManager.getRequirements(for: technique)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 标题栏
            HStack {
                Image(systemName: technique.icon)
                    .foregroundStyle(technique.color)
                    .font(.title3)
                
                Text(String(format: L("%@核心要求"), technique.displayName))
                    .font(.subheadline)
                    .fontWeight(.bold)
                
                Spacer()
                
                // 进度指示
                Text("\(currentIndex + 1)/\(requirements.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            // 滚动内容区域
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(requirements.indices, id: \.self) { index in
                        RequirementCard(
                            text: requirements[index],
                            color: technique.color
                        )
                        .frame(width: geometry.size.width)
                    }
                }
                .offset(x: offset)
            }
            .frame(height: 60)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
        .onAppear {
            startAutoScroll()
        }
        .onDisappear {
            stopAutoScroll()
        }
        .onChange(of: technique) { _, _ in
            resetScroll()
        }
    }
    
    // MARK: - 自动滚动控制
    
    private func startAutoScroll() {
        timer = Timer.scheduledTimer(withTimeInterval: switchInterval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                scrollToNext()
            }
        }
        
        print("📋 启动要求轮播：\(technique.rawValue)")
    }
    
    private func stopAutoScroll() {
        timer?.invalidate()
        timer = nil
    }
    
    private func resetScroll() {
        stopAutoScroll()
        currentIndex = 0
        offset = 0
        startAutoScroll()
        
        print("🔄 重置要求轮播：\(technique.rawValue)")
    }
    
    private func scrollToNext() {
        currentIndex = (currentIndex + 1) % requirements.count
        offset = -CGFloat(currentIndex) * UIScreen.main.bounds.width
    }
}

// MARK: - 要求卡片

struct RequirementCard: View {
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(color)
                .font(.title2)
            
            // 文本
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        EnhancedScrollingBanner(technique: .roll)
            .padding()
        
        EnhancedScrollingBanner(technique: .sweep)
            .padding()
        
        EnhancedScrollingBanner(technique: .pluck)
            .padding()
    }
    .background(Color.black)
}
