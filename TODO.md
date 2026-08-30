# RadioBot Windows Installer / End-to-End TODO

## Current status

- Client5-style `ConfigWizard.exe` implemented and built.
- `package-installer.ps1` 7-Zip extraction path fixed; official payload is now extracted and overlaid correctly.
- Stale/duplicate files from the official payload are pruned after overlay.
- `RadioBot.nsi` runs `ConfigWizard.exe -o "$INSTDIR\ircbot.conf"` instead of the broken PowerShell wizard.
- Old `config-wizard.ps1` and `run-wizard.vbs` removed.
- New installer `RadioBot-setup-cw.exe` built (~39 MB) and a manual GUI sanity check in the VM showed the dialog opens and writes `ircbot.conf`.

## Pending work

### 1. Commit current changes
- Stage and commit the `ConfigWizard/` project, `windows-oem/package-installer.ps1`, `windows-oem/build-radiobot.ps1`, `windows-oem/clean-build.ps1`, `windows-oem/RadioBot.nsi`, and the deleted `config-wizard.ps1` / `run-wizard.vbs`.

### 2. Free disk space on the Windows VM
The VM is down to ~1.1 GB free of a 64 GB disk. Quick analysis of `C:`:

| Path | Approx. size | Notes |
|------|--------------|-------|
| `C:\vcpkg\buildtrees` | 20.0 GB | vcpkg build trees; can be removed after packages are installed |
| `C:\vcpkg\downloads` | 5.7 GB | Cached source archives |
| `C:\vcpkg\packages` | 3.3 GB | Staged packages (redundant with `installed`) |
| `C:\Windows` | 15.2 GB | OS; can run `Dism ... /StartComponentCleanup` |
| `C:\Program Files (x86)` | 12.0 GB | Build tools, NSIS, Python, etc. |
| `C:\RadioBot\payload-test*` | ~0.5 GB total | Temp extraction test directories left over from debugging |

Options:
- **Clean in place**: remove `C:\vcpkg\buildtrees`, `C:\vcpkg\packages`, `C:\vcpkg\downloads`, temp `payload-test*` / `official-test*` dirs, and run Windows component cleanup.
- **Wipe and recreate**: use `docker-compose.windows.yml` to rebuild from the image (faster if the image is cached, but loses the current vcpkg/build state).

First recommend the in-place cleanup; it should free ~25-30 GB quickly.

### 3. Set up an end-to-end test environment
Need to verify the installed bot with real MP3s and an IRC server.

- **MP3 test library**: generate or stage a few MP3 files with varied metadata (including titles with `'` and other special characters) and a `MusicScanner` / playlist path.
- **IRC server**: add an IRCd service to the Docker setup so the Windows VM can connect. Candidate images:
  - `inspircd/inspircd` (simple, no services)
  - `ergochat/ergo` (modern, IRCv3, easy config)
- Add it to `docker-compose.windows.yml` (or a new `docker-compose.test.yml`) and expose a port that the VM can reach via `host.lan` or a dedicated container hostname.
- Configure a test `ircbot.conf` to point at the IRCd and an Icecast/Shoutcast test stream, then run `RadioBot.exe` and exercise request/rating commands.

### 4. Fix `!rate` bug with single quotes in song names
Songs with a single quote (`'`) in the title break the `!rate` command. Likely causes:
- Unescaped quote in an SQL string (`v5/src/ircbot.cpp`, rating plugin, or wherever `!rate` is handled).
- Malformed `sprintf` / `ib_printf` format string.
- Missing quoting in the request/rating parsing.

Need to grep the rating/request code, reproduce with a test MP3, and patch.

### 5. Full installer smoke test
- Run the final installer on a clean VM snapshot.
- Use the wizard to create `ircbot.conf`.
- Start the bot against the Docker IRCd.
- Play/request/rate a song with a `'` in the title to confirm fix #4.

### 6. Data retroactive cleanup for the `!rate` bug
- Before the `!rate` single-quote fix, any song title containing `'` may have been stored incorrectly/duplicated in the SQLite `ircbot.db` (or any backend). In a production deployment it would be useful to scan the `Votes`/`Ratings` tables and repair/re-merge any broken rows created by the bug.
- Investigate whether this is possible/needed. If yes, write a standalone cleanup script (Python or SQL) that can be run against an existing `ircbot.db` (or MariaDB tables if/when ratings are moved there).

### 7. Test `!rate` bug fix in the Linux/Docker run style
- Verify the single-quote `!rate` fix works when RadioBot is built and run inside a Linux container (the current manual tests were done on Windows). This also checks that the Docker build path still produces a working bot.

### 8. Fix volume mapping for persistent bot data
- RadioBot stores runtime data (e.g. `ircbot.db`, config rewrites, downloaded files, logs) inside the container but those paths are not mapped to host volumes. On container recreation this data is lost, which is a serious bug.
- Identify all paths the bot writes to, add them as named or bind volumes in the Docker Compose/service files, and document the persistence model.

### 9. Automatic `.deb` package builds
- Create Docker-based build/packaging containers for:
  - Ubuntu 22.04
  - Ubuntu 24.04
  - Debian Bookworm
  - Debian Trixie
- Each container should build RadioBot and produce `.deb` package(s).
- Store the resulting packages on the host in an `artifacts/` folder (or another sensible volume location) so they survive container restarts.

### 10. Validate Client3 and Client5 builds
- After all the vcpkg/wxWidgets project changes, make sure the `Client3` and `Client5` solutions still build and run cleanly (no missing resources, no stale icon/cursor references, correct vcpkg library links).
- Run the built `Client3.exe` and `Client5.exe` binaries for a quick smoke test.

### 11. Windows x64 (Win64) build and packaging
- The current Windows build targets 32-bit (`x86` / `Win32`). Add or verify a proper `x64` configuration for the main bot, Client3, Client5, and plugins.
- Produce a 64-bit Windows installer/package alongside the 32-bit one, stored in `artifacts/` or the Windows VM output.
