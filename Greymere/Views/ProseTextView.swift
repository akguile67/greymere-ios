import SwiftUI
import UIKit

/// Lets controls outside the text view (the top action bar) act on the prose field being edited, without taking its focus.
@MainActor final class ProseController {
    var apply: ((ProseFormat.Kind) -> Void)?
    func format(_ kind: ProseFormat.Kind) { apply?(kind) }
}

/// One segment of the chapter's manuscript as an editable text view. It takes the height its text needs (the page
/// scrolls, not the segment), reports the caret and the selected passage, and paints the passages that carry open
/// drafting notes. The text is the manuscript's own bytes: nothing is trimmed or rewritten here.
struct ProseTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: TextSelection?
    var editable = true
    var highlights: [String] = []
    var highlightColor: UIColor = UIColor.systemYellow.withAlphaComponent(0.35)
    var focusOnAppear = false
    /// While dictating the keyboard is put away but the text keeps focus, so the caret stays in sight.
    var hideKeyboard = false
    /// False for the last segment of the chapter: a scene break at the end of any other one has to leave the blank line
    /// that separates it from the next segment's first paragraph.
    var trailingBreak = false
    var controller: ProseController?
    var onFocus: () -> Void = {}
    var onSelectedQuote: (String?) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextView {
        let view = ProseUITextView()
        view.onFormat = { [weak coordinator = context.coordinator] kind, v in coordinator?.format(kind, in: v) }
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.isScrollEnabled = false
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 6
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if focusOnAppear { DispatchQueue.main.async { view.becomeFirstResponder() } }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = editable && context.environment.isEnabled
        let c = context.coordinator
        c.updating = true
        defer { c.updating = false }
        if view.text != text { view.text = text }
        if let selection, case .selection(let range) = selection.indices, range.upperBound <= text.endIndex {
            let ns = NSRange(range, in: text)
            if view.selectedRange != ns, view.isFirstResponder { view.selectedRange = ns }
        }
        let hidden = view.inputView != nil
        if hideKeyboard != hidden {
            view.inputView = hideKeyboard ? UIView(frame: .zero) : nil
            if view.isFirstResponder { view.reloadInputViews() }
        }
        restyle(view)
    }

    /// Draws the manuscript's Markdown: bold and italic between balanced markers (the markers dimmed, not hidden), a
    /// `* * *` paragraph centred and spaced, and the passages that carry open notes. Attributes only: the string, the
    /// caret and undo are not touched.
    func restyle(_ view: UITextView) {
        guard view.markedTextRange == nil else { return }
        let base = UIFont.preferredFont(forTextStyle: .body)
        let storage = view.textStorage
        let ns = storage.string as NSString
        let all = NSRange(location: 0, length: ns.length)
        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: UIColor.label], range: all)
        for run in ProseMarkdown.runs(in: ns) {
            switch run.kind {
            case .marker: storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: run.range)
            case .styled(let bold, let italic):
                var traits: UIFontDescriptor.SymbolicTraits = []
                if bold { traits.insert(.traitBold) }
                if italic { traits.insert(.traitItalic) }
                if let d = base.fontDescriptor.withSymbolicTraits(traits) {
                    storage.addAttribute(.font, value: UIFont(descriptor: d, size: base.pointSize), range: run.range)
                }
            case .sceneBreak:
                let style = NSMutableParagraphStyle(); style.alignment = .center
                storage.addAttributes([.paragraphStyle: style, .kern: 6.0, .foregroundColor: UIColor.secondaryLabel], range: run.range)
            }
        }
        for quote in highlights {
            if let r = NoteAnchor.range(of: quote, in: storage.string) {
                storage.addAttribute(.backgroundColor, value: highlightColor, range: NSRange(r, in: storage.string))
            }
        }
        storage.endEditing()
        // What is typed next is plain, whatever it was typed beside.
        view.typingAttributes = [.font: base, .foregroundColor: UIColor.label]
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitting.height, 44))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ProseTextView
        var updating = false
        init(_ parent: ProseTextView) { self.parent = parent }

        /// Bold, italic and scene break, written as the Markdown the manuscript is stored in. Only the characters that
        /// change are replaced, so untouched text stays byte for byte and the system's undo covers it.
        func format(_ kind: ProseFormat.Kind, in view: UITextView) {
            let ns = (view.text ?? "") as NSString
            let edit = ProseFormat.apply(kind, to: ns, selection: view.selectedRange, trailingBreak: parent.trailingBreak)
            guard let start = view.position(from: view.beginningOfDocument, offset: edit.range.location),
                  let end = view.position(from: view.beginningOfDocument, offset: edit.range.location + edit.range.length),
                  let range = view.textRange(from: start, to: end) else { return }
            view.replace(range, withText: edit.text)
            view.selectedRange = edit.selection
            textViewDidChange(view)
            textViewDidChangeSelection(view)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocus()
            parent.controller?.apply = { [weak self, weak textView] kind in
                guard let self, let textView else { return }
                self.format(kind, in: textView)
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !updating else { return }
            parent.text = textView.text
            parent.restyle(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updating else { return }
            let text = textView.text ?? ""
            guard let range = Range(textView.selectedRange, in: text) else { return }
            parent.selection = TextSelection(range: range)
            let picked = textView.selectedRange.length > 0
                ? String(text[range]).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            parent.onSelectedQuote(picked.flatMap { $0.isEmpty ? nil : String($0.prefix(2000)) })
        }
    }
}

