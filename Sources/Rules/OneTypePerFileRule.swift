import SwiftASTLint
import SwiftSyntax

// MARK: - Args

/// Configuration for `one-type-per-file`.
///
/// Example override in YAML:
/// ```yaml
/// rules:
///   one-type-per-file:
///     args:
///       severity: warning
///       check_file_name_match: true
/// ```
struct OneTypePerFileArgs: Codable, Sendable {
    /// The severity of a violation.
    var severity: Severity = .warning
    /// Whether to also check that the type name matches the file name.
    var checkFileNameMatch: Bool = true

    enum CodingKeys: String, CodingKey {
        case severity
        case checkFileNameMatch = "check_file_name_match"
    }

    init(severity: Severity = .warning, checkFileNameMatch: Bool = true) {
        self.severity = severity
        self.checkFileNameMatch = checkFileNameMatch
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decodeIfPresent(Severity.self, forKey: .severity) ?? .warning
        checkFileNameMatch = try container.decodeIfPresent(Bool.self, forKey: .checkFileNameMatch) ?? true
    }
}

// MARK: - Rule

/// One type per file + file name match.
///
/// - Only one `struct`/`class`/`enum`/`actor` may be defined at the top level.
/// - That type name must match the file name (excluding the extension).
///
/// Exceptions:
/// - Types with the "same name" appearing in each branch of `#if`/`#else` (`IfConfigDecl`) are treated as one.
/// - Types nested inside an extension / protocol body are out of scope (only the top level is checked).
/// - Extension files in the `Foo+Bar.swift` form are excluded from the file name match check.
let oneTypePerFileRule = ParameterizedRule(
    id: "one-type-per-file",
    defaultArguments: OneTypePerFileArgs(),
) { file, context, args in
    let types = TopLevelTypeDeclaration.collect(in: file.statements)
    guard !types.isEmpty else { return }

    let distinctNames = Set(types.map(\.name))

    // One type per file: two or more distinct type names -> report each declaration
    if distinctNames.count > 1 {
        let names = distinctNames.sorted().joined(separator: ", ")
        for type in types {
            context.report(
                on: type.nameToken,
                message: "1ファイルにつきトップレベル型は1つにしてください（検出: \(names)）。",
                severity: args.severity,
            )
        }
        return
    }

    // File name match: only checked when there is a single type
    guard args.checkFileNameMatch else { return }
    let baseName = fileBaseName(from: context.filePath)
    // Extension file naming such as `Foo+Bar.swift` is out of scope
    guard !baseName.contains("+") else { return }

    if let typeName = distinctNames.first, typeName != baseName {
        for type in types where type.name == typeName {
            context.report(
                on: type.nameToken,
                message: "型名 '\(typeName)' とファイル名 '\(baseName)' を一致させてください。",
                severity: args.severity,
            )
        }
    }
}

/// Extracts the file name (excluding the `.swift` extension) from an absolute path.
private func fileBaseName(from filePath: String) -> String {
    let lastComponent = filePath.split(separator: "/").last.map(String.init) ?? filePath
    if lastComponent.hasSuffix(".swift") {
        return String(lastComponent.dropLast(".swift".count))
    }
    return lastComponent
}
