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

- For a native Windows build directly on a Windows machine, see [WINDOWS_BUILD.md](WINDOWS_BUILD.md).
- For the Docker/VM Windows build (headless `dockur/windows` VM setup, vcpkg dependencies, Visual Studio Build Tools, and packaging), see [WINDOWS_DOCKER_BUILD.md](WINDOWS_DOCKER_BUILD.md).

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

### Debian/Ubuntu package

A self-contained `.deb` package can be built with Docker using the multi-distro builder in the repo. From the repo root:

```bash
./build-deb.sh            # interactive menu to pick the target
./build-deb.sh noble      # or name the target directly
./build-deb.sh all        # build all four targets
```

Supported targets: `bookworm` (Debian 12), `trixie` (Debian 13), `jammy` (Ubuntu 22.04) and `noble` (Ubuntu 24.04). Each produces `radiobot_5.0.0-1~<distro>_amd64.deb` (or whatever `VERSION` is set to) in the repository root. It uses `Dockerfile.deb` and handles the build entirely inside the container:

- Enables `contrib`/`non-free` in Debian APT so `libfaac-dev` can be installed (Ubuntu images already ship `multiverse`).
- Installs `libwxgtk3.2-dev` where available, falling back to `libwxgtk3.0-gtk3-dev` (Ubuntu 22.04).
- Installs `libpcre3-dev` where available, otherwise builds a static PCRE1 from upstream source (Debian Trixie no longer ships PCRE1).
- Uses `default-libmysqlclient-dev` so MySQL client headers/pkg-config are available.
- Compiles RadioBot and all plugins against the target distro's libraries.
- Computes `shlibs:Depends` with `dpkg-shlibdeps` and writes the final `DEBIAN/control`.

Install the package on the matching distro with:

```bash
sudo apt install ./radiobot_5.0.0-1~noble_amd64.deb
```

This resolves all runtime dependencies automatically (including `whiptail`, used by the setup wizard). On a fresh install, the package's `postinst` offers the whiptail setup wizard when a terminal is available — it can create a new config or import an existing `ircbot.conf`. If you installed with `sudo`, the config is written to your `~/.radiobot`; otherwise it goes to `/var/lib/radiobot` and is copied into your data directory on first run.

If you prefer `dpkg`, install the package and then fix dependencies:

```bash
sudo dpkg -i radiobot_5.0.0-1~noble_amd64.deb
sudo apt-get -f install
```

Note: with `dpkg -i`, `postinst` runs before dependencies like `whiptail` are installed, so the install-time wizard is skipped — it runs on the first `radiobot` launch instead (or re-run it any time with `radiobot-setup`).

After installation:

```bash
# Start the bot as your normal user. It stores data in $HOME/.radiobot:
radiobot

# Use a different data directory if you prefer:
RADIOBOT_DATA=/srv/radiobot radiobot
```

If no `ircbot.conf` exists yet, `radiobot` launches the setup wizard when a terminal is available.

The `radiobot` wrapper in `/usr/bin/radiobot` creates a data directory (default `~/.radiobot`, override with `RADIOBOT_DATA`), symlinks `ircbot.text` and `plugins` from `/usr/lib/radiobot`, and then launches the bot from there. This keeps runtime state in a user-writable location while the binaries stay under `/usr/lib/radiobot`.

If you want to run it as a system service from `/var/lib/radiobot`, create a dedicated `radiobot` user and run the bot under that account with `RADIOBOT_DATA=/var/lib/radiobot`; do not run the bot as root or with `sudo`.

The package installs:

- `/usr/lib/radiobot/radiobot` — main binary
- `/usr/lib/radiobot/plugins/*.so` — plugin modules
- `/usr/lib/radiobot/ircbot.text` — static data file
- `/usr/lib/radiobot/setup-tui.sh` — whiptail first-time setup wizard
- `/usr/bin/radiobot` — wrapper that runs from the user's data directory
- `/usr/bin/radiobot-setup` — re-run the setup wizard (or import an existing `ircbot.conf`) any time
- `/var/lib/radiobot` — runtime data directory, created by the `postinst` script


