import SwiftUI

struct DiskSectionView: View {
    @ObservedObject var store: StatsStore

    private var disk: DiskSnapshot? { store.latestDisk }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Disk")
                Spacer()
                Text(disk.map { "\(ByteFormat.diskGigabytes($0.freeBytes)) free" } ?? "--")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
            }

            if let disk {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.purple)
                            .frame(width: geo.size.width * disk.usedFraction)
                    }
                }
                .frame(height: 6)
                .help("\(ByteFormat.diskGigabytes(disk.usedBytes)) used of \(ByteFormat.diskGigabytes(disk.totalBytes))")

                HStack {
                    Text("\(disk.volumeName) · \(ByteFormat.diskGigabytes(disk.usedBytes)) of \(ByteFormat.diskGigabytes(disk.totalBytes)) used")
                    Spacer()
                    Text("R \(ByteFormat.rate(disk.readBytesPerSec)) · W \(ByteFormat.rate(disk.writeBytesPerSec))")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
