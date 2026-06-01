import SwiftUI

struct NPCInspectorPanel: View {
    let selection: NPCSelection
    let onClose: () -> Void

    private var progress: BondProgress {
        BondProgress.forTokens(selection.totalTokens)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusSection
            statsSection
            progressSection
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 304)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.76))
        .overlay(
            Rectangle()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.name)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Text(selection.trait.rawValue)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.78))
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help("Close inspector")
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Status")
            HStack {
                Circle()
                    .fill(selection.activeSessionCount > 0 ? Color.green : Color.white.opacity(0.35))
                    .frame(width: 8, height: 8)
                Text(selection.activeSessionCount > 0 ? "Working" : "Idle")
                Spacer()
                if selection.activeSessionCount > 0 {
                    Text("\(selection.activeSessionCount) session\(selection.activeSessionCount == 1 ? "" : "s")")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Stats")
            statRow("Bits", formatBits(selection.totalBits))
            statRow("Tokens", formatInt(selection.totalTokens))
            statRow("Bond", "\(selection.bond)")
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Bond Progress")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 1.0, green: 0.82, blue: 0.24))
                        .frame(width: max(0, proxy.size.width * progress.fraction))
                }
            }
            .frame(height: 8)
            Text(progress.label)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.48))
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.68))
            Spacer()
            Text(value)
                .foregroundStyle(.white)
        }
    }

    private func formatInt(_ value: Int) -> String {
        value.formatted(.number)
    }

    private func formatBits(_ bits: Double) -> String {
        if bits >= 1_000_000 { return String(format: "%.1fM", bits / 1_000_000) }
        if bits >= 1_000 { return String(format: "%.1fk", bits / 1_000) }
        if bits >= 10 { return String(format: "%.0f", bits) }
        return String(format: "%.1f", bits)
    }
}
