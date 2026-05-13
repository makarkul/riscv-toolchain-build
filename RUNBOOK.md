# RISC-V Toolchain Build & Debian Package Runbook

End-to-end recipe for building the patched RISC-V GNU toolchain, packaging it
as a `.deb` that installs on **Ubuntu 22.04 jammy** and **Ubuntu 24.04 noble**,
and pushing it to the Gemfury repo `sampigesemi/riscv-toolchain`.

## What gets built

- gcc 13.4.0 (releases/gcc-13.4.0)
- binutils 2.40 (commit `e05406c548867d6467d47564f8f9d7cd338532a4`)
- newlib 4.5.0
- gdb 16.3
- spike (incoresemi fork)
- Full multilib per `temp_config.yaml`
- InCore Semi psimd patches applied to gcc and binutils

## How it stays cross-distro compatible

- **Built on Ubuntu 22.04 (jammy, glibc 2.35)** so host binaries never
  reference symbols newer than `GLIBC_2.35` — they load on both jammy and
  noble (glibc 2.39).
- **`libgmp`, `libmpfr`, `libmpc`, `libstdc++`, `libgcc` statically linked**
  into the host cross-gcc/binutils/gdb binaries.
- Verified post-build by `readelf -V` — the build fails if any host binary
  references `GLIBC_> 2.35`.

## Prerequisites

- Linux host with Docker + Docker Compose v2.
- ≥ 40 GB free disk on the Docker storage path (peak build is ~25 GB).
- Network access to: `github.com`, `gcc.gnu.org`, `sourceware.org`,
  `push.fury.io` (last one only for the push step).
- Gemfury push token (kept out of git — pass via `FURY_TOKEN` env var).

## End-to-end

```bash
# 1. Clone the repo (you already have it).
git clone <this-repo> && cd riscv-toolchain-build
git checkout claude/build-riscv-debian-package-QbzuL

# 2. Fetch the toolchain sources (~5-8 GB, several minutes).
git submodule update --init --recursive

# 3. Build, package, and push in one shot.
export FURY_TOKEN='<your-gemfury-push-token>'
./docker-build.sh --jobs "$(nproc)" --push

# Or, run the build and the push separately:
./docker-build.sh --jobs "$(nproc)"          # produces dist/riscv-toolchain_*.deb
FURY_TOKEN='...' ./push-gemfury.sh           # uploads the newest .deb in dist/
```

Outputs:

- `toolchain-output/` — the full install tree (also bind-mounted in the container at `/opt/riscv-toolchain`).
- `dist/riscv-toolchain_13.4.0-1_amd64.deb` — the .deb you'll ship.

## Verify the .deb locally before/after pushing

```bash
# Inspect package metadata
dpkg-deb -I dist/riscv-toolchain_13.4.0-1_amd64.deb

# Confirm payload starts at ./opt/riscv-toolchain/
dpkg-deb -c dist/riscv-toolchain_13.4.0-1_amd64.deb | head

# Smoke-test install on a fresh jammy container
docker run --rm -it -v "$PWD/dist:/d" ubuntu:22.04 bash -c '
  apt-get update &&
  apt-get install -y /d/riscv-toolchain_13.4.0-1_amd64.deb &&
  /opt/riscv-toolchain/bin/riscv64-unknown-elf-gcc --version &&
  echo "int main(){return 0;}" |
    /opt/riscv-toolchain/bin/riscv64-unknown-elf-gcc -x c - -o /tmp/a.out &&
  /opt/riscv-toolchain/bin/riscv64-unknown-elf-objdump -d /tmp/a.out | head
'

# Same on noble
docker run --rm -it -v "$PWD/dist:/d" ubuntu:24.04 bash -c '
  apt-get update && apt-get install -y /d/riscv-toolchain_13.4.0-1_amd64.deb &&
  /opt/riscv-toolchain/bin/riscv64-unknown-elf-gcc --version
'
```

## Installing the toolchain

### From GitLab Package Registry

The `.deb` is hosted on the GitLab Generic Package Registry.

```bash
# Download the .deb (replace <TOKEN> with a GitLab personal access token)
curl --header "PRIVATE-TOKEN: <TOKEN>" \
  -o riscv-toolchain_13.4.0-1_amd64.deb \
  "https://gitlab.vayavyalabs.com:8000/api/v4/projects/1312/packages/generic/riscv-toolchain/13.4.0-1/riscv-toolchain_13.4.0-1_amd64.deb"

# Install (works on both Ubuntu 22.04 jammy and 24.04 noble)
sudo apt install ./riscv-toolchain_13.4.0-1_amd64.deb

# The toolchain is installed to /opt/riscv-toolchain.
# A /etc/profile.d snippet adds it to PATH for new shells, or manually:
export PATH=/opt/riscv-toolchain/bin:$PATH
```

The package is also browsable at:
```
https://gitlab.vayavyalabs.com:8000/sampigesemi/riscv-toolchain-build/-/packages
```

### From Gemfury (legacy)

```bash
# As root on jammy or noble:
echo 'deb [trusted=yes] https://apt.fury.io/sampigesemi/ /' \
    > /etc/apt/sources.list.d/sampigesemi.list
apt-get update
apt-get install -y riscv-toolchain
export PATH=/opt/riscv-toolchain/bin:$PATH
```

### Uploading a new version to GitLab

```bash
export GITLAB_TOKEN='<your-gitlab-personal-access-token>'

# Upload the .deb
curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --upload-file dist/riscv-toolchain_<VERSION>_amd64.deb \
  "https://gitlab.vayavyalabs.com:8000/api/v4/projects/1312/packages/generic/riscv-toolchain/<VERSION>/riscv-toolchain_<VERSION>_amd64.deb"
```

## Troubleshooting

- **"glibc symbol > 2.35" error from build-toolchain.sh**: the build container
  somehow isn't jammy. Confirm `FROM ubuntu:22.04` in `Dockerfile` and rebuild
  the image with `./docker-build.sh --rebuild`.
- **Patch fails to apply**: confirm submodules are at the pinned refs:
  `git submodule status` should show `gcc` at the gcc-13.4.0 tag commit and
  `binutils` at `e05406c5...`. If they drifted, `git submodule update
  --recursive --force` fixes it.
- **`make spike` fails**: the toolchain is still usable without spike — the
  script downgrades to a warning. Spike is also available from upstream apt.
- **Gemfury HTTP 409 on push**: the version already exists; bump
  `--version 13.4.0-2` and rebuild.
- **Disk pressure during build**: prune docker first: `docker system prune -af`.
  The build workspace lives on the `build-workspace` named volume — locate it
  with `docker volume inspect riscv-toolchain-build_build-workspace`.
