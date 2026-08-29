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

## Compiling on Windows
In the IRCBot folder, load IRCBot.sln. A Windows build is going to be harder just because there are so many dependencies if you want to build everything. I have (and the solution is set up for) a folder c:\deps with a lib and include folder and I keep all my deps in it like on a Linux directory structure. The core things you will need: 
 
**Drift Standard Libraries:** https://github.com/DriftSolutions/DSL  
**OpenSSL:** I recommend https://slproweb.com/products/Win32OpenSSL.html

## Compiling on Linux/Unix
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

## Building a Debian Trixie .deb package

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

## Headless Windows build on Linux (dockur/windows)

You can build the Windows version on a Linux host by running a Windows VM inside a Docker container, using [dockur/windows](https://github.com/dockur/windows). This is completely headless: once the VM is running, all interaction is via SSH and file shares.

### Requirements

- Linux host with `/dev/kvm` and `/dev/net/tun` available
- Docker Compose
- At least 64 GB free disk space and 8 GB RAM

### Quick start

```bash
# Generate an SSH key pair and stage the public key for the Windows VM
./prepare-windows-build.sh

# Start the Windows VM. This downloads a Windows Server 2022 evaluation image
# and installs it automatically; it can take 30-60 minutes.
docker compose -f docker-compose.windows.yml up -d

# Monitor progress at http://localhost:8006 (web VNC) or RDP to localhost:3389
# The setup script (windows-oem/setup.ps1) installs Visual Studio Build Tools,
# vcpkg, dependencies in C:\deps, and an OpenSSH server.

# Once the VM is ready, build:
./build-windows.sh

# Built .exe and .dll files are copied to the shared folder and appear in
# ./artifacts/ on the host.
```

### How it works

- `docker-compose.windows.yml` runs `dockurr/windows` with Windows Server 2022.
- `windows-oem/install.bat` is executed automatically after Windows setup; it
  calls `setup.ps1`, which installs Build Tools, vcpkg packages, OpenSSL, and
  stages everything under `C:\deps`.
- The RadioBot source is copied from the shared drive (`Z:`) to `C:\RadioBot`.
- `build-windows.sh` SSHs into the VM (localhost:2222) and runs
  `build-windows.ps1`, which invokes `MSBuild IRCBot.sln` and copies outputs
  back to `Z:\artifacts`, which appears as `./artifacts/` on the host.
