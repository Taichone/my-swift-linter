import SwiftASTLint
import SwiftSyntax

// MARK: - Args

/// Configuration for `no-dispatch-queue`.
///
/// Example override in YAML:
/// ```yaml
/// rules:
///   no-dispatch-queue:
///     args:
///       severity: error
/// ```
struct NoDispatchQueueArgs: Codable, Sendable {
    /// The severity of a violation.
    var severity: Severity = .error

    init(severity: Severity = .error) {
        self.severity = severity
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decodeIfPresent(Severity.self, forKey: .severity) ?? .error
    }

    enum CodingKeys: String, CodingKey {
        case severity
    }
}

// MARK: - Rule

/// Bans the use of `DispatchQueue`. Use Swift Concurrency for asynchronous work.
let noDispatchQueueRule = ParameterizedRule(
    id: "no-dispatch-queue",
    defaultArguments: NoDispatchQueueArgs(),
) { file, context, args in
    for token in file.tokens(viewMode: .sourceAccurate) where token.tokenKind == .identifier("DispatchQueue") {
        context.report(
            on: token,
            message: "DispatchQueue は使用しないでください。Swift Concurrency（async/await・Task）を使用してください。",
            severity: args.severity,
        )
    }
}
