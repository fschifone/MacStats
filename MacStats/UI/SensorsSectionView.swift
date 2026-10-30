import SwiftUI

struct TemperaturesSectionView: View {
    @ObservedObject var store: StatsStore

    private var sensors: SensorsSnapshot? { store.latestSensors }

    var body: some View {
        if store.sensorsSampler.hasTemperatures {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle("Temperatures")
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

                HStack(spacing: 16) {
                    if let cpu = sensors?.cpuTemperature {
                        SensorValue("CPU die", String(format: "%.0f°C", cpu))
                    }
                    if let gpu = sensors?.gpuTemperature {
                        SensorValue("GPU die", String(format: "%.0f°C", gpu))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

struct FansSectionView: View {
    @ObservedObject var store: StatsStore

    private var sensors: SensorsSnapshot? { store.latestSensors }

    var body: some View {
        if store.sensorsSampler.fanCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle("Fans")
                    Spacer()
                    Text(sensors?.fanRPM.max().map { String(format: "%.0f rpm", $0) } ?? "--")
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                }

                if let sensors, !sensors.fanRPM.isEmpty {
                    HStack(spacing: 16) {
                        ForEach(Array(sensors.fanRPM.enumerated()), id: \.offset) { index, rpm in
                            SensorValue(sensors.fanRPM.count > 1 ? "Fan \(index + 1)" : "Fan",
                                        String(format: "%.0f rpm", rpm))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

struct SensorValue: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
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
