//
//  MetronomeView.swift
//  PluckBuddy
//
//  节拍器可视化组件
//  Created by Zehui Wu on 2026/8/29.
//

import SwiftUI

// MARK: - 主节拍器视图

/// 节拍器顶部栏（简化版 - 只显示和控制）
struct MetronomeBar: View {
    @ObservedObject var metronome: MetronomeManager
    let targetBPM: Int  // ✨ 只读，显示目标速度
    
    var body: some View {
        HStack(spacing: 16) {
            // 节拍灯
            BeatIndicatorView(
                currentBeat: metronome.currentBeat,
                totalBeats: metronome.beatsPerMeasure,
                isPlaying: metronome.isPlaying
            )
            .frame(width: 100)
            
            Spacer()
            
            // BPM 显示（只读）
            VStack(spacing: 4) {
                Text("\(targetBPM)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                
                Text("BPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80)
            
            Spacer()
            
            // 播放/暂停按钮
            Button(action: { metronome.toggle() }) {
                Image(systemName: metronome.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(metronome.isPlaying ? Color.orange : Color.green)
                    .clipShape(Circle())
                    .shadow(color: (metronome.isPlaying ? Color.orange : Color.green).opacity(0.3), radius: 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 节拍指示器

/// 节拍灯指示器（显示 4 个灯）
struct BeatIndicatorView: View {
    let currentBeat: Int
    let totalBeats: Int
    let isPlaying: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...totalBeats, id: \.self) { beat in
                Circle()
                    .fill(beatColor(for: beat))
                    .frame(width: 16, height: 16)
                    .shadow(
                        color: beatColor(for: beat).opacity(0.5),
                        radius: currentBeat == beat && isPlaying ? 6 : 0
                    )
                    .scaleEffect(currentBeat == beat && isPlaying ? 1.2 : 1.0)
                    .animation(.spring(response: 0.2), value: currentBeat)
            }
        }
    }
    
    private func beatColor(for beat: Int) -> Color {
        if !isPlaying {
            return Color.gray.opacity(0.3)
        }
        
        if beat == currentBeat {
            // 当前拍高亮
            return beat == 1 ? .red : .green
        } else {
            // 非当前拍暗淡
            return Color.gray.opacity(0.3)
        }
    }
}

// MARK: - 紧凑版节拍器（用于空间有限的界面）

/// 紧凑节拍器按钮
struct CompactMetronomeButton: View {
    @ObservedObject var metronome: MetronomeManager
    
    var body: some View {
        Button(action: { metronome.isEnabled.toggle() }) {
            HStack(spacing: 8) {
                Image(systemName: "metronome")
                    .foregroundStyle(metronome.isEnabled ? .green : .secondary)
                
                if metronome.isEnabled {
                    Text("\(metronome.bpm)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(metronome.isEnabled ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
            .clipShape(Capsule())
        }
    }
}

// MARK: - 预览

#Preview("节拍器栏") {
    VStack {
        MetronomeBar(metronome: MetronomeManager(), targetBPM: 120)
            .padding()
        
        Spacer()
    }
    .background(Color.gray.opacity(0.1))
}

#Preview("紧凑按钮") {
    CompactMetronomeButton(metronome: MetronomeManager())
        .padding()
}
