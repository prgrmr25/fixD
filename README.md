# Garage Signal OBD

An independent native iOS diagnostics project built with SwiftUI and CoreBluetooth.

Garage Signal opens in Vehicle mode. On iPhone, a matched FIXD adapter can start a read-only scan or poll standard OBD-II readings from responding ECUs. The Dashboard and Signals show the latest vehicle readings by ECU, with timestamps and availability states. Demo mode shows simulated readings, and Drive Logs records and exports demo sessions.

The module browser gives the engine/PCM, automatic transmission, SH-AWD, ABS/VSA, and other systems separate status pages. Vehicle testing has confirmed live standard RPM through FIXD on iPhone. The scan includes engine oil temperature and ECU-reported module voltage when each responder advertises support. It includes model-specific descriptions for selected 2011 Acura MDX VTEC and torque converter trouble codes. The module pages can try a single targeted read-only Honda CAN data request for the engine, transmission, SH-AWD, ABS/VSA, TPMS, SRS, and instrument cluster. The beta shows accepted replies as raw data and reports their CAN address and data identifier. A directed standard read checks the route for known standard responders, and each scan has a shareable trace when no reply arrives. The field-tested Honda transmission identification response unlocks a follow-up read of its raw data list. An incomplete PCM response can trigger one adapter-paced retry. Manufacturer-specific live field values and service commands require separate vehicle validation.

DiagnosticsCore decodes complete SAE J1979 service 01 payloads. Replay tests exercise RPM, vehicle speed, coolant, paged capabilities, oil temperature, module voltage, ignition advance, and both banks of fuel trims.

## Build

On macOS with Xcode and XcodeGen installed, run the following from this checkout.

```sh
swift test --package-path ios/DiagnosticsCore
cd ios
xcodegen generate
open GarageSignal.xcodeproj
```

The macOS workflow generates the project, runs the decoder tests, and compiles the app for iOS with signing disabled.
