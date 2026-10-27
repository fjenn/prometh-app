import Foundation

/// Decodes named and numeric HTML entities in search titles and snippets.
enum PromethHTML {
    static func decode(_ text: String) -> String {
        var output = text
        let named: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&#x27;", "'"),
            ("&#x2019;", "\u{2019}"),
            ("&#8217;", "\u{2019}"),
            ("&#x2018;", "\u{2018}"),
            ("&#x201C;", "\u{201C}"),
            ("&#x201D;", "\u{201D}"),
            ("&rsquo;", "\u{2019}"),
            ("&lsquo;", "\u{2018}"),
            ("&rdquo;", "\u{201D}"),
            ("&ldquo;", "\u{201C}"),
            ("&mdash;", "\u{2014}"),
            ("&ndash;", "\u{2013}"),
            ("&hellip;", "\u{2026}"),
        ]
        // Ampersand entities first would turn `&amp;quot;` into `&quot;` then `"`.
        for (entity, value) in named {
            output = output.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        guard let expression = try? NSRegularExpression(
            pattern: #"&#(x?[0-9a-fA-F]+);"#
        ) else { return output }
        let ns = output as NSString
        let matches = expression.matches(in: output, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return output }
        var result = ""
        var cursor = 0
        for match in matches {
            let whole = match.range
            if whole.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: whole.location - cursor))
            }
            let digits = ns.substring(with: match.range(at: 1))
            let radix = digits.lowercased().hasPrefix("x") ? 16 : 10
            let value = radix == 16 ? String(digits.dropFirst()) : digits
            if let scalarValue = UInt32(value, radix: radix),
               let scalar = UnicodeScalar(scalarValue) {
                result.append(Character(scalar))
            } else {
                result += ns.substring(with: whole)
            }
            cursor = whole.location + whole.length
        }
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }
}
