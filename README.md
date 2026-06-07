<div align="center">

<img src="https://raw.githubusercontent.com/flutter/website/main/src/assets/images/shared/brand/flutter/logo+wordmark/horizontal/default.svg" height="72" alt="Flutter Logo"/>

# Flutter Windows Installer

**The fastest, safest, most reliable way to install Flutter SDK on Windows — no manual steps, no broken downloads, no PATH headaches.**

[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)](https://docs.microsoft.com/en-us/powershell/)
[![Flutter Stable](https://img.shields.io/badge/Flutter-stable%20track-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows&logoColor=white)](https://www.microsoft.com/windows)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![No Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)](.)

```
  ______ _       _   _
 |  ____| |     | | | |
 | |__  | |_   _| |_| |_ ___ _ __
 |  __| | | | | | __| __/ _ \ '__|
 | |    | | |_| | |_| ||  __/ |
 |_|    |_|\__,_|\__|\__\___|_|

     ╔══════════════════════════════════╗
     ║    F L U T T E R  I N S T A L L E R   ║
     ║    automated  ·  verified  ·  resumable    ║
     ╚══════════════════════════════════╝
```

**One double-click. Flutter is installed. That's it.**

[Quick Start](#-quick-start) · [Features](#-features) · [How It Works](#-how-it-works) · [FAQ](#-faq) · [Comparison](#-vs-alternatives)

</div>

---

## The Problem With Installing Flutter on Windows

The [official Flutter install guide](https://docs.flutter.dev/get-started/install/windows) asks you to:

1. Manually download a 1.7 GB zip
2. Extract it somewhere
3. Edit system PATH by hand
4. Hope your download didn't get corrupted
5. Hope it didn't cut out at 98% on a slow connection

If your internet drops mid-download — start over. If you added the wrong PATH — Flutter silently doesn't work. If you downloaded the wrong architecture — good luck figuring out why.

**This installer fixes all of that.**

---

## ✨ Features

| Feature | What it does |
|---|---|
| **Auto-detects latest release** | Fetches the official Flutter manifest and resolves the exact latest stable version — no hardcoded URLs |
| **Resumable download** | Picks up exactly where it left off after a disconnect — critical on slow or unstable connections |
| **SHA-256 integrity check** | Verifies the downloaded archive against Google's official manifest hash before extracting |
| **Architecture-aware** | Automatically selects `x64` or `ARM64` build based on your machine |
| **Dual extraction engine** | Uses Windows built-in `tar.exe` for speed; falls back to `.NET ZipArchive` if needed |
| **Idempotent** | Already have Flutter installed? It checks your version and skips if you're already up to date |
| **PATH management** | Adds `C:\flutter\bin` to your system PATH without creating duplicates |
| **Live progress bar** | Animated bar with real-time download speed, bytes transferred, and ETA |
| **50-attempt retry** | Automatically reconnects and resumes on network failure — no babysitting required |
| **Zero dependencies** | Pure PowerShell, no chocolatey, no winget, no external tools needed |

---

## ⚡ Quick Start

### Option 1 — Double-click (Recommended for most users)

1. Download [`install_flutter.ps1`](install_flutter.ps1)
2. Right-click → **Run with PowerShell**
3. Done. Open a new terminal and run `flutter doctor`

### Option 2 — One-liner from PowerShell

```powershell
irm https://raw.githubusercontent.com/zamin-naqvi/flutter-windows-installer/main/install_flutter.ps1 | iex
```

### Option 3 — Clone and run

```powershell
git clone https://github.com/zamin-naqvi/flutter-windows-installer
cd flutter-windows-installer
.\install_flutter.ps1
```

> **First run?** If PowerShell says "execution policy", run this first:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

---

## 🎬 What It Looks Like

```
  ->  Checking the latest Flutter (stable) release...
  OK  Latest stable: Flutter 3.44.1 (x64)
  ->  Found a previous partial download; attempting to resume it.
  ->  Downloading Flutter 3.44.1...
       https://storage.googleapis.com/.../flutter_windows_3.44.1-stable.zip
   [##########--------------------]  34%  601 MB/1.77 GB  2.1 MB/s  ETA 09:42

  ->  Verifying download integrity (SHA-256)...
  OK  Integrity verified (a3f9c12b8d04e71f...)
  ->  Extracting with tar (handles large archives)...
   / unpacking...  elapsed 00:43
  OK  Extracted to C:\flutter
  OK  Added C:\flutter\bin to the system PATH.
  OK  Flutter 3.44.1 is ready.

============  SUCCESS  ============

  Next steps:
    1) Open a NEW terminal (so the PATH refreshes).
    2) Run:  flutter doctor
    3) In your project, run:  flutter pub get
```

---

## 🔧 Options

The installer works perfectly with no arguments, but supports customization:

```powershell
# Install to a custom directory (default: C:\flutter)
.\install_flutter.ps1 -InstallRoot "D:\Dev"

# Install a different channel (default: stable)
.\install_flutter.ps1 -Channel beta
.\install_flutter.ps1 -Channel main
```

| Parameter | Default | Description |
|---|---|---|
| `-InstallRoot` | `C:\` | Root where the `flutter` folder will be created |
| `-Channel` | `stable` | Flutter release channel: `stable`, `beta`, or `main` |

---

## 🔍 How It Works

```
┌─────────────────────────────────────────────────────────┐
│                    install_flutter.ps1                    │
└────────────────────────┬────────────────────────────────┘
                         │
           ┌─────────────▼─────────────┐
           │  1. Fetch release manifest │  ← storage.googleapis.com
           │     (latest stable hash)   │
           └─────────────┬─────────────┘
                         │
           ┌─────────────▼─────────────┐
           │  2. Architecture detection │  ← x64 or ARM64
           └─────────────┬─────────────┘
                         │
           ┌─────────────▼─────────────┐
           │  3. Resumable download    │  ← HTTP Range requests
           │     with retry (50x)      │    auto-resume on drop
           └─────────────┬─────────────┘
                         │
           ┌─────────────▼─────────────┐
           │  4. SHA-256 verification  │  ← against manifest hash
           └─────────────┬─────────────┘
                         │
           ┌─────────────▼─────────────┐
           │  5. Extract SDK           │  ← tar.exe → ZipArchive
           └─────────────┬─────────────┘
                         │
           ┌─────────────▼─────────────┐
           │  6. Add to system PATH    │  ← no duplicates
           └─────────────┬─────────────┘
                         │
           ┌─────────────▼─────────────┐
           │  7. Verify installation   │  ← flutter --version
           └───────────────────────────┘
```

The installer uses **HTTP Range requests** (`Content-Range` headers) to resume downloads — the same mechanism used by download managers. If the server doesn't support range requests, it gracefully falls back to a full restart.

---

## ⚖️ vs Alternatives

| | This Installer | `winget install Flutter` | Manual (Official Guide) | Chocolatey |
|---|:---:|:---:|:---:|:---:|
| Resumable download | ✅ | ❌ | ❌ | ❌ |
| SHA-256 verification | ✅ | ✅ | ❌ | Partial |
| Architecture detection | ✅ | ✅ | Manual | ✅ |
| Live progress + ETA | ✅ | Basic | ❌ | Basic |
| Auto PATH setup | ✅ | ✅ | Manual | ✅ |
| Zero dependencies | ✅ | Requires winget | ✅ | Requires choco |
| Double-click install | ✅ | ❌ | ❌ | ❌ |
| Idempotent (safe to re-run) | ✅ | Partial | ❌ | Partial |
| Works offline-resume | ✅ | ❌ | ❌ | ❌ |

> **Bottom line:** If you know `winget` and have a fast connection, use winget. If you're on a slow/unstable connection, setting up a new machine, or distributing this to non-developer teammates — this installer is the better choice.

---

## 🌐 Why Resumable Downloads Matter

Flutter SDK is ~1.8 GB. On a typical internet connection in many parts of the world:

- `winget` or a browser download that drops at 94% → **start over from 0 MB**
- This installer drops at 94% → **resumes from 1.69 GB**

The script uses `HttpWebRequest` with `AddRange()` to issue a partial content request (`206 Partial Content`). If the server responds with `200 OK` instead (no range support), it automatically clears the partial file and restarts cleanly.

---

## 🛡️ Security

- Downloads only from `storage.googleapis.com` — Google's official Flutter CDN
- Verifies SHA-256 against Google's official release manifest (not a third-party source)
- If the hash doesn't match, the corrupted file is **deleted automatically** and the installer aborts
- No scripts are downloaded from this repo and executed — you can read every line before running

---

## ❓ FAQ

**Q: Does this require admin rights?**  
A: Yes — modifying the system `PATH` requires elevated privileges. Right-click → "Run as Administrator" if not prompted automatically.

**Q: Will this overwrite my existing Flutter installation?**  
A: If the installed version matches the latest stable, it skips everything. If there's a newer version, it removes the old `C:\flutter` folder and installs fresh.

**Q: Can I change the install location?**  
A: Yes. Use `-InstallRoot "D:\Dev"` and Flutter will be installed at `D:\Dev\flutter`.

**Q: What if I lose internet during the download?**  
A: Just re-run the installer. It will resume from exactly where it left off, no flags needed.

**Q: Does this work on ARM Windows (Surface Pro X, Copilot+ PCs)?**  
A: Yes — it automatically detects ARM64 and downloads the correct build.

**Q: What PowerShell version do I need?**  
A: PowerShell 5.1, which ships with Windows 10 and 11 by default. No upgrade needed.

---

## 📋 Requirements

- Windows 10 or Windows 11 (any edition)
- PowerShell 5.1+ (pre-installed on all modern Windows)
- Administrator privileges (for PATH modification)
- Internet connection (resumable — doesn't need to be stable)
- ~4 GB free disk space (1.8 GB download + 2 GB extracted)

---

## 🤝 Contributing

Pull requests are welcome. Some ideas for improvement:

- [ ] Run `flutter doctor` automatically post-install
- [ ] `flutter precache` for common platforms after extract
- [ ] GUI progress window using WPF/WinForms
- [ ] Uninstaller script
- [ ] Silent/headless mode flag (`-Silent`) for CI/CD pipelines
- [ ] Support for FVM (Flutter Version Manager) layout

---

## 📄 License

MIT © [AeroLoom Studio](https://github.com/zamin-naqvi)

---

<div align="center">

**If this saved you from a failed 1.7 GB download, consider leaving a ⭐**

Made with ☕ by [Syed](https://github.com/zamin-naqvi)

</div>
