import SwiftUI

struct RosterPanel: View {
    let catalog: NPCCatalog
    let roster: NPCRoster
    let onSelect: (String) -> Void
    let onClose: () -> Void

    private let columns = [
        GridItem(.fixed(132), spacing: 10),
        GridItem(.fixed(132), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Roster")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.78))
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(catalog.entries) { entry in
                    let rosterEntry = roster.entry(catalogId: entry.catalogId)
                    Button {
                        if rosterEntry?.isUnlocked == true { onSelect(entry.catalogId) }
                    } label: {
                        RosterCard(entry: entry, rosterEntry: rosterEntry)
                    }
                    .buttonStyle(.plain)
                    .disabled(rosterEntry?.isUnlocked != true)
                }
            }
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 310)
        .background(.black.opacity(0.78))
        .overlay(Rectangle().stroke(.white.opacity(0.14), lineWidth: 1))
    }
}

private struct RosterCard: View {
    let entry: NPCCatalogEntry
    let rosterEntry: RosterEntry?

    private var unlocked: Bool { rosterEntry?.isUnlocked == true }
    private var projectCount: Int { rosterEntry?.assignedProjects.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(entry.sprite.replacingOccurrences(of: "char_", with: "C"))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(width: 34, height: 34)
                    .background(unlocked ? Color(red: 0.52, green: 0.92, blue: 0.62).opacity(0.28) : .white.opacity(0.08))
                    .overlay(Rectangle().stroke(.white.opacity(unlocked ? 0.22 : 0.08), lineWidth: 1))
                    .opacity(unlocked ? 1.0 : 0.42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(rosterEntry?.name ?? entry.defaultName ?? entry.catalogId)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                    Text(unlocked ? badgeText : entry.unlockCondition.displayText)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(badgeColor)
                        .lineLimit(2)
                }
            }
            Text(entry.personality)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(unlocked ? 0.48 : 0.28))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(width: 132, height: 118, alignment: .topLeading)
        .background(.white.opacity(unlocked ? 0.07 : 0.035))
        .overlay(Rectangle().stroke(.white.opacity(unlocked ? 0.12 : 0.06), lineWidth: 1))
        .opacity(unlocked ? 1.0 : 0.58)
    }

    private var badgeText: String {
        if projectCount == 0 { return "No project" }
        return "\(projectCount) project\(projectCount == 1 ? "" : "s")"
    }

    private var badgeColor: Color {
        if !unlocked { return .white.opacity(0.42) }
        if projectCount == 0 { return Color(red: 1.0, green: 0.72, blue: 0.25) }
        return Color(red: 0.52, green: 0.92, blue: 0.62)
    }
}
