import Foundation

/// Text-only instruction templates are deliberately separate from the base completion renderer.
/// Automatic selection uses a bounded GGUF header read, not a filename guess. Rendered control
/// tokens are passed to the native instruction tokenizer, which recognizes them as actual tokens.
nonisolated enum LearningLocalPrompt {
    static func resolve(_ template: LearningChatTemplate, modelURL: URL) throws -> LearningChatTemplate {
        guard template == .automatic else { return template }
        switch try architecture(modelURL) {
        case "hunyuan-dense": return .hyMT
        case "qwen35", "qwen3", "qwen3moe": return .qwen3
        case "qwen2": return modelURL.lastPathComponent.lowercased().contains("qwen3") ? .qwen3 : .chatML
        case "gemma4":
            let name = modelURL.lastPathComponent.lowercased()
            guard name.contains("e2b") || name.contains("e4b") else {
                throw LearningFailure.message("Gemma 4 不同规格的模板不同，请手动选择对应规格的指令模板。")
            }
            return .gemma4
        case "gemma3", "gemma3n", "gemma2", "gemma": return .gemma3
        case "llama": return .llama3
        default: throw LearningFailure.message("无法自动识别此 GGUF 的指令模板，请在模型设置中选择模板。")
        }
    }

    static func render(_ text: String, template: LearningChatTemplate) throws -> String {
        let (prefix, suffix) = try delimiters(template)
        return prefix + text + suffix
    }

    static func delimiters(_ template: LearningChatTemplate) throws -> (String, String) {
        // The caller tokenizes these trusted delimiters as special tokens and the payload as
        // literal text. This preserves code/HTML and prevents payload from creating model turns.
        switch template {
        case .hyMT: return ("<｜hy_begin▁of▁sentence｜><｜hy_User｜>", "<｜hy_Assistant｜>")
        case .chatML: return ("<|im_start|>user\n", "<|im_end|>\n<|im_start|>assistant\n")
        case .qwen3: return ("<|im_start|>user\n", "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
        case .gemma4: return ("<bos><|turn>user\n", "<turn|>\n<|turn>model\n")
        case .gemma4Large: return ("<bos><|turn>user\n", "<turn|>\n<|turn>model\n<|channel>thought\n<channel|>")
        case .gemma3: return ("<bos><start_of_turn>user\n", "<end_of_turn>\n<start_of_turn>model\n")
        case .llama3: return ("<|begin_of_text|><|start_header_id|>user<|end_header_id|>\n\n", "<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n")
        case .automatic: throw LearningFailure.message("指令模板尚未识别。")
        }
    }

    private static func architecture(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        func read(_ count: Int) throws -> Data {
            guard count >= 0, count <= 16_000_000, file.offsetInFile + UInt64(count) <= 32_000_000,
                  let data = try file.read(upToCount: count), data.count == count else {
                throw LearningFailure.message("GGUF 元数据不完整或超过读取范围。")
            }
            return data
        }
        func integer(_ bytes: Int) throws -> UInt64 {
            let data = try read(bytes)
            return data.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
        }
        func string() throws -> String {
            let length = try integer(8)
            guard length <= 16_000_000 else { throw LearningFailure.message("GGUF 字符串过长。") }
            return String(decoding: try read(Int(length)), as: UTF8.self)
        }
        func skip(_ type: UInt64) throws {
            let lengths: [UInt64: Int] = [0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8]
            if type == 8 { _ = try string() }
            else if type == 9 {
                let subtype = try integer(4), count = try integer(8)
                guard count <= 1_000_000, subtype != 9 else { throw LearningFailure.message("GGUF 数组无效。") }
                if let length = lengths[subtype] { _ = try read(Int(count) * length) }
                else { for _ in 0..<count { try skip(subtype) } }
            } else if let length = lengths[type] { _ = try read(length) }
            else { throw LearningFailure.message("GGUF 元数据类型无效。") }
        }
        guard try read(4) == Data("GGUF".utf8), [2, 3].contains(try integer(4)) else {
            throw LearningFailure.message("不是支持的 GGUF 文件。")
        }
        _ = try integer(8)
        let count = try integer(8)
        guard count <= 100_000 else { throw LearningFailure.message("GGUF 元数据数量无效。") }
        for _ in 0..<count {
            let key = try string(), type = try integer(4)
            if key == "general.architecture", type == 8 { return try string() }
            try skip(type)
        }
        throw LearningFailure.message("GGUF 缺少模型架构信息。")
    }
}
