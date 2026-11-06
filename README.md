# ⚡ Smart Bypass Charging

![Magisk](https://img.shields.io/badge/Magisk-20.4%2B-00B0FF?style=for-the-badge&logo=magisk&logoColor=white)
![KernelSU](https://img.shields.io/badge/KernelSU-Supported-black?style=for-the-badge&logo=android&logoColor=white)
![License](https://img.shields.io/badge/License-GPLv3-blue?style=for-the-badge)

**Smart Bypass Charging** is an advanced charging controller module for **KernelSU** and **Magisk**. It protects your battery health by stopping charging at a custom limit and provides a dedicated **Force Bypass Mode** for gamers to power the phone directly from the charger without heating or charging the battery.

---

## ✨ Key Features

* **🧠 Universal Auto-Detection Engine:** Automatically probes, verifies, and caches the exact working kernel charging switch for your device (Supports GKI, Qualcomm, MediaTek, Google Tensor, Exynos, Xiaomi, Samsung, OnePlus/Oplus, Asus, etc.).
* **🔥 Gaming Bypass Mode:** One-tap toggle to pause battery charging at any percentage and run the device directly on AC/USB power (Idle Mode), reducing heat and battery degradation during heavy gaming.
* **🛡️ Smart Charging Limits:** Set custom **Stop Charging** (e.g., 90%) and **Resume Charging** (e.g., 80%) thresholds.
* **🎨 Material Design 3 WebUI:** Built-in native Android 14/KernelSU styled graphical interface with automatic **Light & Dark Mode** support.
* **🔔 Smart Notifications:** Real-time system notifications for Charger Connect/Disconnect, Limit Reached, Bypass Activation, and **Overheating Warnings (≥42°C)**.
* **🧹 Clean Storage:** Zero clutter on your `/sdcard`. All configurations are stored securely inside the module's internal directory.

---

## 📱 How to Access Settings (WebUI)

* **For KernelSU / APatch Users:**
  1. Open the **KernelSU Manager** app and go to the **Modules** tab.
  2. Tap on the **Smart Bypass Charging** card (or the Web/Globe icon) to open the Settings GUI directly.

* **For Magisk Users:**
  1. Download and install the lightweight **[KSUWebUI APK](https://github.com/5ec1cff/KsuWebUIStandalone/releases)** from GitHub.
  2. Open the **KSUWebUI** app, grant root permission, and select **Smart Bypass Charging** to configure your settings.

---

## 📦 Installation

1. Download the latest release `.zip` from the **[Releases](../../releases)** page.
2. Open **Magisk**, **KernelSU**, or **APatch** Manager.
3. Flash the zip file in the **Modules** section.
4. **Reboot** your device.

---

## 🤝 Credits & Inspiration

* Inspired by the switch database of **ACC (Advanced Charging Controller)**.
* Designed for the Android Root & Modding Community.

## 📄 License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)** - see the [LICENSE](LICENSE) file for details.