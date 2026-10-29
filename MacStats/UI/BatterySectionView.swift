import Charts
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
                BatteryChart(history: store.batteryHistory.filter { $0.date >= windowStart },
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

                if let duration = durationText(battery) {
                    Text(duration)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func stateText(_ battery: BatterySnapshot) -> String {
        var text = battery.stateLabel
        if let minutes = battery.minutesRemaining {
            let suffix = battery.isCharging ? "until full" : "remaining"
            text += " · \(Self.hoursMinutes(minutes)) \(suffix)"
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

    /// Expected runtime, estimated from the discharge rate measured while the
    /// app has been running on battery power.
    private func durationText(_ battery: BatterySnapshot) -> String? {
        guard !battery.onACPower, !battery.isCharging,
              let rate = dischargeRatePerSecond() else { return nil }
        var parts: [String] = []
        if battery.minutesRemaining == nil {
            let remaining = Int(battery.level / rate / 60)
            parts.append("Est. \(Self.hoursMinutes(remaining)) remaining")
        }
        let fullCharge = Int(1.0 / rate / 60)
        parts.append("~\(Self.hoursMinutes(fullCharge)) on a full charge")
        return "Expected duration: " + parts.joined(separator: " · ")
    }

    /// Fraction of battery drained per second over the recent history, or nil
    /// when there isn't enough data or the level isn't dropping.
    private func dischargeRatePerSecond() -> Double? {
        let windowStart = Date().addingTimeInterval(-3600)
        let points = store.batteryHistory.filter { $0.date >= windowStart }
        guard let first = points.first, let last = points.last else { return nil }
        let elapsed = last.date.timeIntervalSince(first.date)
        let drained = first.value - last.value
        guard elapsed >= 300, drained > 0.001 else { return nil }
        return drained / elapsed
    }

    private static func hoursMinutes(_ minutes: Int) -> String {
        String(format: "%d:%02d h", minutes / 60, minutes % 60)
    }
}

/// Battery level history with a hover cursor showing the exact level and time.
private struct BatteryChart: View {
    let history: [HistoryPoint]
    let color: Color
    let xDomain: ClosedRange<Date>

    @State private var hovered: HistoryPoint?

    var body: some View {
        Chart {
            ForEach(history) { point in
                AreaMark(x: .value("Time", point.date),
                         y: .value("Level", point.value))
                    .foregroundStyle(color.opacity(0.22))
                LineMark(x: .value("Time", point.date),
                         y: .value("Level", point.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if let hovered {
                RuleMark(x: .value("Time", hovered.date))
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Time", hovered.date),
                          y: .value("Level", hovered.value))
                    .foregroundStyle(color)
                    .symbolSize(30)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hovered = nearestPoint(to: location, proxy: proxy, geo: geo)
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if let hovered {
                Text("\(Int((hovered.value * 100).rounded()))% · \(Self.timeFormatter.string(from: hovered.date))")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func nearestPoint(to location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> HistoryPoint? {
        guard !history.isEmpty, let plotFrame = proxy.plotFrame else { return nil }
        let x = location.x - geo[plotFrame].origin.x
        guard let date: Date = proxy.value(atX: x) else { return nil }
        return history.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
