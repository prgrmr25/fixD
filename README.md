# Garage Signal OBD

An independent native iOS diagnostics project built with SwiftUI and CoreBluetooth.

Garage Signal opens in Vehicle mode. On iPhone, a matched FIXD adapter can start a read-only scan or poll standard OBD-II readings from responding ECUs. The Dashboard and Signals show the latest vehicle readings by ECU, with timestamps and availability states. Demo mode shows simulated readings, and Drive Logs records and exports demo sessions.

The module browser gives the engine/PCM, automatic transmission, SH-AWD, ABS/VSA, and other systems separate status pages. Vehicle testing has confirmed live standard RPM through FIXD on iPhone. The scan includes engine oil temperature and ECU-reported module voltage when each responder advertises support. It includes model-specific descriptions for selected 2011 Acura MDX VTEC and torque converter trouble codes.

The module pages support targeted read-only CAN requests and retain shareable traces. When the automatic transmission replies with its identification and a complete Honda data list, the app shows a timestamped snapshot of fluid temperature, engine RPM, and both shaft speeds. The decoder uses a Honda family reference layout and awaits independent vehicle cross-checks. An incomplete PCM response can trigger one adapter-paced retry.

Acura's 2011 MDX service manual shows a factory K-line diagnostic connection on DLC pin 7 for SH-AWD, ABS/VSA, TPMS, and SRS. Acura lists the instrument cluster in the body electrical diagnostic menu. The app's direct CAN probes for these modules check candidate routes. A K-line scan requires an adapter that supports the vehicle's session and a verified read transaction. [Acura DLC circuit troubleshooting](https://charm.li/Acura/2011/MDX%20V6-3.7L/Repair%20and%20Diagnosis/Powertrain%20Management/Computers%20and%20Control%20Systems/Data%20Link%20Connector/Testing%20and%20Inspection/) · [Acura body electrical diagnostics](https://charm.li/Acura/2011/MDX%20V6-3.7L/Repair%20and%20Diagnosis/Powertrain%20Management/Computers%20and%20Control%20Systems/Information%20Bus/Testing%20and%20Inspection/Component%20Tests%20and%20General%20Diagnostics/Troubleshooting%20-%20B-CAN%20System%20Diagnosis%20Test%20Mode%20A/)

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
