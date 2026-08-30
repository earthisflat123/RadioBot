# Test data for RadioBot end-to-end testing

These tracks are from the [Free Music Archive](https://freemusicarchive.org/) and are used for automated / manual end-to-end testing only.

## Tracks

- `Soft_and_Furious_-_01_-_Youre_Magic.mp3` — title contains a single quote (`'`), licensed CC0 1.0 Universal.
- `Soft_and_Furious_-_02_-_Game_On.mp3` — title without a single quote, licensed CC0 1.0 Universal.

Both tracks are from the album *Bae* by [Soft and Furious](https://freemusicarchive.org/music/Soft_and_Furious/).

The MP3 files are **not** stored in this repository. To download them, run:

```bash
# Linux / macOS
cd test-data
./download-songs.sh
```

or on Windows:

```powershell
cd test-data
.\download-songs.ps1
```

## Usage

The files are intended to be played by a test RadioBot instance running the AutoDJ or SimpleDJ plugin. The `docker-compose.test.yml` in the repo root provides a local IRCd (InspIRCd), MariaDB, and Icecast server for this purpose.
