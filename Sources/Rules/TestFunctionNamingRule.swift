import SwiftASTLint
import SwiftSyntax

/// Enforces Swift Testing names without spaces, underscores or a redundant `test` prefix.
/// Each naming check can be enabled independently. Functions without `@Test` and escaped
/// Swift keywords without spaces are not checked.
struct TestFunctionNamingArgs: Codable {
    var severity: Severity = .error
    var checkSpaces: Bool = true
    var checkUnderscores: Bool = true
    var checkTestPrefix: Bool = true

    enum CodingKeys: String, CodingKey {
        case severity
        case checkSpaces = "check_spaces"
        case checkUnderscores = "check_underscores"
        case checkTestPrefix = "check_test_prefix"
    }

    init(
        severity: Severity = .error,
        checkSpaces: Bool = true,
        checkUnderscores: Bool = true,
        checkTestPrefix: Bool = true
    ) {
        self.severity = severity
        self.checkSpaces = checkSpaces
        self.checkUnderscores = checkUnderscores
        self.checkTestPrefix = checkTestPrefix
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decodeIfPresent(Severity.self, forKey: .severity) ?? .error
        checkSpaces = try container.decodeIfPresent(Bool.self, forKey: .checkSpaces) ?? true
        checkUnderscores = try container.decodeIfPresent(
            Bool.self, forKey: .checkUnderscores
        ) ?? true
        checkTestPrefix = try container.decodeIfPresent(Bool.self, forKey: .checkTestPrefix) ?? true
    }
}

let testFunctionNamingRule = ParameterizedRule(
    id: "test-function-naming",
    defaultArguments: TestFunctionNamingArgs(),
) { file, context, args in
    let visitor = TestFunctionNamingVisitor(context: context, args: args)
    visitor.walk(file)
}

// MARK: - Visitor

private final class TestFunctionNamingVisitor: SyntaxVisitor {
    let context: LintContext
    let args: TestFunctionNamingArgs

    init(context: LintContext, args: TestFunctionNamingArgs) {
        self.context = context
        self.args = args
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasTestAttribute(node.attributes) else { return .visitChildren }
        let rawName = node.name.text
        let message: String
        if args.checkSpaces, rawName.contains(" ") {
            message = "@Test function name \"\(rawName)\" uses a backtick-quoted phrase. "
                + "Use lowerCamelCase and move the description into @Test(\"…\") instead."
        } else if args.checkUnderscores, rawName.contains("_") {
            message = "@Test function name \"\(rawName)\" is underscore-separated. "
                + "Use lowerCamelCase instead."
        } else if args.checkTestPrefix, rawName.lowercased().hasPrefix("test") {
            message = "@Test function name \"\(rawName)\" starts with \"test\", "
                + "which is redundant. Drop the prefix and use lowerCamelCase."
        } else {
            return .visitChildren
        }
        context.report(on: node, message: message, severity: args.severity)
        return .visitChildren
    }

    // MARK: - Helpers

    private func hasTestAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard case let .attribute(attr) = element else { return false }
            guard let name = attr.attributeName.as(IdentifierTypeSyntax.self) else { return false }
            return name.name.text == "Test"
        }
    }
}
