import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@testable import Rules

struct NoDispatchQueueRuleTests {
    @Test func DispatchQueueの使用は違反() {
        let diagnostics = noDispatchQueueRule.lint(
            source: """
            func run() {
                DispatchQueue.main.async {}
            }
            """,
        )
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.severity == .error)
    }

    @Test func DispatchQueueを使わなければ違反なし() {
        let diagnostics = noDispatchQueueRule.lint(
            source: """
            func run() async {
                await Task { }.value
            }
            """,
        )
        #expect(diagnostics.isEmpty)
    }

    @Test func severityをYAMLで上書きできる() {
        let diagnostics = noDispatchQueueRule.lint(
            source: "let q = DispatchQueue.main",
            argsYAML: "severity: warning",
        )
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.severity == .warning)
    }
}
