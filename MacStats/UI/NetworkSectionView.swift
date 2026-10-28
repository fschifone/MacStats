import Charts
import SwiftUI

struct NetworkSectionView: View {
    @ObservedObject var store: StatsStore

    private var network: NetworkSnapshot? { store.latestNetwork }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Network")
                Spacer()
                Text(network.map { "↓ \(ByteFormat.rate($0.downBytesPerSec))  ↑ \(ByteFormat.rate($0.upBytesPerSec))" } ?? "--")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
            }

            DualHistoryChart(primary: store.networkDownHistory,
                             secondary: store.networkUpHistory,
                             primaryColor: .blue,
                             secondaryColor: .green)
                .frame(height: 48)

            HStack(spacing: 14) {
                LegendDot(color: .blue, label: "Down")
                LegendDot(color: .green, label: "Up")
                Spacer()
                if let interface = network?.primaryInterface, !interface.isEmpty {
                    Text(interface)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Two line series sharing one auto-scaling Y axis.
struct DualHistoryChart: View {
    let primary: [HistoryPoint]
    let secondary: [HistoryPoint]
    let primaryColor: Color
    let secondaryColor: Color

    var body: some View {
        Chart {
            ForEach(primary) { point in
                LineMark(x: .value("Time", point.date),
                         y: .value("Primary", point.value),
                         series: .value("Series", "primary"))
                    .foregroundStyle(primaryColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(secondary) { point in
                LineMark(x: .value("Time", point.date),
                         y: .value("Secondary", point.value),
                         series: .value("Series", "secondary"))
                    .foregroundStyle(secondaryColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}
