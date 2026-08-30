# Windows Build Instructions

This document describes how to build the Windows (x86) version of RadioBot on a Linux host using a headless Windows Server 2022 VM running in Docker.

## Overview

RadioBot has two build systems:

- **Linux/Unix:** CMake (`CMakeLists.txt`)
- **Windows:** Visual Studio solution and `.vcxproj` files (`IRCBot\IRCBot.sln`)

The Windows project files reference many third-party libraries under `C:\deps` and use a custom static library called `ibdsl.lib` (the Drift Standard Library). Instead of cross-compiling with MinGW, the build runs inside a Windows VM that has Visual Studio Build Tools, vcpkg, and MSBuild.

## Files involved

| File | Purpose |
|------|---------|
| `docker-compose.windows.yml` | Launches the `dockur/windows` container. |
| `windows-oem/install.bat` | First-logon hook; runs `windows-oem/setup.ps1`. |
| `windows-oem/setup.ps1` | Provisions the VM: Build Tools, vcpkg, DSL, dependencies, OpenSSH, and saves a pristine copy of the solution. |
| `windows-oem/build-radiobot.ps1` | Full build orchestration (prunes solution, generates protobuf, creates lib aliases, builds with MSBuild, copies artifacts). |
| `windows-oem/build-dsl.ps1` | Clones and builds the Drift Standard Library (`ibdsl.lib`). |
| `windows-oem/CMakeLists.dsl.txt` | Custom CMakeLists used by `build-dsl.ps1`. |
| `windows-oem/Directory.Build.props` | Global MSBuild properties that add vcpkg include/lib paths, C++17, and protobuf/abseil DLL settings. |
| `windows-oem/fix-deps.ps1` | Copies vcpkg libs to `C:\deps` and creates the legacy lib name aliases RadioBot expects. |
| `windows-oem/sln-prune.ps1` | Removes selected projects from `IRCBot.sln` before building. |
| `build-windows.sh` | Host script that SSHs into the VM and runs `C:\RadioBot\build-windows.ps1`. |
| `build-windows.ps1` | Wrapper inside the VM that invokes `C:\OEM\build-radiobot.ps1`. |
| `prepare-windows-build.sh` | Generates an SSH key pair and stages the public key in `windows-oem/`. |
| `.gitignore` | Ignores `windows-storage/`, `artifacts/`, and `windows-oem/id_rsa*`. |

## Requirements

- Linux host with KVM (`/dev/kvm`) and TUN (`/dev/net/tun`) available.
- Docker Compose.
- At least 64 GB of free disk space and 8 GB of RAM.
- A working internet connection for the VM.

## Build steps

### 1. Generate SSH keys

```bash
./prepare-windows-build.sh
```

This creates `~/.ssh/radiobot_windows_builder` and copies the public key to `windows-oem/id_rsa.pub`.

### 2. Start the Windows VM

```bash
docker compose -f docker-compose.windows.yml up -d
```

`dockur/windows` downloads a Windows Server 2022 evaluation ISO, builds a 64 GB raw disk image, and begins an unattended install. The `windows-oem/` folder is mounted inside the VM as `C:\OEM` and `install.bat` runs automatically after the first logon.

You can monitor the install with:

- Web VNC: `http://localhost:8006`
- RDP: `localhost:3389`
- Logs: `docker logs -f radiobot-windows-build`

The setup script (`windows-oem/setup.ps1`) installs:

- Chocolatey, Git, CMake, Python
- Visual Studio Build Tools 2022 (v143 toolset)
- vcpkg with the packages required by RadioBot
- The Drift Standard Library (DSL) as `ibdsl.lib`
- A pristine copy of `IRCBot\IRCBot.sln` saved as `C:\OEM\IRCBot.sln.orig`
- OpenSSH server

This can take 30–60 minutes on the first run.

### 3. Build RadioBot

Once setup is complete:

```bash
./build-windows.sh
```

This connects as `builder` on `localhost:2222` and runs `C:\OEM\build-radiobot.ps1`, which:

1. Restores `IRCBot.sln` from the pristine copy.
2. Removes the projects that cannot build in this vcpkg environment (wxWidgets GUIs, optional plugins, the old shell, etc.).
3. Generates `autodj.pb.cc` and `remote_protobuf.pb.cc` with `protoc`.
4. Creates lib name aliases in `C:\deps\lib`.
5. Builds `add_checksum` first to avoid file-in-use copy failures.
6. Builds the full solution with MSBuild in Release/Win32.
7. Copies runtime DLLs into `C:\RadioBot\v5\Output`.
8. Copies the full output tree to `Z:\artifacts` (mounted as `./artifacts/` on the host).

Built artifacts appear in `./artifacts/` on the host. The main executables are:

- `RadioBot.exe`
- `AutoDJ.exe` (the standalone AutoDJ binary)
- `editusers.exe`
- `MusicScanner2.exe`
- `mp3sync.exe`
- `langdump.exe`
- `ibctl.exe`

Plugins are in `./artifacts/plugins/` and `./artifacts/Plugins/AutoDJ/`.

## Restoring dependencies on a fresh Windows VM

