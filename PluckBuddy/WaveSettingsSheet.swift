//
//  WaveSettingsSheet.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/8/31.
//

import SwiftUI

struct WaveSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var targetBPM: Double
    @Binding var targetDuration: TimeInterval
    @Binding var metronomeEnabled: Bool
    @Binding var metronomeSoundType: MetronomeSoundType
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 目标设置
                Section {
                    // 目标速度（BPM）- 扫弦通常较慢
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L("目标速度"))
                                .font(.headline)
                            Spacer()
                            Text("\(Int(targetBPM)) BPM")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.cyan)
                        }
                        
                        Slider(value: $targetBPM, in: Double(MetronomeManager.minimumBPM)...Double(MetronomeManager.maximumBPM), step: 1)
                            .tint(.cyan)
                        
                        HStack {
                            Text("\(MetronomeManager.minimumBPM)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(MetronomeManager.maximumBPM)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        // 速度建议
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text(speedSuggestion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                    
                    // 目标时长
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L("目标时长"))
                                .font(.headline)
                            Spacer()
                            if targetDuration > 0 {
                                Text(durationText)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
                            } else {
                                Text(L("不限"))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Picker(L("时长"), selection: $targetDuration) {
                            Text(L("不限")).tag(TimeInterval(0))
                            Text(L("1 分钟")).tag(TimeInterval(60))
                            Text(L("3 分钟")).tag(TimeInterval(180))
                            Text(L("5 分钟")).tag(TimeInterval(300))
                            Text(L("10 分钟")).tag(TimeInterval(600))
                            Text(L("15 分钟")).tag(TimeInterval(900))
                            Text(L("20 分钟")).tag(TimeInterval(1200))
                            Text(L("30 分钟")).tag(TimeInterval(1800))
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                    
                } header: {
                    Label(L("练习目标"), systemImage: "target")
                } footer: {
                    Text(L("设置您的扫弦练习目标速度和时长"))
                }
                
                // MARK: - 节拍器设置
                Section {
                    // 节拍器开关
                    Toggle(isOn: $metronomeEnabled) {
                        HStack {
                            Image(systemName: "metronome")
                                .foregroundStyle(.orange)
                            Text(L("启用节拍器"))
                                .font(.headline)
                        }
                    }
                    .tint(.orange)
                    
                    // 节拍器音色（仅在启用时显示）
                    if metronomeEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L("节拍器音色"))
                                .font(.headline)
                            
                            Picker(L("音色"), selection: $metronomeSoundType) {
                                ForEach(MetronomeSoundType.allCases) { type in
                                    HStack {
                                        Image(systemName: type.icon)
                                        Text(type.displayName)
                                    }
                                    .tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                } header: {
                    Label(L("节拍器"), systemImage: "speaker.wave.2")
                } footer: {
                    if metronomeEnabled {
                        Text(L("节拍器将以您设定的目标速度播放，帮助您保持稳定的扫弦节奏"))
                    } else {
                        Text(L("开启节拍器以获得节奏辅助"))
                    }
                }
                
                // MARK: - 技巧提示
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        TipRow(
                            icon: "arrow.up.arrow.down",
                            title: L("练习两个方向"),
                            description: L("向上扫和向下扫都要练习，保持方向平衡")
                        )
                        
                        Divider()
                        
                        TipRow(
                            icon: "bolt.fill",
                            title: L("控制力度"),
                            description: L("尝试保持稳定的扫弦力度，避免忽强忽弱")
                        )
                        
                        Divider()
                        
                        TipRow(
                            icon: "waveform.path",
                            title: L("节奏稳定"),
                            description: L("跟随节拍器练习，逐步提高速度")
                        )
                    }
                } header: {
                    Label(L("练习技巧"), systemImage: "star.fill")
                }
                
                // MARK: - 说明
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(
                            icon: "waveform",
                            title: L("扫弦检测"),
                            description: L("自动识别向上和向下的扫弦动作")
                        )
                        
                        Divider()
                        
                        InfoRow(
                            icon: "drop.fill",
                            title: L("水波效果"),
                            description: L("根据扫弦力度生成不同大小的水波")
                        )
                        
                        Divider()
                        
                        InfoRow(
                            icon: "star.fill",
                            title: L("得分系统"),
                            description: L("根据力度和方向平衡获得分数")
                        )
                    }
                } header: {
                    Label(L("功能说明"), systemImage: "info.circle")
                }
            }
            .navigationTitle(L("练习设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("完成")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Helper Properties
    
    private var durationText: String {
        let minutes = Int(targetDuration / 60)
        if minutes < 60 {
            return "\(minutes) " + L("分钟")
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) " + L("小时")
            } else {
                return "\(hours) " + L("小时") + " \(remainingMinutes) " + L("分钟")
            }
        }
    }
    
    private var speedSuggestion: String {
        let bpm = Int(targetBPM)
        switch bpm {
        case 0..<50:
            return L("极慢 - 适合初学者基础练习")
        case 50..<70:
            return L("慢速 - 适合稳定性练习")
        case 70..<90:
            return L("中慢速 - 适合基础扫弦")
        case 90..<110:
            return L("中速 - 适合日常练习")
        case 110..<140:
            return L("中快速 - 适合进阶练习")
        case 140..<170:
            return L("快速 - 适合高级练习")
        default:
            return L("极快 - 适合专业级练习")
        }
    }
}

// MARK: - Info Row Component

private struct InfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.cyan)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Tip Row Component

private struct TipRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WaveSettingsSheet(
        targetBPM: .constant(60),
        targetDuration: .constant(300),
        metronomeEnabled: .constant(true),
        metronomeSoundType: .constant(.tick)
    )
}
