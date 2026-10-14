import Foundation

/// Text-only instruction templates are deliberately separate from the base completion renderer.
/// Automatic selection uses a bounded GGUF header read, not a filename guess. Rendered control
/// tokens are passed to the native instruction tokenizer, which recognizes them as actual tokens.
nonisolated enum LearningLocalPrompt {
    static func resolve(_ template: LearningChatTemplate, modelURL: URL) throws -> LearningChatTemplate {
        guard template == .automatic else { return template }
        let metadata = try modelMetadata(modelURL)
        switch metadata.architecture {
        case "hunyuan-dense":
            // Hy-MT2 7B has the same architecture as 1.8B but a different tokenizer/turn format.
            // Read its embedded format rather than assuming all sizes share the older tokens.
            return metadata.chatTemplate?.contains("<|extra_0|>") == true ? .hyMT7 : .hyMT
        case "qwen35", "qwen3", "qwen3moe": return .qwen3
        case "qwen2": return modelURL.lastPathComponent.lowercased().contains("qwen3") ? .qwen3 : .chatML
        case "gemma4":
            let name = modelURL.lastPathComponent.lowercased()
            guard name.contains("e2b") || name.contains("e4b") else {
                throw LearningFailure.message(String(localized: """
                Gemma 4 model variants use different templates. Choose the template for your model variant.
                """,
                    table: "Learning", comment: """
                    Guidance shown when a Gemma 4 GGUF does not identify which variant-specific instruction template to use.
                    """))
            }
            return .gemma4
        case "gemma3":
            // Architecture alone cannot distinguish Gemma 3 chat from its translation specialist.
            // Prefer embedded provenance so renaming a downloaded file does not change its task.
            if metadata.name?.lowercased().contains("translategemma") == true ||
                modelURL.lastPathComponent.lowercased().contains("translategemma") { return .translateGemma }
            return .gemma3
        case "gemma3n", "gemma2", "gemma": return .gemma3
        case "llama": return .llama3
        default:
            throw LearningFailure.message(String(localized: """
            Could not detect this GGUF's instruction template automatically. Choose one in Model settings.
            """,
                table: "Learning", comment: "Guidance shown when automatic instruction-template detection fails for a local GGUF model."))
        }
    }

    static func render(_ text: String, template: LearningChatTemplate) throws -> String {
        let (prefix, suffix) = try delimiters(template)
        return prefix + text + suffix
    }

    /// Check the actual tokenizer result, including chat framing. The shared native allocation
    /// is larger than TranslateGemma's documented 2K input limit; allocation size is not proof
    /// that a specialist was trained for longer input. Reject rather than silently truncate.
    static func validateTokenBudget(input: Int, output: Int, template: LearningChatTemplate) throws {
        if template == .translateGemma, input > 2_048 {
            throw LearningFailure.message(String(localized: "TranslateGemma input exceeds 2,048 tokens. Split the text into smaller parts.",
                table: "Learning", comment: "Error shown when input exceeds TranslateGemma's supported token budget."))
        }
        guard input > 0, output > 0, input < 8_192, output < 8_192 - input else {
            throw LearningFailure.message(String(localized: """
            The source text and output budget exceed the local model's context limit. Split the text into smaller parts.
            """,
                table: "Learning", comment: """
                Error shown when the source text plus requested output exceeds the local model context window.
                """))
        }
    }

    static func delimiters(_ template: LearningChatTemplate) throws -> (String, String) {
        // The caller tokenizes these trusted delimiters as special tokens and the payload as
        // literal text. This preserves code/HTML and prevents payload from creating model turns.
        switch template {
        case .hyMT: return ("<｜hy_begin▁of▁sentence｜><｜hy_User｜>", "<｜hy_Assistant｜>")
        case .hyMT7: return ("<|startoftext|>", "<|extra_0|>")
        case .chatML: return ("<|im_start|>user\n", "<|im_end|>\n<|im_start|>assistant\n")
        case .qwen3: return ("<|im_start|>user\n", "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
        case .gemma4: return ("<bos><|turn>user\n", "<turn|>\n<|turn>model\n")
        case .gemma4Large: return ("<bos><|turn>user\n", "<turn|>\n<|turn>model\n<|channel>thought\n<channel|>")
        case .gemma3, .translateGemma: return ("<bos><start_of_turn>user\n", "<end_of_turn>\n<start_of_turn>model\n")
        case .llama3: return ("<|begin_of_text|><|start_header_id|>user<|end_header_id|>\n\n", "<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n")
        case .automatic:
            throw LearningFailure.message(String(localized: "The instruction template has not been identified.",
                table: "Learning", comment: """
                Error shown when an automatic instruction template could not be resolved before local generation.
                """))
        }
    }

    private static func modelMetadata(_ url: URL) throws -> (architecture: String, name: String?, chatTemplate: String?) {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        // Tokenizer arrays can precede chat_template. Buffer the bounded header so inspecting
        // them does not make a separate filesystem call for every token/string in the vocabulary.
        var buffer = Data(), cursor = 0, consumed = 0, loaded = 0
        func read(_ count: Int) throws -> Data {
            guard count >= 0, count <= 16_000_000, count <= 32_000_000 - consumed else {
                throw LearningFailure.message(String(localized: "GGUF metadata is incomplete or exceeds the supported read limit.",
                    table: "Learning", comment: "Error shown when GGUF metadata is missing or larger than the parser's safe limit."))
            }
            if buffer.count - cursor < count {
                buffer = buffer.subdata(in: cursor..<buffer.count)
                cursor = 0
                while buffer.count < count {
                    let request = min(32_000_000 - loaded, max(65_536, count - buffer.count))
                    guard request > 0, let part = try file.read(upToCount: request), !part.isEmpty else {
                        throw LearningFailure.message(String(localized: "GGUF metadata is incomplete or exceeds the supported read limit.",
                            table: "Learning", comment: """
                            Error shown when GGUF metadata is missing or larger than the parser's safe limit.
                            """))
                    }
                    loaded += part.count
                    buffer.append(part)
                }
            }
            let data = buffer.subdata(in: cursor..<(cursor + count))
            cursor += count
            consumed += count
            return data
        }
        func integer(_ bytes: Int) throws -> UInt64 {
            let data = try read(bytes)
            return data.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
        }
        func string() throws -> String {
            let length = try integer(8)
            guard length <= 16_000_000 else {
                throw LearningFailure.message(String(localized: "A GGUF metadata string is too long.",
                    table: "Learning", comment: "Error shown when a GGUF metadata string exceeds the supported read size."))
            }
            return String(decoding: try read(Int(length)), as: UTF8.self)
        }
        func skip(_ type: UInt64) throws {
            let lengths: [UInt64: Int] = [0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8]
            if type == 8 {
                let length = try integer(8)
                guard length <= 16_000_000 else {
                    throw LearningFailure.message(String(localized: "A GGUF metadata string is too long.",
                        table: "Learning", comment: "Error shown when a GGUF metadata string exceeds the supported read size."))
                }
                _ = try read(Int(length))
            }
            else if type == 9 {
                let subtype = try integer(4), count = try integer(8)
                guard count <= 1_000_000, subtype != 9 else {
                    throw LearningFailure.message(String(localized: "A GGUF metadata array is invalid.",
                        table: "Learning", comment: "Error shown when GGUF metadata contains an unsupported or oversized array."))
                }
                if let length = lengths[subtype] { _ = try read(Int(count) * length) }
                else { for _ in 0..<count { try skip(subtype) } }
            } else if let length = lengths[type] { _ = try read(length) }
            else {
                throw LearningFailure.message(String(localized: "A GGUF metadata type is invalid.",
                    table: "Learning", comment: "Error shown when GGUF metadata contains a type this parser cannot read."))
            }
        }
        guard try read(4) == Data("GGUF".utf8), [2, 3].contains(try integer(4)) else {
            throw LearningFailure.message(String(localized: "This is not a supported GGUF file.",
                table: "Learning", comment: "Error shown when a selected file is not a GGUF model supported by this app."))
        }
        _ = try integer(8)
        let count = try integer(8)
        guard count <= 100_000 else {
            throw LearningFailure.message(String(localized: "The GGUF metadata count is invalid.",
                table: "Learning", comment: "Error shown when a GGUF file declares more metadata entries than the parser supports."))
        }
        var architecture: String?, name: String?, chatTemplate: String?
        for _ in 0..<count {
            let key = try string(), type = try integer(4)
            if key == "general.architecture", type == 8 { architecture = try string() }
            else if key == "general.name", type == 8 { name = try string() }
            else if key == "tokenizer.chat_template", type == 8 { chatTemplate = try string() }
            else { try skip(type) }
            // Most GGUFs put these fields first. Other families do not need the name, avoiding
            // a scan of the tokenizer arrays on every request. Gemma 3 needs its name; Hy-MT
            // needs its embedded template to distinguish incompatible tokenizer generations.
            if let architecture {
                let enough = architecture == "hunyuan-dense" ? chatTemplate != nil :
                    architecture != "gemma3" || name != nil
                if enough { return (architecture, name, chatTemplate) }
            }
        }
        if let architecture { return (architecture, name, chatTemplate) }
        throw LearningFailure.message(String(localized: "The GGUF file is missing model architecture information.",
            table: "Learning", comment: "Error shown when GGUF metadata does not identify the model architecture."))
    }
}
