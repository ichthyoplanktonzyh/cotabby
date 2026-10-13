import SwiftUI

/// Presents the cross-language learning controls from the app-owned settings model.
/// The shared settings object owns persistence; this section only edits language choices,
/// the two independent model profiles, and the detail shortcut.
struct LanguageLearningSection: View {
    @ObservedObject var settings: LanguageLearningSettings
    let suggestionSettings: SuggestionSettingsModel
    var configureModel: (LearningModelRole) -> Void = { _ in }
    @State private var recording = false
    @State private var sourceLanguagesExpanded = false

    var body: some View {
        Section("跨语言表达学习") {
            Toggle("启用跨语言翻译", isOn: $settings.translationEnabled)
            Toggle("输入停顿后自动显示整句表达", isOn: $settings.sentencePreviewEnabled)
                .disabled(!settings.translationEnabled)
            translationControls
            Text(
                "照常输入并确认候选词上屏，停顿后会在旁边显示目标表达；" +
                "开启语块对应后，对应结果随后准备；按快捷键展开原文与译文；" +
                "点击语块查看两侧表达，再点击单词打开系统词典浮窗。译文可直接双击单词查词。" +
                "不要求特定品牌输入法，也不需要切换到 ABC 键盘。" +
                "翻译与语块对应分别配置模型，支持内置 GGUF 或独立 Endpoint。"
            )
                .font(.caption).foregroundStyle(.secondary)
            Text("学习请求不包含屏幕、剪贴板或输入历史。")
                .font(.caption).foregroundStyle(.secondary)
            LearningModelSummaryRow(title: "翻译模型", profile: settings.translation) {
                configureModel(.translation)
            }
            Toggle("启用语块对应", isOn: $settings.analysisEnabled)
                .disabled(!settings.translationEnabled)
            Text("关闭语块对应后仍可阅读译文、对照原文和查词。对应任务只摘取片段，不重新翻译或生成解释。")
                .font(.caption).foregroundStyle(.secondary)
            LearningModelSummaryRow(title: "语块对应模型", profile: settings.analysis) {
                configureModel(.analysis)
            }
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
            DisclosureGroup("源语言（可选多个，当前 \(settings.sourceLanguages.count) 个）",
                            isExpanded: sourceExpansionBinding) {
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
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
    }

    /// Expansion is presentation state, not a persisted language preference. Its height change
    /// reaches the grouped Form and outer ScrollView; animating that change can repeatedly alter
    /// the scroller's document proportions. Apply the transaction at the binding write so the
    /// parent layout receives it too, without changing animations in other settings controls.
    private var sourceExpansionBinding: Binding<Bool> {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        return $sourceLanguagesExpanded.transaction(transaction)
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

/// Writing shows the role's current selection and a route into Engine & Model. It observes the
/// app-owned profile, while the navigation owner performs the jump. No model services or editable
/// server/key fields live in this summary, so there is one configuration surface per task.
private struct LearningModelSummaryRow: View {
    let title: String
    @ObservedObject var profile: LearningModelSettings
    let configure: () -> Void

    var body: some View {
        LabeledContent {
            Button("配置模型", action: configure)
                .help("在 Engine & Model 中配置\(title)")
                .accessibilityLabel("配置\(title)")
        } label: {
            SettingsRowLabel(title: title, description: summary, systemImage: "shippingbox")
        }
    }

    private var summary: String {
        switch profile.backend {
        case .local:
            "内置 GGUF · \(profile.localModel.isEmpty ? "尚未选择模型" : profile.localModel)"
        case .endpoint:
            "Endpoint · \(profile.endpointModel.isEmpty ? "尚未填写模型" : profile.endpointModel)"
        }
    }
}
