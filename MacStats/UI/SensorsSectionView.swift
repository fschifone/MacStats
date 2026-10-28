import SwiftUI

struct SensorsSectionView: View {
    @ObservedObject var store: StatsStore

    private var sensors: SensorsSnapshot? { store.latestSensors }

    var body: some View {
        if store.sensorsSampler.hasTemperatures || store.sensorsSampler.fanCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle(store.sensorsSampler.fanCount > 0 ? "Fans & Temperatures" : "Temperatures")
                    Spacer()
                    Text(sensors?.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "--")
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                }

                if !store.cpuTempHistory.isEmpty {
                    HistoryChart(history: store.cpuTempHistory, color: .orange, maxValue: nil)
                        .frame(height: 48)
                        .help("CPU temperature over the last 10 minutes")
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    if let sensors, !sensors.fanRPM.isEmpty {
                        GridRow {
                            ForEach(Array(sensors.fanRPM.enumerated()), id: \.offset) { index, rpm in
                                sensorValue(sensors.fanRPM.count > 1 ? "Fan \(index + 1)" : "Fan",
                                            String(format: "%.0f rpm", rpm))
                            }
                        }
                    }
                    GridRow {
                        if let cpu = sensors?.cpuTemperature {
                            sensorValue("CPU die", String(format: "%.0f°C", cpu))
                        }
                        if let gpu = sensors?.gpuTemperature {
                            sensorValue("GPU die", String(format: "%.0f°C", gpu))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func sensorValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
    }
}
