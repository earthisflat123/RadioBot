# Native Windows Build Instructions

This document describes how to build the Windows (x86) version of RadioBot directly on a Windows machine, without Docker, the `dockur/windows` VM, or the Linux host scripts.

## Requirements

- Windows 10 or Windows 11 (x64)
- Administrator privileges (the setup installs system-wide build tools)
- Internet connection
- At least 64 GB of free disk space and 8 GB of RAM
- `git` installed (recommended). Without `git`, the standalone launcher and setup scripts can fall back to downloading a ZIP archive from public GitHub repositories.

## Supported repository sources

The native build wizard can build from any of these sources:

- `earthisflat123/RadioBot` — the fork with Windows build fixes (default)
- `DriftSolutions/RadioBot` — the upstream repository
- Any other public or private `git` URL

## Quick start

### Option 1: Run the standalone launcher

Download `RadioBot-Windows-Setup.ps1` and run it as Administrator:

```powershell
powershell -ExecutionPolicy Bypass -File .\RadioBot-Windows-Setup.ps1
```

The launcher will ask for a repository, clone it, and then run the in-repo GUI wizard. The source repository then contains the full wizard and can be reused.

### Option 2: Clone the repository manually

```powershell
git clone --depth 1 https://github.com/earthisflat123/RadioBot.git C:\RadioBot
cd C:\RadioBot
```

Then run either the **GUI** wizard:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows-native-wizard.ps1
```

or the **console** wizard:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows-native-console.ps1
```

## Step-by-step wizard flow

1. **Repository** — choose upstream, the recommended fork, a custom URL, or an existing local clone.
2. **Setup** — installs Chocolatey, Visual Studio Build Tools 2022, vcpkg, the Drift Standard Library, libfaac, and libspopc.
3. **Build** — compiles `RadioBot.exe`, `AutoDJ.exe`, `RadioBot_Shell.exe`, `ConfigWizard.exe`, and the other tools.
4. **Package** — builds `RadioBot-setup.exe` using NSIS and the official installer payload.
5. **Finish** — launch any built binary, open the artifacts folder, or close the wizard.

## Using a dependency archive

If you have a previously built `radiobot-windows-deps.7z`, place it in the repository root before starting. The wizard will detect it automatically and skip the long vcpkg build. In the GUI you can also point to an archive in a different location.

The archive can be produced from an existing VM or Docker build by running `windows-oem/package-deps.ps1` inside the build environment.

## Files involved

| File | Purpose |
|------|---------|
| `RadioBot-Windows-Setup.ps1` | Standalone launcher for users who do not have the repo yet. |
| `build-windows-native-wizard.ps1` | WinForms GUI wizard. |
| `build-windows-native-console.ps1` | Console menu-driven wizard. |
| `windows-oem/native-build-core.psm1` | Shared PowerShell module used by the console and GUI. |
| `windows-oem/setup.ps1` | Installs the build environment. `-Native` mode skips Docker/Samba/SSH setup. |
| `windows-oem/build-radiobot.ps1` | Builds the solution. |
| `windows-oem/package-installer.ps1` | Builds `RadioBot-setup.exe`. |

## What is different from the Docker build?

- No `dockur/windows` container and no 64 GB VM disk.
- No Samba share or `Z:` drive; the repo is used in place.
- No SSH key or OpenSSH server is installed.
- The `windows-oem/` folder inside the clone is used instead of a mounted `C:\OEM` directory.

## Troubleshooting

### The wizard asks for Administrator rights

The setup installs Chocolatey and Visual Studio Build Tools into protected locations. You must run the wizard as Administrator.

### `git` is not found

Install [Git for Windows](https://git-scm.com/download/win) or use the standalone launcher with a public GitHub repository, which will download the source as a ZIP archive.

### Visual Studio Build Tools installation is slow

This is normal on a fresh machine. The setup step can take 15–30 minutes. The wizard will show the live log.

### vcpkg build fails

Make sure the `builtin-baseline` in `vcpkg.json` has not been altered and that your network can reach `github.com`. If a `radiobot-windows-deps.7z` archive is available, use it to skip the vcpkg build.

### Packaging fails because the official installer cannot be downloaded

Place the official installer (`official-installer.exe`) in the repository root. The packaging script will use it instead of downloading from the upstream URL.
