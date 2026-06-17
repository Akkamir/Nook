import SwiftUI

struct AssignmentPanel: View {
    let catalogEntry: NPCCatalogEntry
    let rosterEntry: RosterEntry
    let roster: NPCRoster
    let canRename: Bool
    let projects: [DiscoveredProject]
    let onSave: (String, [String]) -> Void
    let onClose: () -> Void

    @State private var name: String
    @State private var selectedPaths: Set<String>

    init(
        catalogEntry: NPCCatalogEntry,
        rosterEntry: RosterEntry,
        roster: NPCRoster,
        canRename: Bool,
        projects: [DiscoveredProject],
        onSave: @escaping (String, [String]) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.catalogEntry = catalogEntry
        self.rosterEntry = rosterEntry
        self.roster = roster
        self.canRename = canRename
        self.projects = projects
        self.onSave = onSave
        self.onClose = onClose
        _name = State(initialValue: rosterEntry.name)
        _selectedPaths = State(initialValue: Set(rosterEntry.assignedProjects))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Projects")
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.46))
                TextField("", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .padding(8)
                    .background(.white.opacity(canRename ? 0.10 : 0.05))
                    .overlay(Rectangle().stroke(.white.opacity(0.10), lineWidth: 1))
                    .disabled(!canRename)
            }

            Text(catalogEntry.personality)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.54))
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(projectRows) { project in
                        Button {
                            toggle(project.path)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: selectedPaths.contains(project.path) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.displayName)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .lineLimit(1)
                                    Text(project.path)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.42))
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(shortRelative(project.lastActivityAt))
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.42))
                            }
                            .padding(8)
                            .background(.white.opacity(selectedPaths.contains(project.path) ? 0.10 : 0.045))
                            .overlay(Rectangle().stroke(.white.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 260)

            Button {
                onSave(name, Array(selectedPaths).sorted())
                onClose()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                    Text("Save")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .foregroundStyle(.black)
            .background(Color(red: 0.52, green: 0.92, blue: 0.62))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 440)
        .background(.black.opacity(0.82))
        .overlay(Rectangle().stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private var projectRows: [DiscoveredProject] {
        let available = roster.availableProjects(from: projects, forCatalogId: rosterEntry.catalogId)
        let discoveredByPath = Dictionary(uniqueKeysWithValues: available.map { ($0.path, $0) })
        let assignedOnly = rosterEntry.assignedProjects
            .filter { discoveredByPath[$0] == nil }
            .map {
                DiscoveredProject(
                    path: $0,
                    displayName: URL(fileURLWithPath: $0).lastPathComponent,
                    lastActivityAt: Date(timeIntervalSince1970: 0)
                )
            }
        return (available + assignedOnly).sorted { lhs, rhs in
            if selectedPaths.contains(lhs.path) != selectedPaths.contains(rhs.path) {
                return selectedPaths.contains(lhs.path)
            }
            if lhs.lastActivityAt == rhs.lastActivityAt { return lhs.path < rhs.path }
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
    }

    private func toggle(_ path: String) {
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    private func shortRelative(_ date: Date) -> String {
        guard date.timeIntervalSince1970 > 0 else { return "-" }
        let days = max(0, Int(Date().timeIntervalSince(date) / 86_400))
        if days == 0 { return "today" }
        return "\(days)d"
    }
}
