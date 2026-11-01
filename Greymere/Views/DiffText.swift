import SwiftUI

/// A marked-up reading of one changed paragraph: words that go are struck through in red, words that arrive are
/// green, and a long stretch nothing touches is folded to "…" so the change itself is what you read.
enum DiffText {
    private enum Op { case same(String), removed(String), added(String) }

    static func marked(before: String, after: String, theme: ThemeStore) -> AttributedString {
        let a = before.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = after.split(whereSeparator: \.isWhitespace).map(String.init)
        // Beyond this the table is too big to be worth it; show the change whole.
        guard a.count * b.count <= 4_000_000 else { return wholesale(before, after) }
        return render(ops(a, b), theme: theme)
    }

    private static func wholesale(_ before: String, _ after: String) -> AttributedString {
        var removed = AttributedString(before + "\n\n")
        removed.strikethroughStyle = .single
        removed.foregroundColor = .red
        var added = AttributedString(after)
        added.foregroundColor = .green
        return removed + added
    }

    /// Words in common by longest-common-subsequence, then the gaps between them are removals and additions.
    private static func ops(_ a: [String], _ b: [String]) -> [Op] {
        let n = a.count, m = b.count
        var table = [[UInt16]](repeating: [UInt16](repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var out: [Op] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] { out.append(.same(a[i])); i += 1; j += 1 }
            else if j < m, i == n || table[i][j + 1] >= table[i + 1][j] { out.append(.added(b[j])); j += 1 }
            else { out.append(.removed(a[i])); i += 1 }
        }
        return out
    }

    private static func render(_ ops: [Op], theme: ThemeStore) -> AttributedString {
        let keep = 10          // words of unchanged context kept either side of a change
        var result = AttributedString()
        var run: [String] = []

        func word(_ s: String, _ op: Op?) -> AttributedString {
            var t = AttributedString(s + " ")
            switch op {
            case .removed?: t.strikethroughStyle = .single; t.foregroundColor = .red
            case .added?: t.foregroundColor = Color(red: 0.12, green: 0.55, blue: 0.25); t.backgroundColor = Color.green.opacity(0.14)
            default: break
            }
            return t
        }
        func flush(first: Bool, last: Bool) {
            guard !run.isEmpty else { return }
            if run.count <= keep * 2 + 6 || (first && last) {
                for w in run { result += word(w, nil) }
            } else {
                if !first { for w in run.prefix(keep) { result += word(w, nil) } }
                result += AttributedString("… ")
                if !last { for w in run.suffix(keep) { result += word(w, nil) } }
            }
            run = []
        }
        var seenChange = false
        for op in ops {
            switch op {
            case .same(let w): run.append(w)
            case .removed(let w): flush(first: !seenChange, last: false); seenChange = true; result += word(w, op)
            case .added(let w): flush(first: !seenChange, last: false); seenChange = true; result += word(w, op)
            }
        }
        flush(first: !seenChange, last: true)
        return result
    }
}
