import SwiftASTLint
import SwiftSyntax

struct SingleLargeTypeArgs: Codable {
    /// Line count at which a type is considered large enough to warn. Must be less than or equal to `error_lines`.
    var warningLines: Int = 50
    /// Line count at which a type triggers an error when multiple appear in one file.
    var errorLines: Int = 50

    enum CodingKeys: String, CodingKey {
        case warningLines = "warning_lines"
        case errorLines = "error_lines"
    }
}

/// Flags files that contain two or more large `public`/`package` types.
/// Emits an error by default when each type exceeds `error_lines` lines.
/// Nested types are not counted as top-level declarations.
///
/// Configure via YAML:
/// ```yaml
/// rules:
///   single-large-type-per-file:
///     args:
///       warning_lines: 50
///       error_lines: 50
/// ```
let singleLargeTypePerFileRule = ParameterizedRule(
    id: "single-large-type-per-file",
    defaultArguments: SingleLargeTypeArgs()
) { file, context, args in
    let candidates = TopLevelTypeDeclaration.collect(in: file.statements).filter { type in
        type.modifiers.contains {
            $0.name.tokenKind == .keyword(.public) || $0.name.tokenKind == .keyword(.package)
        }
    }
    guard candidates.count >= 2 else { return }

    let converter = context.sourceLocationConverter
    let largeTypes = candidates.compactMap { type -> LargeTypeInfo? in
        let lineCount = converter.location(for: type.node.endPosition).line
            - converter.location(for: type.node.position).line + 1
        guard lineCount >= args.warningLines else { return nil }
        return LargeTypeInfo(name: type.name, lineCount: lineCount, node: type.node)
    }
    guard largeTypes.count >= 2 else { return }
    for info in largeTypes {
        let severity: Severity = info.lineCount >= args.errorLines ? .error : .warning
        let threshold = info.lineCount >= args.errorLines ? args.errorLines : args.warningLines
        context.report(
            on: info.node,
            message: "\(info.name) is \(info.lineCount) lines."
                + " Only one large (>= \(threshold) lines) public/package type per file is allowed."
                + " Split into separate files.",
            severity: severity
        )
    }
}

private struct LargeTypeInfo {
    let name: String
    let lineCount: Int
    let node: Syntax
}
