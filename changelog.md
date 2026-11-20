# Changelog

## v1.1.1
- **Fixed (Installer):** Replaced the custom 6-line `update-binary` with the official standard Magisk `util_functions.sh` installer for full Magisk & KernelSU compatibility.
- **Fixed (Bypass Detection):** Corrected current threshold to `50000 uA` (`50mA`), removed `input_suspend`, and explicitly rejected `Discharging` status so battery discharge is never misidentified as valid bypass/idle mode.
- **Fixed (Switch Probing):** Cached probe failure (`NONE` in `active_switch.conf`) when no compatible kernel switch is found, preventing continuous sysfs re-probing every 2 seconds on unsupported devices.
- **Docs:** Added a clear **Risk Notice & Disclaimer** in `README.md` regarding writing directly to kernel charging control `sysfs` nodes.

## v1.1.0
- **Fixed:** Resolved 14W (3A) fast charging ceiling cap issue on first charger plug-in.
- **New:** Added **Charging Speed Controller** (Fast Max, Balanced 10W, and Cool Night 5W modes).
- **New:** Added **Live Power & Health Telemetry** in WebUI (Live Wattage, Current mA, Voltage, Battery Health %, and Cycle Count).
- **New:** Added **Smart Thermal Auto-Pause** (Automatically pauses charging at >=42°C and resumes at <=38°C).
- **New:** Added **Auto-Bypass in Games** (Automatically activates bypass mode when a configured game is in the foreground).
- **New:** Added **Charge to 100% Once** toggle.

## v1.0.1
- Added Universal Auto-Detection Engine for charging & bypass switches.
- Added Material Design 3 WebUI (Auto Light/Dark theme).
- Added Force Bypass Mode for gaming and Smart Charging Limits.
- Added Smart Notifications (Plug/Unplug, State changes, and >=42°C Overheating warning).

## v1.0.0 (Initial Release)
- Initial stable release with Universal Auto-Detection Engine and Material 3 WebUI.
