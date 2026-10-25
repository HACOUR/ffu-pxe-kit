# Setup guide - FFU deployment over PXE/WDS

> **Beta / draft.** Steps marked ✅ are verified against the FFU Builder source code.
> Steps marked ⚠ are **not yet verified end-to-end** - read the notes before you rely on them.
> Always try this in an isolated lab network first.

## How it fits together

```
 Build host (Hyper-V)                 Deployment server (WDS)                 Target device
 ─────────────────────                ───────────────────────                ─────────────
 FFU Builder                          WDS (standalone, no AD)                 PXE boot
  ├─ driverless FFU image   ───────►  boot image = FFU Builder WinPE  ──────►  WinPE
  └─ WinPE deploy ISO                 staging: FFU + Drivers\                  ApplyFFU.ps1
                                       └─ DriverMapping.json                    ├─ apply FFU
                                                                                └─ inject drivers
                                                                                   for this model
```

**Idea:** one driverless FFU for all devices. Drivers are added at apply time,
chosen per model through `DriverMapping.json`. No image per model.

## 1. Requirements

| Role | Requirement |
|---|---|
| Build host | Windows 10/11 or Server, x64, Hyper-V enabled ([FFU Builder](https://github.com/rbalsleyMSFT/FFU) requirement). Apple Silicon / ARM hosts cannot build x64 FFUs. |
| Deployment server | Windows Server 2022/2025 with the WDS role |
| Network | Isolated lab VLAN for testing. PXE clients must reach the WDS server (same subnet, or DHCP relay / IP helper towards WDS) |
| Target devices | UEFI network (PXE) boot enabled |

## 2. Build the FFU and the WinPE deploy media ✅

On the build host:

1. Install FFU Builder (see its [Quick Start](https://rbalsleymsft.github.io/FFU/quickstart.html)), default folder `C:\FFUDevelopment`.
2. Build the image **without drivers** (`InstallDrivers = false`) so it stays valid for every model.
3. Enable **`CreateDeploymentMedia`** - FFU Builder creates `WinPE_FFU_Deploy_x64.iso` containing `ApplyFFU.ps1`.
4. Save your settings in the UI - they end up in `config\FFUConfig.json`, which allows unattended builds later:

```powershell
.\BuildFFUVM.ps1 -ConfigFile 'C:\FFUDevelopment\config\FFUConfig.json'
```

> If FFU Builder downloads drivers and the model name matches more than one device,
> it asks interactively (`Read-Host`). For unattended builds use an exact model name.

## 3. Drivers and the mapping file ✅

Folder layout below the drivers root:

```
Drivers\
├─ DriverMapping.json
├─ <Manufacturer>\
│  └─ <Model>\          ← extracted driver packages (or a .wim)
```

`DriverMapping.json` is a JSON array. `ApplyFFU.ps1` detects the device via WMI,
normalizes the manufacturer and compares **only entries of that manufacturer**:

| Manufacturer | Match field in the mapping | Source on the device |
|---|---|---|
| Lenovo | `MachineType` | first 4 characters of the model (e.g. `<MT01>`) |
| Dell, HP, Fujitsu, Panasonic, Getac, … | `SystemId` | system SKU / baseboard product |
| Microsoft (Surface) | `SystemSku` (array) | `SystemSku` |
| others | `Model` | model name |

Example (placeholders):

```json
[
  {
    "Manufacturer": "<Manufacturer>",
    "Model": "<Model>",
    "DriverPath": "<Manufacturer>\\<Model>",
    "MachineType": "<MT01>"
  }
]
```

Maintain it with ffu-pxe-kit instead of editing by hand:

```powershell
Import-Module .\src\FfuPxeKit\FfuPxeKit.psm1
Add-FfuDriverModel -MappingPath '<STAGING-PATH>\Drivers\DriverMapping.json' `
    -DriversRoot '<STAGING-PATH>\Drivers' -Manufacturer '<Manufacturer>' `
    -Model '<Model>' -MachineType '<MT01>'
Test-FfuDriverMapping -MappingPath '<STAGING-PATH>\Drivers\DriverMapping.json' -DriversRoot '<STAGING-PATH>\Drivers'
```

> **Current limitation:** `Add-FfuDriverModel` writes `MachineType` (Lenovo scheme) only.
> `SystemId` / `SystemSku` for other vendors is on the roadmap.

If no rule matches, `ApplyFFU.ps1` logs the reason and **falls back to manual driver selection** -
the deployment does not stop. A failed driver injection is logged as a warning, not an error.

## 4. Install WDS in standalone mode ✅

On the deployment server (elevated PowerShell):

```powershell
Install-WindowsFeature WDS -IncludeManagementTools
wdsutil /Initialize-Server /RemInst:"<WDS-REMOTEINSTALL-PATH>" /Standalone
wdsutil /Set-Server /AnswerClients:All
```

> `AnswerClients:All` answers **every** PXE request in the network. Use an isolated VLAN,
> or restrict answering (e.g. known clients only) before connecting to a production network.

## 5. Import the FFU Builder WinPE as WDS boot image ✅

```powershell
$iso = Mount-DiskImage -ImagePath '<FFU-BUILDER-PATH>\WinPE_FFU_Deploy_x64.iso' -PassThru
$drive = ($iso | Get-Volume).DriveLetter
Import-WdsBootImage -Path "$($drive):\sources\boot.wim" -NewImageName '<BOOT-IMAGE-NAME>'
Dismount-DiskImage -ImagePath '<FFU-BUILDER-PATH>\WinPE_FFU_Deploy_x64.iso'
```

Repeat after every new WinPE build (planned: `Update-FfuBootImage`).

## 6. Network deployment - no USB stick ⚠ boot image build tested on WDS, device test pending

**Why this is needed:** the stock `ApplyFFU.ps1` reads the FFU and the `Drivers` folder
**from a local volume only** (removable NTFS drive, or fixed NTFS volume labelled `Deploy`).
PXE alone gets WinPE onto the device - not the image. Without a USB stick it stops with
*"Cannot find USB drive letter"*.

**What ffu-pxe-kit does** (`New-FfuNetworkBootImage`), in a copy of the FFU Builder `boot.wim`:

1. Patches the included `ApplyFFU.ps1` with two small, marked changes
   (`ConvertTo-FfuNetworkApplyScript`): use `FFU_DEPLOY_ROOT` (the mapped share) instead of
   a USB drive, and a per-device log name. Without these variables the original USB logic is unchanged.
2. Adds `X:\ffu-pxe-kit\Start-FfuNetworkDeploy.ps1` + `network.json` (share path, user name - **no password**).
3. Replaces `startnet.cmd`: WinPE waits for the network, asks for the password, maps the share
   (`net use N: …`) and starts the patched `ApplyFFU.ps1`.
4. Optional: injects WinPE network drivers (`-NetworkDriverPath`) - needed if WinPE has no driver for the device's NIC.
5. Optional: imports the result into WDS as a **new** boot image - the existing one stays untouched.

### 6.1 Share layout and permissions

The share root must look like a FFU Builder USB stick:

```
\\<SERVER>\<STAGING-SHARE-NAME>\
├─ <image>.ffu
├─ Drivers\
│  └─ DriverMapping.json
├─ (optional) Autopilot\  PPKG\  unattend\
```

`ApplyFFU.ps1` writes its logs (`ScriptLog_<serial>.txt`, `dism.log`, `setupapi.offline.log`)
into the share root. Recommended:

| Account | Share root | `Drivers\`, `*.ffu` |
|---|---|---|
| `<DEPLOY-USER>` (local account on the server, used only for deployment) | Modify | Read |
| Administrators | Full control | Full control |

> Keep the deployment network isolated. Deploy one device at a time until tested -
> parallel devices share `dism.log` in the root.

### 6.2 Build and import the boot image

On the WDS server (elevated PowerShell):

```powershell
Import-Module .\src\FfuPxeKit\FfuPxeKit.psm1
$iso   = Mount-DiskImage -ImagePath '<FFU-BUILDER-PATH>\WinPE_FFU_Deploy_x64.iso' -PassThru
$drive = ($iso | Get-Volume).DriveLetter
New-FfuNetworkBootImage -SourceWim "$($drive):\sources\boot.wim" -WorkPath 'C:\Temp\ffu-netboot' `
    -SharePath '\\<SERVER>\<STAGING-SHARE-NAME>' -UserName '<SERVER>\<DEPLOY-USER>' `
    -ImportToWds -BootImageName 'FFU Network Deploy'
Dismount-DiskImage -ImagePath '<FFU-BUILDER-PATH>\WinPE_FFU_Deploy_x64.iso'
```

Use `-WhatIf` first to see what would happen.

### 6.3 On the device

PXE boot → choose **FFU Network Deploy** → WinPE waits for the network → enter the password
of `<DEPLOY-USER>` → `ApplyFFU.ps1` runs as usual (select FFU, apply, drivers).
If something fails, WinPE opens a command prompt for troubleshooting (`ipconfig`, `net use`).

## 7. Health check ✅

```powershell
Copy-Item .\config\config.example.json .\config\config.json   # fill in your values
.\scripts\Test-FfuEnvironment.ps1 -ConfigPath .\config\config.json
```

Read-only. Checks folders, FFU Builder, WDS service, boot image, staging share, free space,
age of the newest FFU and the driver mapping.

## 8. Deploying a device

1. Connect the device to the deployment network, boot from network (UEFI PXE, usually F12).
2. Select the boot image `<BOOT-IMAGE-NAME>`.
3. WinPE starts `ApplyFFU.ps1`: select the FFU, the image is applied, drivers for the detected model are injected.
4. Device reboots into Windows setup/OOBE.

For network deployment (no USB) see section 6.3.

## 9. Troubleshooting

| Symptom | Where to look |
|---|---|
| Wrong / no drivers | `ScriptLog.txt` on the deploy volume - look for "No matching driver mapping rule". Check the match field for your vendor (table in section 3). Lenovo: `MachineType` = first 4 characters of the model. |
| Driver injection failed | `setupapi.offline.log` and `dism.log` copied to the deploy volume |
| "Cannot find USB drive letter" | You booted the stock FFU Builder WinPE without USB - use the network boot image (section 6) |
| "Server not reachable" in WinPE | No NIC driver in WinPE (`-NetworkDriverPath`), wrong VLAN, or DHCP |
| Device does not PXE boot | WDS service running? `AnswerClients` set? DHCP relay/IP helper towards WDS? UEFI network stack enabled? |
| Mapping file broken | `Test-FfuEnvironment` reports `DriverMapping: Invalid JSON` |

## Credits

Built around **[FFU Builder](https://github.com/rbalsleyMSFT/FFU)** by **rbalsleyMSFT** (MIT License).
The behaviour of `ApplyFFU.ps1` described here was taken from its source code.
