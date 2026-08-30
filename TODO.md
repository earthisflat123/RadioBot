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
