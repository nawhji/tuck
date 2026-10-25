import Foundation

// Tests furniture recommendations from the terminal using the app’s ClaudeClient and ProductCatalog.
// Run: scripts/test-ai.sh ["question"]
let csv = URL(fileURLWithPath: CommandLine.arguments[1])
let question = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Recommend two brown lounge chairs for a small studio apartment."

let catalog = try ProductCatalog(url: csv)
var client = ClaudeClient()
client.systemPrompt = ClaudeClient.makeSystemPrompt(catalog: catalog)

print("Loaded \(catalog.rows.count) catalog items / prompt: \(client.systemPrompt.count) characters")
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
    if case .products(let picks) = segment { return "\(picks.count) cards" } else { return "text" }
}.joined(separator: " → ")
print("\n\n[Validation] Segments: \(layout) / picks: \(picks.count) (max \(ReplyParser.maxProducts)) / unknown catalog IDs: \(unknown.isEmpty ? "none" : unknown.sorted().joined(separator: ", "))")
for pick in picks { print("  - \(pick.id) \(pick.keywords)") }
// A response with no picks (for a request outside the catalog) is valid. Only unknown catalog IDs fail.
exit(unknown.isEmpty ? 0 : 1)
