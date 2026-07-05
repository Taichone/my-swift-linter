import SwiftASTLint
import SwiftSyntax

// MARK: - Args

/// Configuration for `no-magic-number`.
///
/// Example override in YAML:
/// ```yaml
/// rules:
///   no-magic-number:
///     args:
///       severity: warning
///       numeric_arg_calls: ["frame", "padding", "offset", "cornerRadius", "lineSpacing", "system"]
///       numeric_labels: ["spacing", "cornerRadius"]
///       allowed_values: ["0", "1"]
/// ```
struct NoMagicNumberArgs: Codable, Sendable {
    /// The severity of a violation.
    var severity: Severity = .warning
    /// Call names whose numeric-literal arguments are all treated as magic numbers
    /// (e.g. `.frame(width: 38)`, `.padding(.top, 8)`, `.cornerRadius(8)`, `.system(size: 13)`).
    var numericArgCalls: [String] = ["frame", "padding", "offset", "cornerRadius", "lineSpacing", "system"]
    /// Argument labels whose numeric-literal value is treated as a magic number in any call
    /// (e.g. `VStack(spacing: 8)`, `RoundedRectangle(cornerRadius: 2)`).
    var numericLabels: [String] = ["spacing", "cornerRadius"]
    /// Numeric literal texts that are allowed (trivial values such as `0` / `1`).
    var allowedValues: [String] = ["0", "1"]

    enum CodingKeys: String, CodingKey {
        case severity
        case numericArgCalls = "numeric_arg_calls"
        case numericLabels = "numeric_labels"
        case allowedValues = "allowed_values"
    }

    init(
        severity: Severity = .warning,
        numericArgCalls: [String] = ["frame", "padding", "offset", "cornerRadius", "lineSpacing", "system"],
        numericLabels: [String] = ["spacing", "cornerRadius"],
        allowedValues: [String] = ["0", "1"],
    ) {
        self.severity = severity
        self.numericArgCalls = numericArgCalls
        self.numericLabels = numericLabels
        self.allowedValues = allowedValues
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decodeIfPresent(Severity.self, forKey: .severity) ?? .warning
        numericArgCalls = try container.decodeIfPresent([String].self, forKey: .numericArgCalls)
            ?? ["frame", "padding", "offset", "cornerRadius", "lineSpacing", "system"]
        numericLabels = try container.decodeIfPresent([String].self, forKey: .numericLabels)
            ?? ["spacing", "cornerRadius"]
        allowedValues = try container.decodeIfPresent([String].self, forKey: .allowedValues) ?? ["0", "1"]
    }
}

// MARK: - Rule

/// Bans hardcoded magic numbers in UI layout / font code.
///
/// Detection targets:
/// - Numeric literal arguments of layout/font calls (`.frame` / `.padding` / `.offset` /
///   `.cornerRadius` / `.lineSpacing` / `.system(size:)`).
/// - Numeric literal values for layout labels in any call (`spacing:` / `cornerRadius:`).
///
/// Non-numeric values (`.infinity` etc.), constant references (`Metrics.padding`), and trivial
/// values (`0` / `1`) are not reported. Use system defaults (argument-less `.padding()`) or a
/// shared static constant (`Layout.*`) instead of a raw literal.
let noMagicNumberRule = ParameterizedRule(
    id: "no-magic-number",
    defaultArguments: NoMagicNumberArgs(),
) { file, context, args in
    let visitor = MagicNumberVisitor(context: context, args: args)
    visitor.walk(file)
}

// MARK: - Visitor

private final class MagicNumberVisitor: SyntaxVisitor {
    private let context: LintContext
    private let numericArgCalls: Set<String>
    private let numericLabels: Set<String>
    private let allowedValues: Set<String>
    private let severity: Severity

    init(context: LintContext, args: NoMagicNumberArgs) {
        self.context = context
        numericArgCalls = Set(args.numericArgCalls)
        numericLabels = Set(args.numericLabels)
        allowedValues = Set(args.allowedValues)
        severity = args.severity
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = calleeName(of: node)
        let checkAllArguments = callee.map { numericArgCalls.contains($0) } ?? false

        for argument in node.arguments {
            let labelMatches = argument.label.map { numericLabels.contains($0.text) } ?? false
            guard checkAllArguments || labelMatches else { continue }
            guard let value = numericLiteralText(argument.expression), !allowedValues.contains(value) else { continue }

            let location = argument.label.map { "\($0.text): \(value)" } ?? value
            context.report(
                on: argument.expression,
                message: "マジックナンバー '\(location)' を直接指定しないでください。"
                    + "Layout などに集約した静的定数を参照するか、システムデフォルト（引数なしの .padding() 等）を使用してください。",
                severity: severity,
            )
        }
        return .visitChildren
    }

    /// Returns the called function/initializer name (`frame`, `RoundedRectangle`, `system`, ...).
    private func calleeName(of node: FunctionCallExprSyntax) -> String? {
        if let ident = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            return ident.baseName.text
        }
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    /// Returns the literal text when the expression is an integer/float literal (optionally signed), else nil.
    private func numericLiteralText(_ expr: ExprSyntax) -> String? {
        if let intLiteral = expr.as(IntegerLiteralExprSyntax.self) {
            return intLiteral.literal.text
        }
        if let floatLiteral = expr.as(FloatLiteralExprSyntax.self) {
            return floatLiteral.literal.text
        }
        if let prefix = expr.as(PrefixOperatorExprSyntax.self) {
            return numericLiteralText(prefix.expression)
        }
        return nil
    }
}
