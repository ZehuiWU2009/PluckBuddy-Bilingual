//
//  ScrollingTextView.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/7/29.
//

import SwiftUI

/// 滚动字幕视图 - 用于显示技法核心要求
struct ScrollingTextView: View {
    let text: String
    let technique: TechniqueType
    
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    
    // MARK: - 配置
    private let scrollSpeed: Double = 50 // 点/秒
    private let padding: CGFloat = 12
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                backgroundColor
                
                // 滚动文本
                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textGeometry in
                            Color.clear
                                .onAppear {
                                    textWidth = textGeometry.size.width
                                }
                                .onChange(of: text) { _, _ in
                                    // 文本改变时重新计算宽度
                                    textWidth = textGeometry.size.width
                                }
                        }
                    )
                    .offset(x: offset)
                    .onAppear {
                        startScrolling(containerWidth: geometry.size.width)
                    }
                    .onChange(of: technique) { _, _ in
                        // 技法改变时重启动画
                        resetScrolling(containerWidth: geometry.size.width)
                    }
            }
        }
        .frame(height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
    }
    
    // MARK: - 背景色
    private var backgroundColor: some View {
        technique.color
            .opacity(0.25)
            .overlay(
                LinearGradient(
                    colors: [
                        .white.opacity(0.1),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
    
    // MARK: - 滚动动画
    
    /// 启动滚动动画
    private func startScrolling(containerWidth: CGFloat) {
        // 从右侧进入
        offset = containerWidth
        
        // 计算滚动时长
        let totalDistance = containerWidth + textWidth
        let duration = totalDistance / scrollSpeed
        
        // 启动无限循环动画
        withAnimation(
            .linear(duration: duration)
            .repeatForever(autoreverses: false)
        ) {
            offset = -textWidth
        }
        
        print("📜 启动滚动字幕：\(technique.rawValue)")
        print("   - 文本宽度: \(Int(textWidth))pt")
        print("   - 滚动时长: \(String(format: "%.1f", duration))秒")
    }
    
    /// 重置滚动动画（技法切换时）
    private func resetScrolling(containerWidth: CGFloat) {
        // 停止当前动画
        withAnimation(.linear(duration: 0)) {
            offset = containerWidth
        }
        
        // 短暂延迟后重启
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startScrolling(containerWidth: containerWidth)
        }
        
        print("🔄 切换滚动字幕：\(technique.rawValue)")
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ScrollingTextView(
            text: TechniqueRequirementsManager.getScrollingText(for: .roll),
            technique: .roll
        )
        .padding()
        
        ScrollingTextView(
            text: TechniqueRequirementsManager.getScrollingText(for: .sweep),
            technique: .sweep
        )
        .padding()
        
        ScrollingTextView(
            text: TechniqueRequirementsManager.getScrollingText(for: .pluck),
            technique: .pluck
        )
        .padding()
    }
    .background(Color.black)
}
