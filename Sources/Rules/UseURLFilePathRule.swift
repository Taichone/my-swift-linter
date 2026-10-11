import SwiftASTLint
import SwiftDiagnostics
import SwiftSyntax

/// Detects deprecated URL initializers that use `fileURLWithPath` labels
/// and suggests migrating to `URL(filePath:)` / `URL(filePath:directoryHint:)`.
struct UseURLFilePathArgs: Codable {
    var severity: Severity = .error
}

let useURLFilePathRule = ParameterizedRule(
    id: "use-url-file-path",
    defaultArguments: UseURLFilePathArgs(),
) { file, context, args in
    let visitor = UseURLFilePathVisitor(context: context, severity: args.severity)
    visitor.walk(file)
}

// MARK: - Visitor

private final class UseURLFilePathVisitor: SyntaxVisitor {
    let context: LintContext
    let severity: Severity

    init(context: LintContext, severity: Severity) {
        self.context = context
        self.severity = severity
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard isURLInit(node), let deprecatedLabel = deprecatedFirstLabel(node) else {
            return .visitChildren
        }

        let hint = deprecatedLabel == "fileURLWithPath:isDirectory:"
            ? " Use `URL(filePath:directoryHint:)` instead."
            : " Use `URL(filePath:)` instead."

        context.reportWithFix(
            on: node,
            message: "Deprecated `URL(\(deprecatedLabel):)` initializer.\(hint)",
            severity: severity,
            fixIts: [
                FixIt.replace(
                    message: SimpleFixItMessage("Replace with `URL(filePath:)`"),
                    oldNode: node,
                    newNode: buildFixed(node: node),
                ),
            ],
        )

        return .visitChildren
    }

    // MARK: - Detection helpers

    private func isURLInit(_ node: FunctionCallExprSyntax) -> Bool {
        if let ref = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text == "URL"
        }
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "init"
        {
            if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
                return base.baseName.text == "URL"
            }
            // `.init(fileURLWithPath:)` with implicit base — no type info available,
            // but this label is unique to URL's deprecated initializer so flag it.
            if memberAccess.base == nil {
                return true
            }
        }
        return false
    }

    /// Returns the deprecated label name if this call uses `fileURLWithPath` as first argument label.
    private func deprecatedFirstLabel(_ node: FunctionCallExprSyntax) -> String? {
        var arguments = node.arguments.makeIterator()
        guard let first = arguments.next(),
              let label = first.label?.text,
              label == "fileURLWithPath"
        else { return nil }

        let hasIsDirectory = arguments.next()?.label?.text == "isDirectory"
        return hasIsDirectory ? "fileURLWithPath:isDirectory:" : "fileURLWithPath"
    }

    // MARK: - Fix-it construction

    private func buildFixed(node: FunctionCallExprSyntax) -> FunctionCallExprSyntax {
        let arguments = node.arguments.enumerated().map { index, argument in
            guard let label = argument.label else { return argument }
            if index == 0 {
                return argument.with(\.label, label.with(\.tokenKind, .identifier("filePath")))
            }
            if index == 1, label.text == "isDirectory" {
                return argument
                    .with(\.label, label.with(\.tokenKind, .identifier("directoryHint")))
                    .with(\.expression, directoryHint(for: argument.expression))
            }
            return argument
        }
        return node.with(\.arguments, LabeledExprListSyntax(arguments))
    }

    private func directoryHint(for expression: ExprSyntax) -> ExprSyntax {
        func hint(_ name: String) -> ExprSyntax {
            ExprSyntax(MemberAccessExprSyntax(declName: DeclReferenceExprSyntax(baseName: .identifier(name))))
        }
        let replacement: ExprSyntax
        if let boolean = expression.as(BooleanLiteralExprSyntax.self) {
            replacement = hint(boolean.literal.tokenKind == .keyword(.true) ? "isDirectory" : "notDirectory")
        } else {
            // Parenthesize the original expression to preserve precedence and evaluate it once.
            replacement = ExprSyntax(TernaryExprSyntax(
                condition: TupleExprSyntax(elements: LabeledExprListSyntax([
                    LabeledExprSyntax(expression: expression.trimmed),
                ])),
                questionMark: .infixQuestionMarkToken(leadingTrivia: .space, trailingTrivia: .space),
                thenExpression: hint("isDirectory"),
                colon: .colonToken(leadingTrivia: .space, trailingTrivia: .space),
                elseExpression: hint("notDirectory"),
            ))
        }
        return replacement
            .with(\.leadingTrivia, expression.leadingTrivia)
            .with(\.trailingTrivia, expression.trailingTrivia)
    }
}
