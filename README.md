# RadioBot
Since I no longer have a lot of time to put into RadioBot I thought I would go ahead and release the source code so others can check it out and customize it to their needs.
I'll be the first to admit it's kind of a mess in places, the bot was originally in C before moving to C++ and is basically what I learned C/C++ on so it's not perfect.

## Running with Docker
The easiest way to get RadioBot running is via Docker Compose — no manual dependency installation required, everything is built inside the container. From the cloned repo:

```bash
docker compose up -d --build
```

On first run (or whenever `./data/ircbot.conf` is missing), an interactive setup wizard walks you through configuring your bot's nickname, IRC server, streaming server, and plugins:

```bash
docker compose run --rm radiobot
```

![RadioBot setup wizard](demo-whiptail.gif)

The wizard writes `./data/ircbot.conf`, which you can edit directly afterward — restart with `docker compose restart` to pick up changes. Once configured, start the bot normally:

```bash
docker compose up -d
```

By default the container runs as a non-root user (UID/GID 1000). To make files written to `./data` (config, database, logs) match your own host user instead, export `UID`/`GID` before running compose — bash doesn't export `GID` automatically, so:

```bash
export UID GID=$(id -g)
docker compose up -d
```

## Build options

### Windows
For the Windows build — including the headless `dockur/windows` VM setup, vcpkg dependencies, Visual Studio Build Tools, and packaging — see [WINDOWS_BUILD.md](WINDOWS_BUILD.md).

### Linux/Unix
1. Install dependencies, cmake, git, protoc (profobuf compiler), and core GNU C/C++ compiler/tools (build-essential on Debian systems). You can find most deps by looking in your distro at https://wiki.shoutirc.com/index.php/Installation - you will need the corresponding -dev/-devel packages of course.

**On Ubuntu 24.04 or 22.10:**
- ```sudo apt install libssl-dev libsqlite3-dev libwxgtk3.2-dev libtag1-dev libmp3lame-dev libogg-dev libvorbis-dev libsndfile1-dev libavcodec-extra libavformat-dev libavcodec-dev libcurl4-openssl-dev libmpg123-dev libresample1-dev libfaad-dev libncurses5-dev libphysfs-dev libpcre3-dev libprotobuf-dev libmysqlclient-dev libfaac-dev libopus-dev libloudmouth1-dev libdbus-glib-1-dev libmuparser-dev libsoxr-dev build-essential cmake libz-dev git protobuf-compiler```

**On Ubuntu 22.04:**
- ```sudo apt install libssl-dev libsqlite3-dev libwxgtk3.0-gtk3-dev libtag1-dev libmp3lame-dev libogg-dev libvorbis-dev libsndfile1-dev libavcodec-extra libavformat-dev libavcodec-dev libcurl4-openssl-dev libmpg123-dev libresample1-dev libncurses5-dev libphysfs-dev libpcre3-dev libprotobuf-dev libmysqlclient-dev libfaac-dev libopus-dev libloudmouth1-dev libdbus-glib-1-dev libmuparser-dev libsoxr-dev build-essential cmake libz-dev git protobuf-compiler```

**On Debian 12: (note you need non-free enabled in APT for libfaac)**
- ```sudo apt install libssl-dev libsqlite3-dev libwxgtk3.2-dev libtag1-dev libmp3lame-dev libogg-dev libvorbis-dev libsndfile1-dev libavcodec-extra libavformat-dev libavcodec-dev libcurl4-openssl-dev libmpg123-dev libresample1-dev libncurses5-dev libphysfs-dev libpcre3-dev libprotobuf-dev libopus-dev libloudmouth1-dev libdbus-glib-1-dev libmuparser-dev libsoxr-dev build-essential cmake libz-dev git protobuf-compiler default-libmysqlclient-dev libfaac-dev autoconf libtool-bin liblua5.4-dev```
  
**On Debian 11:**
- ```sudo apt install libssl-dev libsqlite3-dev libwxgtk3.0-gtk3-dev libtag1-dev libmp3lame-dev libogg-dev libvorbis-dev libsndfile1-dev libavcodec-extra libavformat-dev libavcodec-dev libcurl4-openssl-dev libmpg123-dev libresample1-dev libncurses5-dev libphysfs-dev libpcre3-dev libprotobuf-dev libopus-dev libloudmouth1-dev libdbus-glib-1-dev libmuparser-dev libsoxr-dev build-essential cmake libz-dev git protobuf-compiler default-libmysqlclient-dev libfaac-dev autoconf libtool-bin liblua5.4-dev```

_(Please let me know if I missed any.)_  
3. cd to the cloned repo, create a 'build' subfolder and cd to it.  
4. Run: cmake ..  
5. make -j**X** (where **X** is however many CPU cores you have)

### Debian package

A self-contained Debian package can be built with Docker using the Trixie-based builder in the repo. From the repo root:

```bash
./build-deb.sh
```

This produces `radiobot_5.0.0_amd64.deb` (or whatever `VERSION` is set to) in the repository root. It uses `Dockerfile.debian-trixie` and handles the build entirely inside the container:

- Enables `main contrib non-free non-free-firmware` in Trixie APT so `libfaac-dev` can be installed.
- Builds a static PCRE1 from upstream source, because Debian Trixie no longer ships `libpcre3-dev` (PCRE1).
- Uses `default-libmysqlclient-dev` so MySQL client headers/pkg-config are available.
- Compiles RadioBot and all plugins against the Trixie libraries.
- Computes `shlibs:Depends` with `dpkg-shlibdeps` and writes the final `DEBIAN/control`.

Install the package on Debian Trixie with:

```bash
sudo apt install ./radiobot_5.0.0_amd64.deb
```

This resolves all runtime dependencies automatically. If you prefer `dpkg`, install the package and then fix dependencies:

```bash
sudo dpkg -i radiobot_5.0.0_amd64.deb
sudo apt-get -f install
```

The package has been tested in a clean `debian:trixie` container. All `Depends:` packages resolve from the Trixie repositories with `contrib`/`non-free-firmware` enabled (only needed at build time for `libfaac-dev`; runtime dependencies are in `main`).

After installation:

```bash
# Start the bot as your normal user. It stores data in $HOME/.radiobot:
radiobot

# Use a different data directory if you prefer:
RADIOBOT_DATA=/srv/radiobot radiobot
```

The first time it runs, it will complain that `ircbot.conf` is missing. Copy or generate a config file into your data directory (`~/.radiobot/ircbot.conf`) and then run `radiobot` again.

The `radiobot` wrapper in `/usr/bin/radiobot` creates a data directory (default `~/.radiobot`, override with `RADIOBOT_DATA`), symlinks `ircbot.text` and `plugins` from `/usr/lib/radiobot`, and then launches the bot from there. This keeps runtime state in a user-writable location while the binaries stay under `/usr/lib/radiobot`.

If you want to run it as a system service from `/var/lib/radiobot`, create a dedicated `radiobot` user and run the bot under that account with `RADIOBOT_DATA=/var/lib/radiobot`; do not run the bot as root or with `sudo`.

The package installs:

- `/usr/lib/radiobot/radiobot` — main binary
- `/usr/lib/radiobot/plugins/*.so` — plugin modules
- `/usr/lib/radiobot/ircbot.text` — static data file
- `/usr/bin/radiobot` — wrapper that runs from `/var/lib/radiobot`
- `/var/lib/radiobot` — runtime data directory, created by the `postinst` script


