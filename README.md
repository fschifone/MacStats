# MacStats

A free, native macOS menu bar system monitor — CPU, memory, fans, temperatures, network, disk, GPU, battery and Bluetooth, with live graphs. Think Usage Pro or iStat Menus, but free and open.

- **macOS 14+ · Apple Silicon · Swift + SwiftUI/AppKit · no dependencies**

## Features

**Menu bar** — one fixed-width item per stat, each one optional:

| Item | Shows |
|---|---|
| CPU | total usage % |
| Memory | % and/or used/available GB (configurable) |
| Fan | fastest fan rpm |
| Temperature | CPU die °C |
| Network | ↓/↑ throughput, stacked two-line |
| Disk | free space |
| GPU | utilization % |
| Battery | % with a dynamic icon: ⚡ charging, 🔌 on AC, battery level otherwise |
| Bluetooth | connected device count |
| Time awake | time since last sleep |

**Popover** (click any item) — reorderable, selectable sections with live Swift Charts graphs:

- **CPU** — usage history, user/system split, load average, per-core bars (P/E clusters color-coded, hover a core for its exact %)
- **Memory** — usage history, pressure, app/wired/compressed composition bar (hover a segment for its share), swap; hover the section for free/cached/swap details
- **Fans & Temperatures** — CPU temperature history, fan rpm, CPU/GPU die temps (read from the SMC)
- **Network** — down/up history with the active interface
- **Disk** — usage bar, free space, live read/write throughput
- **GPU** — utilization history
- **Battery** — discharge graph over a 1/12/24 h window, time remaining, health, cycle count
- **Bluetooth** — paired devices with battery levels (AirPods show L/R/case separately)

**Settings** (gear in the popover) — tabbed window with a *live preview* of every widget:

- choose and preview the menu bar items
- choose and reorder the popover sections
- memory display options, refresh interval (1/2/5 s), graph history (5/10/30 min), battery graph window
- launch at login

## Building

Requires Xcode 15+. The project file is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`, but a generated `MacStats.xcodeproj` is committed, so either works:

```sh
# straight build
xcodebuild -project MacStats.xcodeproj -scheme MacStats -configuration Release build

# or regenerate the project first after changing project.yml
xcodegen generate
```

Then copy `MacStats.app` from the build products to `/Applications`.

> **Note:** the app is not sandboxed — reading fan speeds and temperatures requires direct access to the SMC (`AppleSMC` IOKit user client), which the App Store sandbox forbids. That's the price of free fan readings. It's also why this app can't ship on the App Store.

On first launch macOS asks for **Bluetooth** permission (used to show device battery levels). Everything else needs no special permissions.

## How it reads the stats

All sampling is in `MacStats/Sampling/`, one small sampler per domain, no private frameworks beyond the well-trodden SMC/IOKit paths every monitor app uses:

| Stat | Source |
|---|---|
| CPU | `host_processor_info` tick deltas, P/E core counts via `sysctl hw.perflevel*` |
| Memory | `host_statistics64`, pressure via `kern.memorystatus_vm_pressure_level`, swap via `vm.swapusage` |
| Fans & temps | `AppleSMC` user client — keys enumerated at startup (`F*Ac`, `Tp*`, `Tg*`), cluster averages |
| Network | `getifaddrs` byte-counter deltas |
| Disk | `URLResourceValues` for capacity, `IOBlockStorageDriver` statistics for throughput |
| GPU | `IOAccelerator` → `PerformanceStatistics` → `Device Utilization %` |
| Battery | `IOPSCopyPowerSourcesInfo` + `AppleSmartBattery` registry (health, cycles) |
| Bluetooth | `IOBluetoothDevice` paired list; battery via GATT Battery Service (0x180F), the HID registry, and the system profiler cache |
| Uptime | `kern.boottime` + `ProcessInfo.systemUptime` |

Temperature keys on Apple Silicon are model-specific and undocumented; MacStats enumerates all SMC keys once and averages the plausible CPU (`Tp*`) and GPU (`Tg*`) sensors, which tracks Activity-Monitor-style readings closely on M-series machines.

## License

MIT — do whatever you like with it.
