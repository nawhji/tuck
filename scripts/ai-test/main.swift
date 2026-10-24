import Foundation

// 앱과 동일한 ClaudeClient / ProductCatalog 로 가구 추천 AI를 터미널에서 테스트한다.
// 실행: scripts/test-ai.sh ["질문"]
let csv = URL(fileURLWithPath: CommandLine.arguments[1])
let question = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "작은 원룸에 놓을 갈색 1인 소파 2개 추천해줘"

let catalog = try ProductCatalog(url: csv)
var client = ClaudeClient()
client.systemPrompt = ClaudeClient.makeSystemPrompt(catalog: catalog)

print("카탈로그 \(catalog.rows.count)개 로드 / 프롬프트 \(client.systemPrompt.count)자")
print("Q: \(question)\n\nA:")
var answer = ""
do {
    for try await chunk in client.stream([.init(role: "user", text: question)]) {
        answer += chunk
        print(chunk, terminator: "")
    }
} catch {
    print("\n❌ \(error.localizedDescription)")
    exit(1)
}

let segments = ReplyParser.parse(answer)
let picks = segments.flatMap { segment -> [ProductPick] in
    if case .products(let picks) = segment { return picks } else { return [] }
}
let unknown = Set(picks.map(\.id)).subtracting(catalog.ids)
let layout = segments.map { segment -> String in
    if case .products(let picks) = segment { return "카드\(picks.count)" } else { return "글" }
}.joined(separator: " → ")
print("\n\n[검증] 구성: \(layout) / pick \(picks.count)개(최대 \(ReplyParser.maxProducts)) / 카탈로그 밖 id: \(unknown.isEmpty ? "없음" : unknown.sorted().joined(separator: ", "))")
for pick in picks { print("  - \(pick.id) \(pick.keywords)") }
// pick이 없는 응답(카탈로그에 없는 요청)도 정상이다. 카탈로그 밖 id만 실패로 본다.
exit(unknown.isEmpty ? 0 : 1)
