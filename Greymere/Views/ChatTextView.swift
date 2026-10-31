import SwiftUI
import UIKit

/// The chat input's text view. SwiftUI's own TextField only scrolls to the caret when the author types, so dictated
/// words that arrive from the server ran off the bottom of a small box. This one scrolls to follow the caret
/// whenever the text is changed from outside, grows with its text up to `maxLines`, and sends on a hardware Return.
struct ChatTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: TextSelection?
    var maxLines = 8
    var onReturn: () -> Void

    func makeUIView(context: Context) -> ReturnTextView {
        let view = ReturnTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 6
        view.isScrollEnabled = true
        view.alwaysBounceVertical = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let coordinator = context.coordinator
        view.onReturn = { coordinator.parent.onReturn() }
        return view
    }

    func updateUIView(_ view: ReturnTextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = context.environment.isEnabled
        let coordinator = context.coordinator
        coordinator.updating = true
        defer { coordinator.updating = false }

        var changed = false
        if view.text != text {
            view.text = text
            changed = true
        }
        if let selection, case .selection(let range) = selection.indices, range.upperBound <= text.endIndex {
            let ns = NSRange(range, in: text)
            if view.selectedRange != ns { view.selectedRange = ns; changed = true }
        }
        if changed {
            // Wait for the new layout, then keep the caret in sight, as typing does.
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }
                view.layoutIfNeeded()
                view.scrollRangeToVisible(view.selectedRange)
            }
        }
    }

    /// Grows with the text; beyond `maxLines` it scrolls inside.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReturnTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 280
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let line = uiView.font?.lineHeight ?? 20
        let maxHeight = line * CGFloat(maxLines) + uiView.textContainerInset.top + uiView.textContainerInset.bottom
        return CGSize(width: width, height: min(max(fitting.height, line + 16), maxHeight))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChatTextView
        var updating = false
        init(_ parent: ChatTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            guard !updating else { return }
            parent.text = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updating else { return }
            let text = textView.text ?? ""
            guard let range = Range(textView.selectedRange, in: text) else { return }
            parent.selection = TextSelection(range: range)
        }
    }
}

/// A text view that tells its owner when a hardware Return (without Shift) is pressed instead of adding a line.
final class ReturnTextView: UITextView {
    var onReturn: (() -> Void)?

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let key = presses.first?.key, key.keyCode == .keyboardReturnOrEnter, !key.modifierFlags.contains(.shift) {
            onReturn?()
            return
        }
        super.pressesBegan(presses, with: event)
    }
}
