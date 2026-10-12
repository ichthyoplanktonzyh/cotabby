import SwiftUI

/// Presents the cross-language learning controls from the app-owned settings model.
/// The shared settings object owns persistence; this section only edits language choices,
/// the endpoint model name, the shortcut, and the opt-in passive word hint.
struct LanguageLearningSection: View {
    @ObservedObject var settings: LanguageLearningSettings
    let suggestionSettings: SuggestionSettingsModel
    @State private var recording = false
    @State private var hintsExpanded = false

    var body: some View {
        Section("跨语言表达学习") {
            Toggle("启用跨语言表达学习", isOn: $settings.translationEnabled)
            Toggle("输入停顿后自动显示整句表达", isOn: $settings.sentencePreviewEnabled)
                .disabled(!settings.translationEnabled)
            translationControls
            Text(
                "照常输入并确认候选词上屏，停顿后会在旁边显示目标表达；" +
                "语块对应随后准备，按快捷键展开同色对应的原文与译文；" +
                "点击语块打开说明小窗，再选择单词查询系统词典。" +
                "不要求特定品牌输入法，也不需要切换到 ABC 键盘。" +
                "学习请求使用此处指定的模型和 Engine & Model 中配置的 Endpoint；" +
                "它可以连接本机服务或 HTTPS 远程服务。"
            )
                .font(.caption).foregroundStyle(.secondary)
            Text("学习请求不包含屏幕、剪贴板或输入历史。")
                .font(.caption).foregroundStyle(.secondary)
            TextField("学习模型名称（独立模型，需要 Chat API）", text: $settings.model)
            HStack {
                Text("展开学习详情：\(settings.keyLabel)")
                if recording {
                    KeyRecorderView(onKeyRecorded: { code, modifiers, label in
                        settings.keyCode = code
                        settings.modifiers = modifiers
                        settings.keyLabel = label
                        recording = false
                    }, onCancelled: { recording = false }, conflictChecker: conflict)
                } else {
                    Button("更改") { recording = true }
                }
            }
            if settings.translationEnabled,
               let reason = conflict(settings.keyCode, settings.modifiers) {
                Text("快捷键与\(reason)冲突，请更改")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("自动预览仅处理开启后当前字段的新输入，不会因切换到已有文本而自动发送。" +
                 "停顿触发预览，句末标点和换行划分句子；继续补充同一句时更新该句。" +
                 "学习浮层不修改原文，Tab 和 Enter 保持正常输入；Esc 收起。" +
                 "关闭自动预览后，可按快捷键预览当前选区或句子。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var translationControls: some View {
        Group {
            Picker("目标语言", selection: $settings.targetLanguage) {
                ForEach(LearningLanguage.allCases) { Text($0.label).tag($0) }
            }
            DisclosureGroup("源语言（可选多个，当前 \(settings.sourceLanguages.count) 个）") {
                ForEach(LearningLanguage.allCases) { language in
                    Toggle(language.label, isOn: Binding(
                        get: { settings.sourceLanguages.contains(language) },
                        set: { enabled in
                            settings.sourceLanguages.removeAll { $0 == language }
                            if enabled { settings.sourceLanguages.append(language) }
                        }
                    )).disabled(language == settings.targetLanguage)
                }
                Text("只选一个源语言时，按所选方向翻译；" +
                     "选择多个时，会根据本次原文自动判断，判断不确定时请调整设置或选择更长文本。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("可选：被动词语轻提示（关闭整句预览时）", isExpanded: $hintsExpanded) {
                Toggle("输入后显示词语轻提示", isOn: $settings.hintsEnabled)
                    .disabled(!settings.translationEnabled || settings.sentencePreviewEnabled)
                Text("默认关闭。只有编辑器能确认新文字已提交时，停顿后才会提示当前词语；有些编辑器无法提供这种证据，因此会跳过提示。" +
                     "开启后只处理之后观察到的提交变化，不会追溯提示此前输入的词。继续输入、切换焦点或按 Esc 会收起提示；Enter 保持正常输入。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func conflict(_ code: UInt16, _ modifiers: ShortcutModifierMask) -> String? {
        if code == 36 || code == 76 || code == 53 || modifiers.isEmpty { return "请用带修饰键的快捷键，保留 Enter/Esc" }
        for action in ShortcutAction.allCases {
            if let conflict = suggestionSettings.conflictingShortcutName(
                keyCode: code, modifiers: modifiers, excluding: action, includingLearningShortcut: false
            ) {
                return conflict
            }
        }
        for override in suggestionSettings.perAppShortcutOverrides {
            if let conflict = suggestionSettings.conflictingPerAppShortcutName(
                forBundleIdentifier: override.bundleIdentifier, keyCode: code, modifiers: modifiers,
                excluding: .toggleTabby, includingLearningShortcut: false
            ) { return conflict }
        }
        return nil
    }
}
