# ⚡ Smart Bypass Charging

![Version](https://img.shields.io/badge/Version-v1.1.2-blue?style=for-the-badge)
![KernelSU](https://img.shields.io/badge/KernelSU-Supported-black?style=for-the-badge&logo=android&logoColor=white)
![Magisk](https://img.shields.io/badge/Magisk-20.4%2B-00B0FF?style=for-the-badge&logo=magisk&logoColor=white)
![License](https://img.shields.io/badge/License-GPLv3-green?style=for-the-badge)

**Smart Bypass Charging** is an all-in-one battery health, wattage controller, and gaming bypass charging module for **KernelSU**, **APatch**, and **Magisk**. It protects your battery from heat and degradation by pausing charging at custom limits, regulating charging speed, and providing automatic **Bypass (Idle) Mode** during gaming.

---

## ⚠️ Risk Notice & Disclaimer

> **IMPORTANT — PLEASE READ BEFORE USE:**
> This module functions by directly writing to kernel power supply and battery charging control `sysfs` / `procfs` nodes (such as `/sys/class/power_supply/battery/*`).
> - Kernel charging implementations vary widely across OEMs, PMICs, and custom kernels. Writing to charging control nodes may cause unexpected charging behavior, inaccurate battery percentage reporting, failure to resume charging until reboot, or PMIC/charger resets on certain devices.
> - Always monitor your device temperature and charging state during initial use.
> - If charging does not resume after unplugging, disable or remove the module and reboot your device to restore default kernel states.
> - You are using this module at your own risk. The developer is not responsible for any hardware, battery, or device issues resulting from its use.

---

## ✨ Key Features

* **📊 Live Power & Health Telemetry:** Real-time dashboard displaying live charging **Wattage (W)**, **Current (mA)**, **Voltage (V)**, **Temperature (°C)**, **Battery Health (%)**, and **Charge Cycle Count**.
* **🔥 Force Bypass & 🎮 Auto-Bypass in Games:**
  * **Force Bypass Mode:** One-tap toggle to pause battery charging at any level and power the phone directly from the charger (AC/Idle power).
  * **Auto-Bypass in Games:** Automatically activates Bypass Mode when a configured game is launched in the foreground and resumes normal operation when closed.
* **🎚️ Charging Speed / Wattage Controller:** Control charging current on the fly with 3 presets:
  * **⚡ Fast (Max):** Unthrottled hardware fast charging.
  * **⚖️ Balanced (~10W / 2000mA):** Moderate speed with reduced heat.
  * **🌙 Cool Night (~5W / 1000mA):** Slow, cool overnight charging to maximize battery longevity.
* **🛡️ Smart Charging Limits & 100% Override:**
  * Set custom **Stop Charging** (e.g., 80%) and **Resume Charging** (e.g., 75%) thresholds.
  * **🔋 Charge to 100% Once:** One-tap toggle to temporarily allow a full 100% charge until the next unplug.
* **🌡️ Smart Thermal Auto-Pause:** Automatically pauses charging if battery temperature reaches **≥42°C** and safely resumes once it cools down to **≤38°C**.
* **🧠 Universal Auto-Detection Engine:** Probes, verifies, and caches the working kernel charging switch for your device (and caches failure on unsupported kernels to prevent continuous sysfs polling).
* **🎨 Native Material Design 3 WebUI:** Clean Android 14 / KernelSU styled interface with automatic **Light & Dark Mode** support.
* **🔔 Smart System Notifications:** Real-time alerts for Charger Connect/Disconnect, Bypass Activation, Limit Reached, and Thermal Pause events.

---

## 🔒 Security & Transparency

* **100% Auditable Shell & Web Code:** Built entirely with plain-text POSIX shell scripts (`customize.sh`, `service.sh`) and a static HTML/CSS/JS WebUI (`webroot/index.html`).
* **Zero Binaries & Zero Network Calls:** Contains no prebuilt binaries/blobs and makes zero external network requests.
* **Clean Storage:** No clutter on `/sdcard`. All configurations (`config.conf`, `games.conf`, `active_switch.conf`) are stored strictly inside `/data/adb/modules/smart_bypass_charging/`.

---

## 📱 How to Access Settings (WebUI)

* **For KernelSU / APatch Users:**
  1. Open the **KernelSU / APatch Manager** app and go to the **Modules** tab.
  2. Tap on the **Smart Bypass Charging** card to launch the built-in Material 3 WebUI.

* **For Magisk Users:**
  1. Download and install the standalone **[KSUWebUI APK](https://github.com/5ec1cff/KsuWebUIStandalone/releases)**.
  2. Open **KSUWebUI**, grant root access, and select **Smart Bypass Charging**.

---

## 📦 Installation

1. Download the latest `.zip` package from the **[Releases](../../releases)** page.
2. Flash the zip in **KernelSU**, **APatch**, or **Magisk** Manager.
3. **Reboot** your device.

---

## 🤝 Credits & Inspiration

* Inspired by the universal switch mechanisms of **ACC (Advanced Charging Controller)**.
* Developed by **[mhmithu](https://github.com/mhmithu)**.

## 📄 License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0-only)** — see the [LICENSE](LICENSE) file for details.