/// A text view with Cmd-B / Cmd-I for a hardware keyboard (the Bold, Italic and Scene break buttons are in the top action bar).
final class ProseUITextView: UITextView {
    var onFormat: (ProseFormat.Kind, UITextView) -> Void = { _, _ in }

    init() { super.init(frame: .zero, textContainer: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override var keyCommands: [UIKeyCommand]? {
        let b = UIKeyCommand(title: "Bold", action: #selector(bold), input: "b", modifierFlags: .command)
        let i = UIKeyCommand(title: "Italic", action: #selector(italic), input: "i", modifierFlags: .command)
        b.wantsPriorityOverSystemBehavior = true; i.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [b, i]
    }
    @objc private func bold() { onFormat(.bold, self) }
    @objc private func italic() { onFormat(.italic, self) }
}

/// The manuscript stores Markdown: `*italic*`, `**bold**`, and a scene break as a paragraph of exactly `* * *`.
/// The editor shows those characters as they are (it is not a rich-text view); these are the edits the controls make.
enum ProseFormat {
    enum Kind { case bold, italic, sceneBreak }
    struct Edit { let range: NSRange; let text: String; let selection: NSRange }

    static func apply(_ kind: Kind, to text: NSString, selection: NSRange, trailingBreak: Bool) -> Edit {
        switch kind {
        case .bold: return toggle("**", in: text, selection: selection)
        case .italic: return toggle("*", in: text, selection: selection)
        case .sceneBreak: return sceneBreak(in: text, selection: selection, trailingBreak: trailingBreak)
        }
    }

    private static func isStar(_ text: NSString, _ i: Int) -> Bool { i >= 0 && i < text.length && text.character(at: i) == 42 }
    private static func isBlank(_ c: unichar) -> Bool { c == 32 || c == 10 || c == 13 || c == 9 || c == 0xA0 }

    private static func run(_ text: NSString, from i: Int, step: Int) -> Int {
        var n = 0, k = i
        while isStar(text, k) { n += 1; k += step }
        return n
    }

    private static func toggle(_ marker: String, in text: NSString, selection: NSRange) -> Edit {
        let m = marker.utf16.count
        var lo = selection.location, hi = selection.location + selection.length
        // Markers go round the words, not the spaces beside them.
        while lo < hi, isBlank(text.character(at: lo)) { lo += 1 }
        while hi > lo, isBlank(text.character(at: hi - 1)) { hi -= 1 }
        if lo == hi { lo = selection.location; hi = lo }
        let inner = text.substring(with: NSRange(location: lo, length: hi - lo))
        // Markers inside the selection: "**word**" selected whole.
        if hi > lo {
            let li = run(text, from: lo, step: 1), ti = run(text, from: hi - 1, step: -1)
            let k = min(li, ti)
            let active = m == 2 ? k >= 2 : k % 2 == 1
            if active, inner.utf16.count > 2 * m {
                let stripped = (inner as NSString).substring(with: NSRange(location: m, length: inner.utf16.count - 2 * m))
                return Edit(range: NSRange(location: lo, length: hi - lo), text: stripped, selection: NSRange(location: lo, length: stripped.utf16.count))
            }
        }
        // Markers just outside it (also an empty pair round the caret).
        let k = min(run(text, from: lo - 1, step: -1), run(text, from: hi, step: 1))
        let active = m == 2 ? k >= 2 : k % 2 == 1
        if active {
            return Edit(range: NSRange(location: lo - m, length: hi - lo + 2 * m), text: inner, selection: NSRange(location: lo - m, length: inner.utf16.count))
        }
        if hi == lo {
            return Edit(range: NSRange(location: lo, length: 0), text: marker + marker, selection: NSRange(location: lo + m, length: 0))
        }
        return Edit(range: NSRange(location: lo, length: hi - lo), text: marker + inner + marker, selection: NSRange(location: lo + m, length: inner.utf16.count))
    }

    private static func sceneBreak(in text: NSString, selection: NSRange, trailingBreak: Bool) -> Edit {
        let lo = selection.location, hi = selection.location + selection.length
        var before = 0, k = lo - 1
        while k >= 0, text.character(at: k) == 10, before < 2 { before += 1; k -= 1 }
        var after = 0; k = hi
        while k < text.length, text.character(at: k) == 10, after < 2 { after += 1; k += 1 }
        let needBefore = lo == 0 ? 0 : 2 - before
        let needAfter = hi >= text.length ? (trailingBreak ? 2 : 0) : 2 - after
        let body = String(repeating: "\n", count: needBefore) + "* * *" + String(repeating: "\n", count: needAfter)
        // The caret goes to the start of the next paragraph.
        let caret = lo + body.utf16.count + (hi >= text.length ? 0 : after)
        return Edit(range: selection, text: body, selection: NSRange(location: caret, length: 0))
    }
}

/// Finds the Markdown the editor draws. A pair of markers counts only when it opens and closes inside one paragraph
/// (paragraphs are separated by a blank line) and its text neither starts nor ends with a space; a paragraph that is
/// exactly `* * *` is the scene break.
enum ProseMarkdown {
    struct Run {
        enum Kind { case marker, styled(bold: Bool, italic: Bool), sceneBreak }
        let kind: Kind
        let range: NSRange
    }

    private static let boldItalic = try! NSRegularExpression(pattern: "\\*\\*\\*(?=\\S)[^\\n]+?(?<=\\S)\\*\\*\\*|\\*\\*\\*(?=\\S)(?:(?!\\n\\n)[\\s\\S])+?(?<=\\S)\\*\\*\\*")
    private static let bold = try! NSRegularExpression(pattern: "\\*\\*(?=[^\\s*])(?:(?!\\n\\n)[\\s\\S])+?(?<=[^\\s*])\\*\\*")
    private static let italic = try! NSRegularExpression(pattern: "\\*(?=[^\\s*])(?:(?!\\n\\n)[^*])+?(?<=[^\\s*])\\*")

    static func runs(in text: NSString) -> [Run] {
        var runs: [Run] = []
        let mask = NSMutableString(string: text)
        func blank(_ r: NSRange) { mask.replaceCharacters(in: r, with: String(repeating: "\u{1}", count: r.length)) }
        func scan(_ re: NSRegularExpression, _ m: Int, bold b: Bool, italic i: Bool, consume: Bool) {
            let found = re.matches(in: mask as String, range: NSRange(location: 0, length: mask.length))
            for f in found {
                let r = f.range
                guard r.length > 2 * m else { continue }
                runs.append(Run(kind: .styled(bold: b, italic: i), range: NSRange(location: r.location + m, length: r.length - 2 * m)))
                runs.append(Run(kind: .marker, range: NSRange(location: r.location, length: m)))
                runs.append(Run(kind: .marker, range: NSRange(location: r.location + r.length - m, length: m)))
                if consume { blank(r) } else {
                    blank(NSRange(location: r.location, length: m)); blank(NSRange(location: r.location + r.length - m, length: m))
                }
            }
        }
        scan(boldItalic, 3, bold: true, italic: true, consume: true)
        scan(bold, 2, bold: true, italic: false, consume: false)
        scan(italic, 1, bold: false, italic: true, consume: false)
        // Styled runs nest (italic inside bold): apply the wider ones first so the later, narrower traits are merged.
        runs = merged(runs)
        // Scene breaks.
        var start = 0
        while start <= text.length {
            let next = text.range(of: "\n\n", range: NSRange(location: start, length: text.length - start))
            let end = next.location == NSNotFound ? text.length : next.location
            if text.substring(with: NSRange(location: start, length: end - start)) == "* * *" {
                runs.append(Run(kind: .sceneBreak, range: NSRange(location: start, length: end - start)))
            }
            if next.location == NSNotFound { break }
            start = end + 2
        }
        return runs
    }

    /// Where a bold run and an italic run overlap, one font with both traits.
    private static func merged(_ runs: [Run]) -> [Run] {
        var bolds: [NSRange] = [], italics: [NSRange] = []
        var out: [Run] = []
        for r in runs {
            if case .styled(let b, let i) = r.kind {
                if b && i { out.append(r) } else if b { bolds.append(r.range) } else if i { italics.append(r.range) }
            } else { out.append(r) }
        }
        var cuts = Set<Int>()
        for r in bolds + italics { cuts.insert(r.location); cuts.insert(r.location + r.length) }
        let points = cuts.sorted()
        for (a, b) in zip(points, points.dropFirst()) {
            let piece = NSRange(location: a, length: b - a)
            let isBold = bolds.contains { NSIntersectionRange($0, piece).length == piece.length }
            let isItalic = italics.contains { NSIntersectionRange($0, piece).length == piece.length }
            if isBold || isItalic { out.append(Run(kind: .styled(bold: isBold, italic: isItalic), range: piece)) }
        }
        return out
    }
}
