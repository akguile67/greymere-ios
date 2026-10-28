import SwiftUI

/// The order the author has dragged things into, kept on this device only (the app never writes to the server).
@MainActor @Observable
final class OrderStore {
    private let key: String
    private(set) var order: [String]

    init(key: String) {
        self.key = key
        order = UserDefaults.standard.stringArray(forKey: "greymere.order.\(key)") ?? []
    }

    /// Items in the saved order; anything not seen before keeps its place after the ones that were.
    func sorted<T: Identifiable>(_ items: [T]) -> [T] where T.ID == String {
        items.enumerated().sorted { a, b in
            let ra = order.firstIndex(of: a.element.id) ?? Int.max
            let rb = order.firstIndex(of: b.element.id) ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// Puts `id` where `target` is now.
    func move(_ id: String, onto target: String, among ids: [String]) {
        guard id != target, ids.contains(id), let to = ids.firstIndex(of: target) else { return }
        var list = ids
        let from = list.firstIndex(of: id)!
        list.remove(at: from)
        list.insert(id, at: to)
        order = list
        UserDefaults.standard.set(list, forKey: "greymere.order.\(key)")
    }
}
