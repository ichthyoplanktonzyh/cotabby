import Foundation

// The standalone experiment compiles the production parser with its three small value contracts.
// App protocols and published settings are intentionally absent: validation needs no app/runtime.
struct LearningMeaningChunk {
    let id: Int
    let sourceRanges: [NSRange]
    let targetRanges: [NSRange]
}
struct LearningSentenceResult {
    let translation: String
    let chunks: [LearningMeaningChunk]
    var unresolvedChunkCount: Int = 0
}

while let line = readLine() {
    do {
        let input = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: String]
        let result = try LearningAlignmentParser.parse(input["raw"]!, source: input["source"]!, translation: input["translation"]!)
        func ranges(_ values: [NSRange]) -> [[String: Int]] {
            values.map { ["location": $0.location, "length": $0.length] }
        }
        let output: [String: Any] = ["succeeded": true, "unresolved": result.unresolvedChunkCount,
            "chunks": result.chunks.map { ["id": $0.id, "sourceRanges": ranges($0.sourceRanges), "targetRanges": ranges($0.targetRanges)] }]
        let encoded = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: encoded, as: UTF8.self))
    } catch {
        let encoded = try! JSONSerialization.data(withJSONObject: ["succeeded": false, "error": error.localizedDescription])
        print(String(decoding: encoded, as: UTF8.self))
    }
}
