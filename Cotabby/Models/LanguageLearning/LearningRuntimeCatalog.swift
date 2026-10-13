import Foundation

/// Task-specific recommendations share the existing download manager and GGUF directory. Keeping
/// this list separate prevents translation specialists from becoming recommended base completions.
nonisolated enum LearningRuntimeCatalog {
    /// Shared storage must not make a downloaded translation specialist the fallback completion
    /// model. Keep custom imports eligible; only our task-specific catalog entries are excluded.
    static func isCompletionCandidate(filename: String) -> Bool {
        !(translationModels + analysisModels).contains { $0.filename.caseInsensitiveCompare(filename) == .orderedSame }
    }
    static let translationModels = [DownloadableRuntimeModel(
        filename: "Hy-MT2-1.8B-Q4_K_M.gguf", displayName: "Hy-MT2 1.8B · 轻量翻译",
        downloadURL: URL(string: "https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/resolve/a0c709d9fac510f2c807aa3af52872340dc37a4a/Hy-MT2-1.8B-Q4_K_M.gguf?download=true")!,
        approximateSizeInGigabytes: 1.13, expectedSizeBytes: 1_133_080_448,
        sha256: "dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699",
        recommendation: "33 种语言 · 轻量默认候选，适合输入停顿后的句子翻译。"), DownloadableRuntimeModel(
        filename: "Hy-MT2-7B-Q4_K_M.gguf", displayName: "Hy-MT2 7B · 质量优先候选",
        downloadURL: URL(string: "https://huggingface.co/tencent/Hy-MT2-7B-GGUF/resolve/ab8472660ac61fac25f1af43fac2599d52a8a775/Hy-MT2-7B-Q4_K_M.gguf?download=true")!,
        approximateSizeInGigabytes: 4.62, expectedSizeBytes: 4_624_648_896,
        sha256: "9f96256500f3fc1ab4d64336b58f52a949a95ad7516b0c229476eef782f9f77b",
        recommendation: "33 种语言 · 较大的翻译专用模型，需要更多内存。"), DownloadableRuntimeModel(
        filename: "translategemma-4b-it-Q4_K_M.gguf", displayName: "TranslateGemma 4B · 多语言翻译",
        downloadURL: URL(string: "https://huggingface.co/bullerwins/translategemma-4b-it-GGUF/resolve/7c938465a870d8624bcfa98a8e4a3510053c19a8/translategemma-4b-it-Q4_K_M.gguf?download=true")!,
        approximateSizeInGigabytes: 2.49, expectedSizeBytes: 2_489_909_312,
        sha256: "7f7357c14abd9da4eb200b38b05da502cd6e10d7e1d403fbc9f78c19f3209b72",
        recommendation: "55 种语言 · Google 翻译模型，bullerwins 提供纯文本 GGUF 量化。")]
    /// The pinned text-model layer from Ollama's official registry is a standalone GGUF, not
    /// an Ollama service dependency. Candidate status makes no promise about teaching accuracy.
    static let analysisModels = [DownloadableRuntimeModel(
        filename: "Gemma-4-E4B-Q4_K_M.gguf", displayName: "Gemma 4 E4B · 语块对应候选",
        downloadURL: URL(string: "https://registry.ollama.ai/v2/library/gemma4/blobs/sha256:370c2879f17648d337b0ab4e208fdce348e24d1060064e93d7645daafd56d39c")!,
        approximateSizeInGigabytes: 5.49, expectedSizeBytes: 5_493_439_296,
        sha256: "370c2879f17648d337b0ab4e208fdce348e24d1060064e93d7645daafd56d39c"), DownloadableRuntimeModel(
        filename: "Qwen3.5-4B-Q4_K_M.gguf", displayName: "Qwen3.5 4B · 语块对应候选",
        downloadURL: URL(string: "https://registry.ollama.ai/v2/library/qwen3.5/blobs/sha256:a9d0a3e1d8c91732a3812becd31f8d4a8ff57414903f226306069f0437e2ac50")!,
        approximateSizeInGigabytes: 2.65, expectedSizeBytes: 2_648_593_216,
        sha256: "a9d0a3e1d8c91732a3812becd31f8d4a8ff57414903f226306069f0437e2ac50")]
}
