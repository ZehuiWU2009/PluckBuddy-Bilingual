//
//  WelcomeView.swift
//  PluckBuddy
//
//  Created by 吴泽荟 on 2026/9/29.
//
//  启动欢迎页。展示 PluckBuddy 品牌标识与每日练习引导语，
//  倒计时 3 秒后自动进入主界面；右上角「跳过 3」可立即进入。
//

import SwiftUI

/// 启动欢迎页：居中展示 logo-English、练习引导语、功能副标题与底部开发者信息，
/// 倒计时 3 秒后自动进入主界面；右上角「跳过 3」可立即进入。
///
/// logo-English.png 自带米白底色（RGB 254/253/241）且不透明，所以整页背景取同一色值，
/// 图片边缘与页面无缝衔接。页面进出只用透明度过渡，避免切换时出现色块边界。
struct WelcomeView: View {
    /// 与 logo 底色一致的米白
    static let brandBackground = Color(red: 254.0 / 255.0, green: 253.0 / 255.0, blue: 241.0 / 255.0)
    /// 品牌深紫，用于引导语与跳过按钮
    private static let brandPurple = Color(red: 0.30, green: 0.24, blue: 0.55)
    
    /// 点击「跳过」或倒计时结束后调用，进入主界面
    let onEnter: () -> Void
    
    @State private var appeared = false
    /// 退出动画进行中，避免倒计时与「跳过」重复触发退出
    @State private var isDismissing = false
    /// 右上角读秒，每秒递减
    @State private var remaining = 3
    
    var body: some View {
        // ZStack 不设 alignment：内容整体居中。
        // 之前用 .topTrailing 会把没占满宽度的 VStack 一起靠右推，logo 就偏了。
        ZStack {
            Self.brandBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                
                // 品牌标识
                Image("LogoChinese")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 24)
                
                // 练习引导语
                Text(L("今天也来练 5 分钟吧！"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Self.brandPurple)
                    .padding(.top, 4)
                
                // 功能副标题
                Text(L("琵琶陪练 · AI 指法分析 · 智能调音"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Self.brandPurple.opacity(0.6))
                    .padding(.top, 6)
                
                Spacer(minLength: 0)
                
                // 开发者信息
                VStack(spacing: 3) {
                    Text(L("开发者：吴泽荟"))
                    Text(L("学校：武汉康礼高级中学"))
                }
                .font(.system(size: 12))
                .foregroundStyle(Self.brandPurple.opacity(0.55))
                .padding(.bottom, 40)
            }
            // 占满宽度，内部文本按自身居中，不受 ZStack 对齐方式影响
            .frame(maxWidth: .infinity)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .overlay(alignment: .topTrailing) {
            skipButton
                .padding(.top, 8)
                .padding(.trailing, 20)
                .opacity(appeared ? 1 : 0)
        }
        .task {
            withAnimation(.easeOut(duration: 0.7)) {
                appeared = true
            }
            // 逐秒读秒，归零后淡出进入主界面；视图消失时该 task 会被取消，不会重复触发
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                remaining -= 1
            }
            beginDismiss()
        }
    }
    
    /// 退出欢迎页：先让本页淡出（透明度 + 轻微缩放），动画结束后再通知父视图移除。
    /// 复制 onEnter 闭包异步调用，避免捕获 struct 视图自身。
    private func beginDismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        let enter = onEnter
        withAnimation(.easeInOut(duration: 0.5)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            enter()
        }
    }

    /// 右上角「跳过 3」胶囊按钮，点击立即进入主界面
    private var skipButton: some View {
        Button(action: beginDismiss) {
            HStack(spacing: 4) {
                Text(L("跳过"))
                Text("\(remaining)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: remaining)
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Self.brandPurple)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.9)))
            .overlay(
                Capsule()
                    .stroke(Self.brandPurple.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WelcomeView { }
}
