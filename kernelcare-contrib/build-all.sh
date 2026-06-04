#!/bin/bash
# Build shim_certificate_kernelcare for x86_64 and aarch64 in almalinux:9
# containers (aarch64 runs under qemu-user-static) and save each .efi + .log
# under kernelcare-build-<date>/.  Needs docker + network access.
#
# Run:  bash kernelcare-contrib/build-all.sh

set -euo pipefail

IMAGE="almalinux:9"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO_ROOT/kernelcare-build-$(date +%Y-%m-%d)"

# provisioning + build, run inside each container
CONTAINER_SCRIPT='
set -euxo pipefail
dnf -y install make gcc binutils git efivar python3 python3-pip python-unversioned-command
pip3 install --quiet pefile
git config --global --add safe.directory "*"
cd /work/kernelcare-certwrapper && bash kernelcare-contrib/build.sh
'

# register foreign-arch emulation once (idempotent)
[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || \
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes >/dev/null

mkdir -p "$OUT"
for entry in x86_64:linux/amd64 aarch64:linux/arm64; do
    arch="${entry%%:*}" platform="${entry##*:}" c="cw-${entry%%:*}"
    echo ">>> building $arch ($platform)"
    docker rm -f "$c" >/dev/null 2>&1 || true
    docker run -d --name "$c" --platform "$platform" "$IMAGE" sleep infinity >/dev/null
    docker exec "$c" mkdir -p /work
    docker cp "$REPO_ROOT" "$c:/work/kernelcare-certwrapper"
    docker exec "$c" bash -c "$CONTAINER_SCRIPT"
    docker cp "$c:/work/kernelcare-certwrapper/kernelcare-build/." "$OUT/"
    docker rm -f "$c" >/dev/null
done

echo ">>> results in $OUT"
ls -l "$OUT"
