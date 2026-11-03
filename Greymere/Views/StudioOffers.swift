import SwiftUI

/// "On offer from the studio": one next action per area, each a glass card. Add to today takes it onto the list as a
/// task (the desktop's button, `POST /api/home/studio/promote`); the pin makes it the author's first priority. The
/// offer's hours are its size, the author's or the type's default, and it counts against the day only once added.
struct StudioOffers: View {
    let model: TodayModel
    let client: APIClient
    let studio: Studio
    @Environment(ConnectionModel.self) private var connection

    private var theme: ThemeStore { connection.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let m = studio.message {
                Text(m).font(.subheadline).foregroundStyle(Color.green).fixedSize(horizontal: false, vertical: true)
            }
            if !studio.areas.isEmpty {
                SectionLabel(title: "On offer from the studio", count: nil)
                ForEach(studio.areas) { area in card(area) }
            }
        }
    }

    private func card(_ a: Studio.Area) -> some View {
        let basis = ["set": "your size", "default": "default size for its type", "unsized": "not sized"][a.item.sizeBasis ?? ""] ?? ""
        let hours = a.item.sizeHours.map { "\(Fmt.hours($0))h" } ?? "unsized"
        let pinned = a.item.pinned == true
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(a.label).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 2)
                    .background(theme.accent.opacity(0.15), in: .capsule).foregroundStyle(theme.accent)
                if let more = a.more, more > 0 { Text("\(more) more waiting").font(.caption).foregroundStyle(theme.faint) }
                Spacer(minLength: 0)
                Button { Task { await model.pin(a.item.key, on: !pinned, client: client) } } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin").font(.footnote).foregroundStyle(pinned ? theme.accent : theme.muted)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pinned ? "Unpin" : "Pin first")
            }
            Text(a.item.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("From \(a.item.source ?? a.label) — \(a.item.reason ?? "") · \(hours) (\(basis))")
                .font(.footnote).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
            Button { Task { await model.promote(a.item.key, client: client) } } label: {
                Label("Add to today", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }
}
