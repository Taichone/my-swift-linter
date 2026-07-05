import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@testable import Rules

struct NoHardcodedColorRuleTests {
    @Test func barewordの固定色は違反() {
        let diagnostics = noHardcodedColorRule.lint(
            source: "let v = Text(\"x\").foregroundStyle(.white)",
        )
        #expect(diagnostics.count == 1)
    }

    @Test func 数値初期化の色は違反() {
        let diagnostics = noHardcodedColorRule.lint(
            source: "let c = Color(red: 1, green: 0, blue: 0)",
        )
        #expect(diagnostics.count == 1)
    }

    @Test func システムカラーは違反なし() {
        let diagnostics = noHardcodedColorRule.lint(
            source: "let c = Color(.label)",
        )
        #expect(diagnostics.isEmpty)
    }

    @Test func banned_barewordsをYAMLで拡張できる() {
        let diagnostics = noHardcodedColorRule.lint(
            source: "let v = Text(\"x\").foregroundStyle(.red)",
            argsYAML: "banned_barewords: [\"white\", \"black\", \"red\"]",
        )
        #expect(diagnostics.count == 1)
    }
}
