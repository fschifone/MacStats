import SwiftUI

struct BluetoothSectionView: View {
    @ObservedObject var store: StatsStore

    var body: some View {
        if !store.bluetoothDevices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Bluetooth")
                ForEach(store.bluetoothDevices) { device in
                    HStack {
                        Text(device.name)
                            .font(.system(size: 12))
                            .foregroundStyle(device.isConnected ? .primary : .secondary)
                        Spacer()
                        if device.leftPercent != nil || device.rightPercent != nil || device.casePercent != nil {
                            HStack(spacing: 8) {
                                if let left = device.leftPercent { componentLevel("L", left) }
                                if let right = device.rightPercent { componentLevel("R", right) }
                                if let caseLevel = device.casePercent { componentLevel("Case", caseLevel) }
                            }
                        } else if let percent = device.batteryPercent {
                            Text("\(percent)%")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(percent <= 20 ? Color.red : Color.green)
                        } else {
                            Text(device.isConnected ? "Connected" : "Disconnected")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func componentLevel(_ label: String, _ percent: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(percent)%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(percent <= 20 ? Color.red : Color.green)
        }
    }
}
