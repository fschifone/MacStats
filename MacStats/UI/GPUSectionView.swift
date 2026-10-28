import SwiftUI

struct GPUSectionView: View {
    @ObservedObject var store: StatsStore

    var body: some View {
        if store.latestGPU != nil || !store.gpuHistory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle("GPU")
                    Spacer()
                    Text(store.latestGPU.map { String(format: "%.0f%%", $0.utilization * 100) } ?? "--")
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                }

                HistoryChart(history: store.gpuHistory, color: .pink)
                    .frame(height: 48)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}
