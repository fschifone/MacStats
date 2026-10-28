import SwiftUI

struct BatterySectionView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject private var settings = AppSettings.shared

    private var battery: BatterySnapshot? { store.latestBattery }

    var body: some View {
        if let battery {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle("Battery")
                    Spacer()
                    Picker("Graph window", selection: $settings.batteryGraphHours) {
                        Text("1 h").tag(1)
                        Text("12 h").tag(12)
                        Text("24 h").tag(24)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .labelsHidden()
                    .fixedSize()
                    Text(String(format: "%.0f%%", battery.level * 100))
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                }

                let windowStart = Date().addingTimeInterval(-Double(settings.batteryGraphHours) * 3600)
                HistoryChart(history: store.batteryHistory.filter { $0.date >= windowStart },
                             color: battery.level <= 0.2 ? .red : .green,
                             xDomain: windowStart...Date())
                    .frame(height: 48)
                    .help("Battery level over the last \(settings.batteryGraphHours) h (fills while the app runs)")

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(battery.level <= 0.2 ? Color.red : Color.green)
                            .frame(width: geo.size.width * battery.level)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(stateText(battery))
                    Spacer()
                    Text(detailText(battery))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func stateText(_ battery: BatterySnapshot) -> String {
        var text = battery.stateLabel
        if let minutes = battery.minutesRemaining {
            let suffix = battery.isCharging ? "until full" : "remaining"
            text += String(format: " · %d:%02d %@", minutes / 60, minutes % 60, suffix)
        }
        return text
    }

    private func detailText(_ battery: BatterySnapshot) -> String {
        var parts: [String] = []
        if let health = battery.health {
            parts.append(String(format: "Health %.0f%%", health * 100))
        }
        if let cycles = battery.cycleCount {
            parts.append("\(cycles) cycles")
        }
        return parts.joined(separator: " · ")
    }
}
