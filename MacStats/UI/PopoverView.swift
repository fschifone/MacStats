import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openSettings) private var openSettings

    private var sections: [PopoverSection] {
        settings.popoverOrder
            .compactMap(PopoverSection.init(rawValue:))
            .filter { settings.popoverEnabled.contains($0.rawValue) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                        if index > 0 {
                            Divider().padding(.horizontal, 16)
                        }
                        sectionView(section)
                    }
                }
            }
            Divider()
            footer
        }
        .frame(width: 380)
        .frame(maxHeight: 600)
    }

    @ViewBuilder
    private func sectionView(_ section: PopoverSection) -> some View {
        switch section {
        case .cpu: CPUSectionView(store: store)
        case .memory: MemorySectionView(store: store)
        case .fans: FansSectionView(store: store)
        case .temperatures: TemperaturesSectionView(store: store)
        case .network: NetworkSectionView(store: store)
        case .disk: DiskSectionView(store: store)
        case .gpu: GPUSectionView(store: store)
        case .battery: BatterySectionView(store: store)
        case .bluetooth: BluetoothSectionView(store: store)
        }
    }

    private var header: some View {
        HStack {
            Text("MacStats")
                .font(.system(size: 15, weight: .bold))
            Spacer()
            Button {
                NSApp.activate()
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("MacStats Settings")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack {
            Text("Awake \(UptimeSampler.format(store.uptime.awake)) · Uptime \(UptimeSampler.format(store.uptime.uptime))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
