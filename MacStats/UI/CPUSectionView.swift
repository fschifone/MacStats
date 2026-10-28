import Charts
import SwiftUI

struct CPUSectionView: View {
    @ObservedObject var store: StatsStore

    private var cpu: CPUSnapshot? { store.latestCPU }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("CPU")
                Spacer()
                Text(cpu.map { String(format: "%.0f%%", $0.totalUsage * 100) } ?? "--")
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
            }

            HistoryChart(history: store.cpuHistory, color: .blue)
                .frame(height: 56)

            HStack {
                Text(cpu.map { String(format: "User %.0f%% · System %.0f%%",
                                      $0.userUsage * 100, $0.systemUsage * 100) } ?? "")
                Spacer()
                Text(cpu.map { String(format: "Load %.2f · %dP + %dE",
                                      $0.loadAverage,
                                      store.cpuSampler.performanceCoreCount,
                                      store.cpuSampler.efficiencyCoreCount) } ?? "")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            if let cpu {
                PerCoreBars(usage: cpu.perCoreUsage,
                            efficiencyCoreCount: store.cpuSampler.efficiencyCoreCount)
                HStack(spacing: 14) {
                    LegendDot(color: .blue, label: "Performance cores")
                    LegendDot(color: .yellow, label: "Efficiency cores")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Vertical usage bars, one per core. On Apple Silicon the first cores
/// reported by host_processor_info are the efficiency cluster.
struct PerCoreBars: View {
    let usage: [Double]
    let efficiencyCoreCount: Int

    @State private var hoveredIndex: Int?

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(usage.enumerated()), id: \.offset) { index, value in
                let isEfficiency = index < efficiencyCoreCount
                let name = isEfficiency ? "E\(index + 1)" : "P\(index - efficiencyCoreCount + 1)"
                let isHovered = hoveredIndex == index
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(isHovered ? 0.16 : 0.08))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isEfficiency ? Color.yellow : Color.blue)
                                .opacity(isHovered ? 1.0 : 0.85)
                                .frame(height: max(2, geo.size.height * value))
                        }
                    }
                    .frame(height: 36)
                    Text(isHovered ? "\(Int((value * 100).rounded()))%" : name)
                        .font(.system(size: 9, weight: isHovered ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isHovered ? .primary : .secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
                .contentShape(Rectangle())
                .help("\(name): \(Int((value * 100).rounded()))% used")
                .onHover { hovering in
                    if hovering {
                        hoveredIndex = index
                    } else if hoveredIndex == index {
                        hoveredIndex = nil
                    }
                }
            }
        }
    }
}

struct HistoryChart: View {
    let history: [HistoryPoint]
    let color: Color
    /// Fixed Y-axis top, or nil to auto-scale to the data.
    var maxValue: Double? = 1.0
    /// Fixed time window, or nil to fit the data.
    var xDomain: ClosedRange<Date>?

    var body: some View {
        let base = Chart(history) { point in
            AreaMark(x: .value("Time", point.date),
                     y: .value("Usage", point.value))
                .foregroundStyle(color.opacity(0.22))
            LineMark(x: .value("Time", point.date),
                     y: .value("Usage", point.value))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)

        let chart = Group {
            if let xDomain {
                base.chartXScale(domain: xDomain)
            } else {
                base
            }
        }

        if let maxValue {
            chart.chartYScale(domain: 0...maxValue)
        } else {
            chart
        }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.6)
    }
}

struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
