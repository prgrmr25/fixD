# Garage Signal OBD

An independent native iOS diagnostics project built with SwiftUI and CoreBluetooth.

The application includes an offline demo dashboard, configurable gauges, session logging and CSV export, a searchable 67-signal list, and a Bluetooth inspector. The module browser groups PCM, automatic transmission, SH-AWD, ABS/VSA, and other Acura MDX diagnostics. The service functions screen lists PCM reset, relearns, and calibrations with their availability. Demo telemetry is simulated. The FIXD scanner is designed to read ECU-reported standard readings and stored, pending, and permanent trouble codes over a compatible adapter. The first real adapter/vehicle exchange remains unverified. Acura-specific PIDs and state-changing service functions remain unavailable.

DiagnosticsCore decodes complete SAE J1979 service 01 payloads. Its replay tests exercise RPM, vehicle speed, coolant temperature, supported-PID bitmaps, ignition advance, and the four standard fuel-trim channels.

## Build

On macOS with Xcode and XcodeGen installed, run the following from this checkout.

```sh
swift test --package-path ios/DiagnosticsCore
cd ios
xcodegen generate
open GarageSignal.xcodeproj
```

The macOS workflow generates the project, runs the decoder tests, and compiles the app for iOS with signing disabled.
