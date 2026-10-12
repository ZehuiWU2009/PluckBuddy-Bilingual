//
//  LanguageSettingView.swift
//  PluckBuddy
//
//  语言选择页：跟随系统 / 中文 / English
//

import SwiftUI

struct LanguageSettingView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(AppLanguage.allCases) { option in
                    Button {
                        lang.selection = option.rawValue
                        lang.apply()
                    } label: {
                        HStack {
                            Text(option.label)
                            Spacer()
                            if lang.current == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("语言"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("完成")) { dismiss() }
                }
            }
        }
    }
}

#Preview {
    LanguageSettingView()
        .environmentObject(LanguageManager.shared)
}
