import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

@testable import Rules

struct NoMagicNumberRuleTests {
    @Test func frameの数値リテラルは違反() {
        let diagnostics = noMagicNumberRule.lint(
            source: "let v = Image(systemName: \"x\").frame(width: 38, height: 38)",
        )
        #expect(diagnostics.count == 2)
    }

    @Test func paddingの数値リテラルは違反() {
        let diagnostics = noMagicNumberRule.lint(
            source: "let v = Text(\"x\").padding(.top, 8)",
        )
        #expect(diagnostics.count == 1)
    }

    @Test func stackのspacingリテラルは違反() {
        let diagnostics = noMagicNumberRule.lint(
            source: "let v = VStack(spacing: 20) { Text(\"x\") }",
        )
        #expect(diagnostics.count == 1)
    }

    @Test func cornerRadiusラベルのリテラルは違反() {
        let diagnostics = noMagicNumberRule.lint(
            source: "let v = RoundedRectangle(cornerRadius: 2)",
        )
        #expect(diagnostics.count == 1)
    }

    @Test func fontSystemSizeのリテラルは違反() {
        let diagnostics = noMagicNumberRule.lint(
            source: "let v = Text(\"x\").font(.system(size: 13))",
        )
        #expect(diagnostics.count == 1)
    }

    @Test func infinityは違反なし() {
        let diagnostics = noMagicNumberRule.lint(
            source: "let v = Text(\"x\").frame(maxWidth: .infinity, alignment: .center)",
        )
        #expect(diagnostics.isEmpty)
    }

    @Test func 定数参照は違反なし() {
        let diagnostics = noMagicNumberRule.lint(
            source: "let v = Text(\"x\").padding(Layout.Spacing.small)",
        )
        #expect(diagnostics.isEmpty)
    }

    @Test func 自明な値0と1は違反なし() {
        let diagnostics = noMagicNumberRule.lint(
            source: "let v = Text(\"x\").padding(.top, 0).padding(.leading, 1)",
        )
        #expect(diagnostics.isEmpty)
    }

    @Test func 引数なしのデフォルトは違反なし() {
        let diagnostics = noMagicNumberRule.lint(
            source: "let v = Text(\"x\").padding()",
        )
        #expect(diagnostics.isEmpty)
    }

    @Test func 対象外ラベルのリテラルは違反なし() {
        let diagnostics = noMagicNumberRule.lint(
            source: "let v = Spacer(minLength: 8)",
        )
        #expect(diagnostics.isEmpty)
    }

    @Test func allowed_valuesをYAMLで拡張できる() {
        let diagnostics = noMagicNumberRule.lint(
            source: "let v = Text(\"x\").frame(width: 44)",
            argsYAML: "allowed_values: [\"0\", \"1\", \"44\"]",
        )
        #expect(diagnostics.isEmpty)
    }

    @Test func numeric_labelsをYAMLで拡張できる() {
        let diagnostics = noMagicNumberRule.lint(
            source: "let v = Spacer(minLength: 8)",
            argsYAML: "numeric_labels: [\"spacing\", \"cornerRadius\", \"minLength\"]",
        )
        #expect(diagnostics.count == 1)
    }
}
