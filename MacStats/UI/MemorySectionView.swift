import SwiftUI

struct MemorySectionView: View {
    @ObservedObject var store: StatsStore

    @State private var hoveredSegment: MemorySegment?
    @State private var isSectionHovered = false

    private var memory: MemorySnapshot? { store.latestMemory }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Memory")
                Spacer()
                Text(memory.map { "\(ByteFormat.gigabytes($0.used)) / \(ByteFormat.gigabytes($0.total))" } ?? "--")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
            }

            HistoryChart(history: store.memoryHistory, color: .green)
                .frame(height: 56)

            if let memory {
                HStack(spacing: 8) {
                    MemoryCompositionBar(memory: memory, hoveredSegment: $hoveredSegment)
                        .frame(height: hoveredSegment == nil ? 6 : 8)
                        .animation(.easeOut(duration: 0.12), value: hoveredSegment)
                    Text("Pressure \(memory.pressureLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(memory.pressureLevel >= 4 ? .red
                                         : memory.pressureLevel >= 2 ? .orange : .secondary)
                        .fixedSize()
                }

                if let segment = hoveredSegment {
                    let bytes = segment.bytes(in: memory)
                    HStack(spacing: 6) {
                        Circle().fill(segment.color).frame(width: 6, height: 6)
                        Text("\(segment.label) \(ByteFormat.gigabytes(bytes)) — \(Int((Double(bytes) / Double(memory.total) * 100).rounded()))% of \(ByteFormat.gigabytes(memory.total))")
                            .font(.system(size: 11, weight: .semibold))
                    }
                } else {
                    HStack {
                        Text("App \(ByteFormat.gigabytes(memory.appMemory)) · Wired \(ByteFormat.gigabytes(memory.wired)) · Compressed \(ByteFormat.gigabytes(memory.compressed))")
                        Spacer()
                        Text("Swap \(ByteFormat.gigabytes(memory.swapUsed))")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                if isSectionHovered {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        GridRow {
                            detail("Available", ByteFormat.gigabytes(memory.available))
                            detail("Free", ByteFormat.gigabytes(memory.free))
                            detail("Cached files", ByteFormat.gigabytes(memory.cachedFiles))
                        }
                        GridRow {
                            detail("Swap used", ByteFormat.gigabytes(memory.swapUsed))
                            detail("Swap total", ByteFormat.gigabytes(memory.swapTotal))
                            detail("Pressure", memory.pressureLabel)
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isSectionHovered = hovering }
            if !hovering { hoveredSegment = nil }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
    }
}

enum MemorySegment: Hashable {
    case app, wired, compressed, available

    var label: String {
        switch self {
        case .app: return "App memory"
        case .wired: return "Wired"
        case .compressed: return "Compressed"
        case .available: return "Available"
        }
    }

    var color: Color {
        switch self {
        case .app: return .green
        case .wired: return .yellow
        case .compressed: return .purple
        case .available: return Color.primary.opacity(0.25)
        }
    }

    func bytes(in memory: MemorySnapshot) -> UInt64 {
        switch self {
        case .app: return memory.appMemory
        case .wired: return memory.wired
        case .compressed: return memory.compressed
        case .available: return memory.available
        }
    }
}

/// Stacked bar showing app / wired / compressed memory as fractions of total.
/// Each segment is hoverable.
struct MemoryCompositionBar: View {
    let memory: MemorySnapshot
    @Binding var hoveredSegment: MemorySegment?

    var body: some View {
        GeometryReader { geo in
            let total = Double(memory.total)
            HStack(spacing: 0) {
                segment(.app, width: geo.size.width * Double(memory.appMemory) / total)
                segment(.wired, width: geo.size.width * Double(memory.wired) / total)
                segment(.compressed, width: geo.size.width * Double(memory.compressed) / total)
                segment(.available, width: nil)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private func segment(_ kind: MemorySegment, width: CGFloat?) -> some View {
        let isDimmed = hoveredSegment != nil && hoveredSegment != kind
        Rectangle()
            .fill(kind == .available ? Color.primary.opacity(0.08) : kind.color)
            .opacity(isDimmed ? 0.35 : 1)
            .frame(width: width)
            .contentShape(Rectangle())
            .help("\(kind.label): \(ByteFormat.gigabytes(kind.bytes(in: memory)))")
            .onHover { hovering in
                if hovering {
                    hoveredSegment = kind
                } else if hoveredSegment == kind {
                    hoveredSegment = nil
                }
            }
    }
}
