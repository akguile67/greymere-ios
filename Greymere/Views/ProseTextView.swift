import SwiftUI
import UIKit

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
        paint(view)
    }

    private func paint(_ view: UITextView) {
        let storage = view.textStorage
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: all)
        for quote in highlights {
            if let r = NoteAnchor.range(of: quote, in: text) {
                storage.addAttribute(.backgroundColor, value: highlightColor, range: NSRange(r, in: text))
            }
        }
        storage.endEditing()
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

        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocus() }

        func textViewDidChange(_ textView: UITextView) {
            guard !updating else { return }
            parent.text = textView.text
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

/// A text view with a Bold / Italic / Scene break bar above the keyboard and Cmd-B / Cmd-I for a hardware keyboard.
final class ProseUITextView: UITextView {
    var onFormat: (ProseFormat.Kind, UITextView) -> Void = { _, _ in }

    init() {
        super.init(frame: .zero, textContainer: nil)
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        bar.items = [
            UIBarButtonItem(image: UIImage(systemName: "bold"), primaryAction: UIAction(title: "Bold") { [unowned self] _ in onFormat(.bold, self) }),
            UIBarButtonItem(image: UIImage(systemName: "italic"), primaryAction: UIAction(title: "Italic") { [unowned self] _ in onFormat(.italic, self) }),
            UIBarButtonItem(title: "* * *", primaryAction: UIAction(title: "Scene break") { [unowned self] _ in onFormat(.sceneBreak, self) }),
            UIBarButtonItem.flexibleSpace(),
        ]
        bar.items?[0].accessibilityLabel = "Bold"
        bar.items?[1].accessibilityLabel = "Italic"
        bar.items?[2].accessibilityLabel = "Scene break"
        bar.autoresizingMask = .flexibleWidth
        inputAccessoryView = bar
    }
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
