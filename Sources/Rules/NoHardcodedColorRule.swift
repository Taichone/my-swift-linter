import SwiftASTLint
import SwiftSyntax

// MARK: - Args

/// Configuration for `no-hardcoded-color`.
///
/// Example override in YAML:
/// ```yaml
/// rules:
///   no-hardcoded-color:
///     args:
///       severity: warning
///       banned_barewords: ["white", "black"]
///       color_types: ["Color", "UIColor", "NSColor"]
///       hardcoded_arg_labels: ["red", "hex", "white"]
/// ```
struct NoHardcodedColorArgs: Codable, Sendable {
    /// The severity of a violation.
    var severity: Severity = .warning
    /// Member names treated as hardcoded colors when used as barewords (e.g. `.white`).
    var bannedBarewords: [String] = ["white", "black"]
    /// Color types for which numeric/hex initialization is banned.
    var colorTypes: [String] = ["Color", "UIColor", "NSColor"]
    /// Leading initializer argument labels indicating a hardcoded color (e.g. `Color(red:...)`).
    var hardcodedArgLabels: [String] = ["red", "hex", "white"]

    enum CodingKeys: String, CodingKey {
        case severity
        case bannedBarewords = "banned_barewords"
        case colorTypes = "color_types"
        case hardcodedArgLabels = "hardcoded_arg_labels"
    }

    init(
        severity: Severity = .warning,
        bannedBarewords: [String] = ["white", "black"],
        colorTypes: [String] = ["Color", "UIColor", "NSColor"],
        hardcodedArgLabels: [String] = ["red", "hex", "white"],
    ) {
        self.severity = severity
        self.bannedBarewords = bannedBarewords
        self.colorTypes = colorTypes
        self.hardcodedArgLabels = hardcodedArgLabels
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decodeIfPresent(Severity.self, forKey: .severity) ?? .warning
        bannedBarewords = try container.decodeIfPresent([String].self, forKey: .bannedBarewords) ?? ["white", "black"]
        colorTypes = try container.decodeIfPresent([String].self, forKey: .colorTypes) ?? ["Color", "UIColor", "NSColor"]
        hardcodedArgLabels = try container.decodeIfPresent([String].self, forKey: .hardcodedArgLabels) ?? ["red", "hex", "white"]
    }
}

// MARK: - Rule

/// Bans hardcoded colors.
///
/// Detection targets:
/// - Bareword `.white` / `.black` (hardcoded color literals other than system colors)
/// - Numeric/hex initialization such as `Color(red:green:blue:)` / `Color(hex:)` / `UIColor(red:...)`
///
/// Use dark-mode-aware system colors or asset catalog colors for colors.
let noHardcodedColorRule = ParameterizedRule(
    id: "no-hardcoded-color",
    defaultArguments: NoHardcodedColorArgs(),
) { file, context, args in
    let visitor = HardcodedColorVisitor(context: context, args: args)
    visitor.walk(file)
}

// MARK: - Visitor

private final class HardcodedColorVisitor: SyntaxVisitor {
    private let context: LintContext
    private let bannedBarewords: Set<String>
    private let colorTypes: Set<String>
    private let hardcodedArgLabels: Set<String>
    private let severity: Severity

    init(context: LintContext, args: NoHardcodedColorArgs) {
        self.context = context
        bannedBarewords = Set(args.bannedBarewords)
        colorTypes = Set(args.colorTypes)
        hardcodedArgLabels = Set(args.hardcodedArgLabels)
        severity = args.severity
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if node.base == nil, bannedBarewords.contains(node.declName.baseName.text) {
            context.report(
                on: node,
                message: "ハードコードした固定色 '.\(node.declName.baseName.text)' は使用しないでください。ダークモード対応のシステムカラーを使用してください。",
                severity: severity,
            )
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let calleeName: String? = if let ident = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            ident.baseName.text
        } else if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            member.declName.baseName.text
        } else {
            nil
        }

        if let calleeName, colorTypes.contains(calleeName),
           let firstLabel = node.arguments.first?.label?.text,
           hardcodedArgLabels.contains(firstLabel) {
            context.report(
                on: node,
                message: "ハードコードした固定色 '\(calleeName)(\(firstLabel):...)' は使用しないでください。システムカラーまたはアセットカタログのカラーを使用してください。",
                severity: severity,
            )
        }
        return .visitChildren
    }
}
