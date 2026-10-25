@echo off
rem ffu-pxe-kit: start WinPE networking, then network deployment
wpeinit > NUL
powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c > NUL
powershell -NoProfile -ExecutionPolicy Bypass -File X:\ffu-pxe-kit\Start-FfuNetworkDeploy.ps1
