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
        filename: "Hy-MT2-1.8B-Q4_K_M.gguf", displayName: "Hy-MT2 1.8B · 翻译候选",
        downloadURL: URL(string: "https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/resolve/a0c709d9fac510f2c807aa3af52872340dc37a4a/Hy-MT2-1.8B-Q4_K_M.gguf?download=true")!,
        approximateSizeInGigabytes: 1.13, expectedSizeBytes: 1_133_080_448,
        sha256: "dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699")]
    /// The pinned text-model layer from Ollama's official registry is a standalone GGUF, not
    /// an Ollama service dependency. Candidate status makes no promise about teaching accuracy.
    static let analysisModels = [DownloadableRuntimeModel(
        filename: "Qwen3.5-4B-Q4_K_M.gguf", displayName: "Qwen3.5 4B · 本地分析候选",
        downloadURL: URL(string: "https://registry.ollama.ai/v2/library/qwen3.5/blobs/sha256:a9d0a3e1d8c91732a3812becd31f8d4a8ff57414903f226306069f0437e2ac50")!,
        approximateSizeInGigabytes: 2.65, expectedSizeBytes: 2_648_593_216,
        sha256: "a9d0a3e1d8c91732a3812becd31f8d4a8ff57414903f226306069f0437e2ac50")]
}
