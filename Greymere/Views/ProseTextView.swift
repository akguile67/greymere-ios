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
    var onFocus: () -> Void = {}
    var onSelectedQuote: (String?) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
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
