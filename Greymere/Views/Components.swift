import SwiftUI

struct EnvironmentBar: View {
    let instance: Instance
    @Environment(ConnectionModel.self) private var connection

    private var tint: Color {
        switch instance.environment {
        case "production": return connection.theme.accent
        case "pre-production": return .orange
        default: return .teal
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(Fmt.environmentName(instance.environment)).font(.caption.weight(.semibold))
            Text("server \(instance.version)").font(.caption).foregroundStyle(connection.theme.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

struct CoverView: View {
    let url: URL?
    let seed: Bool
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default:
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: seed ? "sparkles" : "book.closed").font(.title2).foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }
}

struct SectionLabel: View {
    let title: String
    let count: Int?
    var grip = false
    @Environment(ConnectionModel.self) private var connection
    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.8)
            if let count { Text("\(count)").font(.caption).foregroundStyle(connection.theme.faint) }
            if grip {
                Image(systemName: "line.3.horizontal").font(.caption.weight(.semibold))
                    .foregroundStyle(connection.theme.faint).padding(.leading, 4)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(connection.theme.muted)
    }
}
