//
//  FlowerSettingsSheet.swift
//  PluckBuddy
//
//  Created by 吴泽荟（Zehui Wu） on 2026/8/31.
//

import SwiftUI

struct FlowerSettingsSheet: View {
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
                    // 目标速度（BPM）
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L("目标速度"))
                                .font(.headline)
                            Spacer()
                            Text("\(Int(targetBPM)) BPM")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                        
                        Slider(value: $targetBPM, in: Double(MetronomeManager.minimumBPM)...Double(MetronomeManager.maximumBPM), step: 1)
                            .tint(.blue)
                        
                        HStack {
                            Text("\(MetronomeManager.minimumBPM)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(MetronomeManager.maximumBPM)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
                    Text(L("设置您的练习目标速度和时长"))
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
                        Text(L("节拍器将以您设定的目标速度播放，帮助您保持稳定的节奏"))
                    } else {
                        Text(L("开启节拍器以获得节奏辅助"))
                    }
                }
                
                // MARK: - 说明
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(
                            icon: "hand.tap.fill",
                            title: L("轮指计数"),
                            description: L("记录您每次完成的轮指动作")
                        )
                        
                        Divider()
                        
                        InfoRow(
                            icon: "rectangle.3.group",
                            title: L("序列质量"),
                            description: L("评估每个轮指序列的完成质量")
                        )
                        
                        Divider()
                        
                        InfoRow(
                            icon: "star.fill",
                            title: L("得分系统"),
                            description: L("根据速度、均匀度和质量获得分数")
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
                .foregroundStyle(.blue)
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
    FlowerSettingsSheet(
        targetBPM: .constant(120),
        targetDuration: .constant(300),
        metronomeEnabled: .constant(true),
        metronomeSoundType: .constant(.tick)
    )
}
