# ffu-pxe-kit

PowerShell toolkit for running **FFU-based Windows deployment over PXE** with
Windows Deployment Services (WDS) — built around [FFU Builder](https://github.com/rbalsleyMSFT/FFU).

![status: beta](https://img.shields.io/badge/status-beta-orange)

> **⚠ Beta:** Functions are unit-tested (Pester, mocked), but **not yet tested
> end-to-end** against a real WDS/PXE environment. Further testing is required
> before production use. Use at your own risk and try it in a lab first.

## Test status

| Area | Unit tests (mocked) | Tested on real WDS/PXE |
|---|---|---|
| Config reader | ✅ | — |
| Driver mapping (`Add-FfuDriverModel`, `Test-FfuDriverMapping`) | ✅ | ⏳ pending |
| Health check (`Test-FfuEnvironment`) | ✅ | ⏳ pending |
| `Install-FfuPxeServer`, `Update-FfuBootImage`, `Invoke-FfuMonthlyBuild`, `Remove-FfuOldImages` | planned | planned |

## What it does

FFU Builder creates the image (FFU) and the WinPE deploy media.
`ffu-pxe-kit` adds the parts around it:

| Function | Purpose |
|---|---|
| `Install-FfuPxeServer` | Set up a standalone WDS server, staging share and boot image |
| `Update-FfuBootImage` | Replace the WDS boot image after a new WinPE build |
| `Invoke-FfuMonthlyBuild` | Headless monthly FFU build via FFU Builder `-ConfigFile` |
| `Add-FfuDriverModel` | Add a device model and maintain the driver mapping |
| `Test-FfuEnvironment` | Health check: services, share, free space, mapping consistency |
| `Remove-FfuOldImages` | Keep the last *n* FFU images, remove the rest |

## Concept

- **One driverless FFU** for all devices
- **Drivers per model** are injected at apply time, selected through a mapping file
- **PXE boot** via standalone WDS (no Active Directory required)

## Requirements

- Windows Server 2022/2025 (x64) with WDS
- Hyper-V capable x64 host for FFU Builder
- PowerShell 5.1 (Windows) — tests also run on PowerShell 7

## Setup guide

👉 **[docs/setup-guide.md](docs/setup-guide.md)** - step by step, from FFU build to PXE deployment (draft).

## Quick start: health check

Read-only - changes nothing on the server.

```powershell
Copy-Item .\config\config.example.json .\config\config.json   # then fill in your values
.\scripts\Test-FfuEnvironment.ps1 -ConfigPath .\config\config.json
```

Each check returns `Pass`, `Warn`, `Fail` or `Skip`. Exit code `1` if anything failed.
Checks: config, folders, FFU Builder, WDS service, boot image, staging share,
free disk space, age of the newest FFU image, driver mapping consistency.

## Configuration

Copy `config/config.example.json` to `config/config.json` and fill in your values.
`config.json` is excluded from Git — never commit real server names, paths or credentials.

## Credits

This project builds on **[FFU Builder](https://github.com/rbalsleyMSFT/FFU)** by
**rbalsleyMSFT** (MIT License, Copyright (c) 2023 rbalsleyMSFT).
FFU Builder does the heavy lifting — image build, WinPE media, driver download.
`ffu-pxe-kit` does not include FFU Builder code; install FFU Builder separately.

## License

MIT — see [LICENSE](LICENSE).
