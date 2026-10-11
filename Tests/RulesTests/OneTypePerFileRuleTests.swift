import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@testable import Rules

struct OneTypePerFileRuleTests {
    @Test func 単一の型でファイル名一致なら違反なし() {
        let diagnostics = oneTypePerFileRule.lint(
            source: "struct Foo {}",
            fileName: "Foo.swift",
        )
        #expect(diagnostics.isEmpty)
    }

    @Test func 複数のトップレベル型は違反() {
        let diagnostics = oneTypePerFileRule.lint(
            source: """
            struct Foo {}
            enum Bar {}
            """,
            fileName: "Foo.swift",
        )
        #expect(diagnostics.count == 2)
    }

    @Test func ネスト型は違反にならない() {
        let diagnostics = oneTypePerFileRule.lint(
            source: """
            struct Foo {
                enum Inner {}
            }
            """,
            fileName: "Foo.swift",
        )
        #expect(diagnostics.isEmpty)
    }

    @Test func extension内のネスト型もトップレベル扱いしない() {
        let diagnostics = oneTypePerFileRule.lint(
            source: "extension Foo { struct Helper {} }",
            fileName: "Foo+Helper.swift",
        )
        #expect(diagnostics.isEmpty)
    }

    @Test func 型名とファイル名の不一致は違反() {
        let diagnostics = oneTypePerFileRule.lint(
            source: "struct Foo {}",
            fileName: "Bar.swift",
        )
        #expect(diagnostics.count == 1)
    }

    @Test func if構成の同名型は1つとして扱う() {
        let diagnostics = oneTypePerFileRule.lint(
            source: """
            #if canImport(UIKit)
            struct Foo {}
            #else
            struct Foo {}
            #endif
            """,
            fileName: "Foo.swift",
        )
        #expect(diagnostics.isEmpty)
    }

    @Test func check_file_name_matchをfalseにすると名前不一致を無視する() {
        let diagnostics = oneTypePerFileRule.lint(
            source: "struct Foo {}",
            fileName: "Bar.swift",
            argsYAML: "check_file_name_match: false",
        )
        #expect(diagnostics.isEmpty)
    }

    @Test("local types inside functions and closures are not top-level", arguments: [
        "func helper() { struct Local {} }",
        "let helper = { struct Local {} }",
        "protocol Namespace { struct Local {} }",
    ])
    func localTypesAreExcluded(nestedSource: String) {
        let diagnostics = oneTypePerFileRule.lint(
            source: "struct Foo {}\n" + nestedSource,
            fileName: "Foo.swift",
        )
        #expect(diagnostics.isEmpty)
    }

    @Test("nested conditional compilation branches are collected")
    func nestedConditionalCompilation() {
        let source = """
        #if DEBUG
        #if FEATURE
        struct Foo {}
        #else
        enum Bar {}
        #endif
        #else
        actor Baz {}
        #endif
        """
        let diagnostics = oneTypePerFileRule.lint(source: source, fileName: "Foo.swift")
        #expect(diagnostics.count == 3)
        #expect(diagnostics.map(\.line) == [3, 5, 8])
    }

    @Test func severityをYAMLで上書きできる() {
        let diagnostics = oneTypePerFileRule.lint(
            source: """
            struct Foo {}
            enum Bar {}
            """,
            fileName: "Foo.swift",
            argsYAML: "severity: error",
        )
        #expect(!diagnostics.isEmpty)
        #expect(diagnostics.allSatisfy { $0.severity == .error })
    }
}
