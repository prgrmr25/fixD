# Garage Signal OBD

An independent native iOS diagnostics project built with SwiftUI and CoreBluetooth.

The application includes an offline demo dashboard, configurable gauges, session logging and CSV export, and a Bluetooth inspector for discovering a selected peripheral's services and characteristic properties. Demo telemetry is simulated. The current Bluetooth inspector performs discovery only. The project depends on live verification before enabling FIXD data exchange or the 2011 Acura MDX powertrain profile.

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
