# ffu-pxe-kit

PowerShell toolkit for running **FFU-based Windows deployment over PXE** with
Windows Deployment Services (WDS) — built around [FFU Builder](https://github.com/rbalsleyMSFT/FFU).

![status: beta](https://img.shields.io/badge/status-beta-orange)

> **⚠ Beta:** All functions are unit-tested. On a real WDS server the health check
> and building/importing the network boot image work. **The end-to-end deployment
> on a device has not been tested yet.** Further testing is required before
> production use. Use at your own risk and try it in a lab first.

## Test status

| Area | Unit tests (mocked) | Tested on real WDS server | Tested on a device |
|---|---|---|---|
| Config reader | ✅ | ✅ | — |
| Driver mapping (`Test-FfuDriverMapping`) | ✅ | ✅ Lenovo (MachineType) + HP (SystemId) mappings from FFU Builder | — |
| Driver mapping (`Add-FfuDriverModel`) | ✅ | ⏳ | — |
| Health check (`Test-FfuEnvironment`) | ✅ | ✅ Windows Server, WDS standalone, lists mapped models (Lenovo + HP) | — |
| Network boot image (`ConvertTo-FfuNetworkApplyScript`, `New-FfuNetworkBootImage`) | ✅ patch verified against ApplyFFU.ps1 2026-04 and current main | ✅ built, patched, imported into WDS as additional boot image | ⏳ pending |
| Sync to staging (`Sync-FfuStaging`) | ✅ | ✅ detects FFU Builder downloading straight into the share (`SameFolder`); copy/mirror path not yet run on a server | — |
| Button window (`gui/FfuPxeKit-Gui.ps1`) | syntax only | ✅ *Health check* and *Sync drivers* buttons | — |
| Network deployment in WinPE (`winpe/Start-FfuNetworkDeploy.ps1`) | ✅ syntax/static checks | — | ⏳ pending |
| `Install-FfuPxeServer`, `Update-FfuBootImage`, `Invoke-FfuMonthlyBuild`, `Remove-FfuOldImages` | planned | planned |

## What it does

FFU Builder creates the image (FFU) and the WinPE deploy media.
`ffu-pxe-kit` adds the parts around it:

| Function | Purpose |
|---|---|
| `New-FfuNetworkBootImage` | **Deploy over the network without USB:** builds a WinPE boot image that maps the staging share and runs a patched copy of FFU Builder's `ApplyFFU.ps1` |
| `ConvertTo-FfuNetworkApplyScript` | Minimal, version-checked patch of `ApplyFFU.ps1` (deploy root + per-device log name) |
| `Install-FfuPxeServer` | Set up a standalone WDS server, staging share and boot image |
| `Update-FfuBootImage` | Replace the WDS boot image after a new WinPE build |
| `Invoke-FfuMonthlyBuild` | Headless monthly FFU build via FFU Builder `-ConfigFile` |
| `Add-FfuDriverModel` | Add a device model and maintain the driver mapping |
| `Test-FfuEnvironment` | Health check: services, share, free space, mapping consistency |
| `Sync-FfuStaging` | Copy drivers + `DriverMapping.json` (and optionally the newest FFU) from FFU Builder to the PXE share |
| `gui\FfuPxeKit-Gui.ps1` | Small window with buttons: *Sync drivers*, *Sync drivers + newest image*, *Health check* |
| `Remove-FfuOldImages` | Keep the last *n* FFU images, remove the rest |

## Concept

- **One driverless FFU** for all devices
- **Drivers per model** are injected at apply time, selected through a mapping file
- **PXE boot** via standalone WDS (no Active Directory required)
- **No USB stick:** stock FFU Builder deploys from USB only - ffu-pxe-kit adds network deployment
- **No stored passwords:** the share password is asked at runtime in WinPE

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