If you need to recreate the Windows build VM from scratch, installing vcpkg packages and building the source dependencies (`libfaac`, `libspopc`, DSL, etc.) is the slow part. A pre-packaged dependency archive is stored in the repo root:

- `radiobot-windows-deps.7z` (≈ 625 MB)

It contains everything vcpkg and the build scripts expect at their normal paths:

- `deps/` → `C:\deps`
- `vcpkg/` → `C:\vcpkg` (vcpkg tool + `installed/`, but without `buildtrees/`, `downloads/`, or `packages/`)
- `libspopc-src/` → `C:\libspopc-src`

To restore the dependencies:

1. Make sure the new VM has the `windows-oem/` folder mounted as `C:\OEM` and the RadioBot source available at `C:\RadioBot` (or `Z:\`).
2. Copy the archive into the VM (for example to `C:\Temp` or `Z:\`).
3. In the VM, extract it to the root of `C:\`:

   ```powershell
   7z x radiobot-windows-deps.7z -oC:\
   ```

4. Verify the top-level directories were created:

   ```powershell
   Test-Path C:\deps\lib\libfaac.lib
   Test-Path C:\vcpkg\installed\x86-windows\lib
   Test-Path C:\libspopc-src
   ```

Archive use is opt-in. The default `windows-oem/setup.ps1` behaviour is still to install/build everything from scratch. To enable the archive, either:

- Create an empty file named `USE_RADIOSBOT_DEPS_ARCHIVE` in the repo root (which is `Z:\` in the VM), or
- Set the environment variable `USE_RADIOSBOT_DEPS_ARCHIVE=1` before the VM starts.

After extraction, `./build-windows.sh` can run without waiting for vcpkg or libfaac/libspopc to build. The source dependencies (`driftmeshcore` for `MeshCore`) are still cloned from the network on first build unless they are also present in `C:\RadioBot\v5\Plugins\MeshCore\driftmeshcore`.

## Optional projects not built

The following projects are now built by default:

- `TTS_Services` – fixed by adding `_HAS_STD_BYTE=0` to `Directory.Build.props`.
- `Mumble` – fixed by generating `Mumble.pb.cc`/`Mumble.pb.h` with `protoc` and adding `%(AdditionalIncludeDirectories)` to `Mumble.vcxproj`.
- `adj_enc_opus` – fixed by preserving `%(AdditionalLibraryDirectories)` in `adj_enc_opus.vcxproj`.
- `Client3`, `Client5`, `MusicScanner` – fixed by installing `wxwidgets` from vcpkg, generating `client5_savefile.pb.cc/h`, and correcting include/library paths. `Client3` and `MusicScanner` now link `vcpkg`'s wx 3.3 libraries; `Client5` only needed its protobuf file generated.
- `MeshCore` – fixed by installing `mosquitto` from vcpkg, cloning the `driftmeshcore` dependency, and patching `MeshCore.vcxproj` and `meshcoremqttclient.h` to remove stale `ENABLE_LIBEVENT` / `LIBMOSQUITTO_STATIC` defines.
- `Twitter` – fixed by adding the bundled `libjson` source to `Twitter.vcxproj`, patching `JSONOptions.h` to disable deprecated `json_validate` declarations, and removing the stale `libjson.lib` `#pragma` from `twittimeline.cpp`.
- `SMS` – fixed by building `libspopc` 0.15 from source as an OpenSSL-enabled DLL and copying it to `C:\deps`.
- `adj_enc_aac` – fixed by building `libfaac` 1.50 from source and copying it to `C:\deps`.
- `adj_decenc_ffmpeg` – fixed by installing `ffmpeg:x86-windows` from vcpkg and patching `ffmpeg_encoder.cpp` for FFmpeg 9.x API changes.
- `RadioBot_Shell` – fixed by adding a small `Titus_Buffer` wrapper around `DSL_BUFFER` in `shell.h`.

The following projects are still pruned from the solution because their dependencies are missing or the project itself is incomplete:

- `adj_enc_aacplus` – intentionally skipped. It requires `libaacplus`, which wraps the 3GPP reference AAC+ encoder and has restrictive licensing (the 3GPP source is not freely redistributable). The official Windows installer also does not ship `adj_enc_aacplus.dll`, so this matches the upstream release. Use `adj_enc_aac` (FAAC) or `adj_enc_ffmpeg` for AAC/HE-AAC encoding instead.
- `ibViralSound` – no `.vcxproj` file is present.

## Troubleshooting

### `IRCBot.sln.orig` not found

The setup script saves this file. If you start a build before setup has finished, or if the file was deleted, run `windows-oem/setup.ps1` again inside the VM.

### `Could not map Z:`

The build script tries to map `\\host.lan\Data` to `Z:`. If the host share is unavailable, it falls back to `C:\RadioBot\artifacts` inside the VM. The build still succeeds; you can copy the artifacts manually if needed.

### vcpkg package install fails

Some packages may fail due to network issues. Re-run `windows-oem/setup.ps1` or restart the VM. The setup script uses retries for downloads.

### Build still fails

Check `C:\OEM\build-radio.log` inside the VM. The log is appended by `build-radiobot.ps1` and includes the full MSBuild output.
