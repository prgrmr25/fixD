# Garage Signal OBD

An independent native iOS diagnostics project built with SwiftUI and CoreBluetooth.

Garage Signal opens in Vehicle mode. On iPhone, a matched FIXD adapter can start a read-only scan or poll standard OBD-II readings from responding ECUs. The Dashboard and Signals show the latest vehicle readings by ECU, with timestamps and availability states. Demo mode shows simulated readings, and Drive Logs records and exports demo sessions.

The module browser gives the engine/PCM, automatic transmission, SH-AWD, ABS/VSA, and other systems separate status pages. The engine page shows returned standard readings and trouble codes. The FIXD Bluetooth profile has been observed on an iPhone. An end-to-end vehicle exchange and Acura-specific commands still require hardware validation. Acura-specific readings and service functions remain unavailable.

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
