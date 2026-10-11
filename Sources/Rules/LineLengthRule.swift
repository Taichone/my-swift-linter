import SwiftASTLint
import SwiftSyntax

/// Limits every physical source line to 100 characters, including whitespace and comments.
struct LineLengthArgs: Codable {
    var severity: Severity = .error
}

let lineLengthRule = ParameterizedRule(
    id: "line-length",
    defaultArguments: LineLengthArgs(),
) { file, context, args in
    let maximumLength = 100
    let source = file.description
    var lineStart = source.startIndex
    var byteOffset = 0

    while lineStart < source.endIndex {
        let lineEnd = source[lineStart...].firstIndex { character in
            character == "\n" || character == "\r" || character == "\r\n"
        } ?? source.endIndex
        let line = source[lineStart..<lineEnd]
        let length = line.count
        if length > maximumLength {
            let position = byteOffset + line.prefix(maximumLength).utf8.count
            // LintContext reports node positions. This marker places the diagnostic at the
            // first excess character, including within comments and multiline literal tokens.
            let marker = TokenSyntax(
                .identifier(""), leadingTrivia: .spaces(position), presence: .present
            )
            context.report(
                on: marker,
                message: "Line length is \(length) characters (maximum: \(maximumLength)).",
                severity: args.severity,
            )
        }
        guard lineEnd < source.endIndex else { break }
        byteOffset += line.utf8.count + String(source[lineEnd]).utf8.count
        lineStart = source.index(after: lineEnd)
    }
}
