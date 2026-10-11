@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct DeclarationSpacingRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "declaration-spacing"))
    }

    @Test("adds one blank line before every method, including the first member")
    func methods() {
        assertFix(
            """
            struct Example {
                func first() {}
                private func second() {}
            }
            """,
            """
            struct Example {

                func first() {}

                private func second() {}
            }
            """,
            lines: [2, 3]
        )
    }

    @Test("places the blank line above documentation and attributes")
    func documentedMethods() {
        assertFix(
            """
            struct Example {
                /// Performs the first action.
                /// Keeps related documentation together.
                @MainActor
                public func first() {}
                /** Performs the next action.

                    Additional details remain inside the comment.
                 */
                func second() {}
            }
            """,
            """
            struct Example {

                /// Performs the first action.
                /// Keeps related documentation together.
                @MainActor
                public func first() {}

                /** Performs the next action.

                    Additional details remain inside the comment.
                 */
                func second() {}
            }
            """,
            lines: [2, 6]
        )
    }

    @Test("adds spacing only to documented properties")
    func properties() {
        assertFix(
            """
            struct Example {
                let first = 0
                var second = 1
                /// The cached value.
                @State private var cached = 0
                /** The computed value. */
                var result: Int { cached }
                let last = 2
            }
            """,
            """
            struct Example {
                let first = 0
                var second = 1

                /// The cached value.
                @State private var cached = 0

                /** The computed value. */
                var result: Int { cached }
                let last = 2
            }
            """,
            lines: [4, 6]
        )
    }

    @Test("a first documented property also needs a blank line")
    func firstDocumentedProperty() {
        assertFix(
            "struct Example {\n    /// The value.\n    let value = 0\n}",
            "struct Example {\n\n    /// The value.\n    let value = 0\n}",
            lines: [2]
        )
    }

    @Test("removes excess blank lines while preserving declaration indentation")
    func excessBlankLines() {
        assertFix(
            "struct Example {\n\n \t\n\n    func run() {}\n\n\n    /// The value.\n    let value = 0\n}",
            "struct Example {\n\n    func run() {}\n\n    /// The value.\n    let value = 0\n}",
            lines: [5, 8]
        )
    }

    @Test("one blank line containing whitespace is valid")
    func whitespaceOnlyBlankLines() {
        let source = "struct Example {\n \t\n    func run() {}\n\t\n    /// The value.\n    let value = 0\n}"
        #expect(rule.lint(source: source).isEmpty)
    }

    @Test("properties without documentation have no spacing requirement")
    func undocumentedProperties() {
        let source = """
        struct Example {
            let first = 0
            // This is an ordinary comment.
            let second = 1


            var computed: Int {
                get { first }
                set {}
            }
        }
        """
        #expect(rule.lint(source: source).isEmpty)
    }

    @Test("keeps an attached ordinary comment with its method")
    func ordinaryComments() {
        assertFix(
            """
            struct Example {
                // Keep this note with the method.
                /* More details. */
                @MainActor
                func run() {}
            }
            """,
            """
            struct Example {

                // Keep this note with the method.
                /* More details. */
                @MainActor
                func run() {}
            }
            """,
            lines: [2]
        )
    }

    @Test("separates documentation from a preceding section comment")
    func sectionComments() {
        assertFix(
            """
            struct Example {
                // MARK: - Helpers
                /// Runs the helper.
                func run() {}
            }
            """,
            """
            struct Example {
                // MARK: - Helpers

                /// Runs the helper.
                func run() {}
            }
            """,
            lines: [3]
        )
    }

    @Test("does not require spacing before a detached section comment")
    func detachedSectionComments() {
        let source = """
        struct Example {
            // MARK: - Helpers

            func run() {}
        }
        """
        #expect(rule.lint(source: source).isEmpty)
    }

    @Test("preserves previous members' trailing comments and Unicode positions")
    func trailingComments() {
        assertFix(
            """
            struct Example {
                let text = "日本語" // Keep this note here.
                /// Returns the text.
                func run() {}
            }
            """,
            """
            struct Example {
                let text = "日本語" // Keep this note here.

                /// Returns the text.
                func run() {}
            }
            """,
            lines: [3]
        )
    }

    @Test("moves inline methods onto lines with one blank line above them")
    func inlineMethods() {
        assertFix(
            "struct Example { func first() {} func second() {} }",
            "struct Example {\n\n    func first() {}\n\n    func second() {} }",
            lines: [1, 1]
        )
    }

    @Test("keeps inline block documentation above methods and properties", arguments: [
        "var value = 0", "func run() {}",
    ])
    func inlineDocumentation(declaration: String) {
        assertFix(
            "struct Example { /** Documents the member. */ " + declaration + " }",
            "struct Example {\n\n    /** Documents the member. */ " + declaration + " }",
            lines: [1]
        )
    }

    @Test("keeps attributes together when documentation follows an attribute")
    func documentationAfterAttributes() {
        assertFix(
            """
            struct Example {
                @State
                /// The cached value.
                private var value = 0
                @MainActor
                /// Runs the action.
                public func run() {}
            }
            """,
            """
            struct Example {

                @State
                /// The cached value.
                private var value = 0

                @MainActor
                /// Runs the action.
                public func run() {}
            }
            """,
            lines: [2, 5]
        )
    }

    @Test("includes initializers, deinitializers, and subscripts", arguments: [
        "init() {}", "deinit {}", "subscript(index: Int) -> Int { index }",
        "static func run() {}", "class func run() {}",
    ])
    func otherMethods(declaration: String) {
        assertFix(
            "class Example {\n    " + declaration + "\n}",
            "class Example {\n\n    " + declaration + "\n}",
            lines: [2]
        )
    }

    @Test("includes extension and protocol members", arguments: [
        "extension Example", "protocol Example", "actor Example", "enum Example",
    ])
    func memberScopes(container: String) {
        assertFix(
            container + " {\n    func run()\n}",
            container + " {\n\n    func run()\n}",
            lines: [2]
        )
    }

    @Test("includes members in every conditional compilation branch")
    func conditionalCompilation() {
        assertFix(
            """
            struct Example {
                #if DEBUG
                func run() {}
                #else
                /// The stored value.
                let value = 0
                #endif
            }
            """,
            """
            struct Example {
                #if DEBUG

                func run() {}
                #else

                /// The stored value.
                let value = 0
                #endif
            }
            """,
            lines: [3, 5]
        )
    }

    @Test("leaves global and local declarations, closures, and accessors alone")
    func nonMemberDeclarations() {
        let source = """
        /// A global value.
        let value = 0
        func outer() {
            /// A local value.
            let local = 0
            func inner() {}
            let action = { () -> Int in
                let value = 1
                return value
            }
        }
        struct Example {
            var value: Int {
                get { 0 }
                set {}
            }
        }
        """
        #expect(rule.lint(source: source).isEmpty)
    }

    @Test("preserves the local line ending", arguments: ["\n", "\r\n", "\r"])
    func lineEndings(newline: String) {
        let source = "struct Example {" + newline + "    /// The value." + newline
            + "    let value = 0" + newline + newline + newline + "    func run() {}" + newline + "}"
        let expected = "struct Example {" + newline + newline + "    /// The value." + newline
            + "    let value = 0" + newline + newline + "    func run() {}" + newline + "}"
        assertFix(source, expected, lines: [2, 6])
    }

    @Test("accepts the requested documented and undocumented method layout")
    func requestedLayout() {
        let source = """
        struct Example {

            /// Returns whether the session's current prompt is registered as acknowledged.
            public func isIgnored(_ session: AgentSession, ignored: [String: String]) -> Bool {
                ignored[session.id] == session.promptID && session.promptID != nil
            }

            /// Returns unacknowledged sessions requiring attention by state priority and update time.
            public func attention(_ sessions: [AgentSession], ignored: [String: String]) -> [AgentSession] {
                sessions.filter { $0.status.needsAttention && !isIgnored($0, ignored: ignored) }
                    .sorted {
                    if $0.status.priority != $1.status.priority {
                        return $0.status.priority < $1.status.priority
                    }
                    return $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
                }
            }

            private func newestFirst(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
                lhs.updatedAt == rhs.updatedAt ? lhs.id < rhs.id : lhs.updatedAt > rhs.updatedAt
            }
        }
        """
        let result = rule.lintAndFix(source: source)
        #expect(result.diagnostics.isEmpty)
        #expect(result.fixedSource == nil)
    }

    @Test("severity can be configured")
    func severity() {
        let diagnostics = rule.lint(
            source: "struct Example {\n    func run() {}\n}",
            argsYAML: "severity: warning"
        )
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.severity == .warning)
        #expect(diagnostics.first?.column == 5)
    }

    @Test("empty sources and types have no violations", arguments: ["", "struct Example {}"])
    func emptySources(source: String) {
        #expect(rule.lint(source: source).isEmpty)
    }

    private func assertFix(_ source: String, _ expected: String, lines: [Int]) {
        let result = rule.lintAndFix(source: source)
        #expect(result.diagnostics.map(\.line) == lines)
        #expect(result.diagnostics.allSatisfy { $0.severity == .error && $0.isFixable })
        #expect(result.fixedSource == expected)
        if let fixed = result.fixedSource {
            let secondPass = rule.lintAndFix(source: fixed)
            #expect(secondPass.diagnostics.isEmpty)
            #expect(secondPass.fixedSource == nil)
        }
    }
}
