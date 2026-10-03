#!/usr/bin/env bash
# Build Acton from this checkout and install the `acton` binary.
#
# For the prebuilt release binary, use the public installer instead:
#   curl -LsSf https://github.com/ton-blockchain/acton/releases/latest/download/acton-installer.sh | sh
set -euo pipefail

# Same default location as the release installer (`install-path` in dist-workspace.toml).
install_dir="${ACTON_INSTALL_DIR:-$HOME/.acton/bin}"
skip_sync=0
skip_ui=0

log() {
    printf 'install: %s\n' "$*"
}

die() {
    printf 'install: error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $0 [options]

Build Acton from source and install the \`acton\` binary.

Options:
  --install-dir <dir>  Where to put the binary (default: \$ACTON_INSTALL_DIR or ~/.acton/bin)
  --skip-sync          Do not run \`cargo xtask sync-artifacts\` (reuse existing objs/)
  --skip-ui            Do not rebuild the bundled UI packages
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir)
            [[ $# -ge 2 ]] || die "--install-dir requires a value"
            install_dir="$2"
            shift 2
            ;;
        --install-dir=*)
            install_dir="${1#*=}"
            shift
            ;;
        --skip-sync)
            skip_sync=1
            shift
            ;;
        --skip-ui)
            skip_ui=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

require() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required: $2"
}

require cargo "install Rust via https://rustup.rs"
require git "install git from your package manager"
if [[ $skip_sync -eq 0 ]]; then
    require gh "install the GitHub CLI (used by \`cargo xtask sync-artifacts\`)"
fi
if [[ $skip_ui -eq 0 ]]; then
    require bun "install Bun via https://bun.sh (or pass --skip-ui)"
fi

case "$(uname -s)" in
    Linux)
        require pkg-config "sudo apt install pkg-config"
        pkg-config --atleast-version=3.0.0 openssl \
            || die "OpenSSL >= 3.0 not found via pkg-config: sudo apt install libssl-dev"
        for lib in libsodium libmicrohttpd; do
            pkg-config --exists "$lib" \
                || log "warning: $lib not found via pkg-config (sudo apt install $lib-dev)"
        done
        ;;
    Darwin)
        if command -v brew >/dev/null 2>&1; then
            for lib in libsodium libmicrohttpd pkg-config; do
                brew list --versions "$lib" >/dev/null 2>&1 \
                    || log "warning: $lib is not installed (brew install $lib)"
            done
        fi
        ;;
    *)
        log "warning: $(uname -s) is not a supported platform; continuing anyway"
        ;;
esac

if [[ $skip_sync -eq 0 ]]; then
    log "syncing TON artifacts"
    cargo xtask sync-artifacts
fi

if [[ $skip_ui -eq 0 ]]; then
    log "building UI packages"
    bun ci
    for pkg in test-ui explorer-core studio-ui; do
        (cd "packages/$pkg" && bun ci && bun run build)
    done
fi

log "building acton (release)"
cargo build --release --locked --package acton

mkdir -p "$install_dir"
install -m 755 target/release/acton "$install_dir/acton"
log "installed $("$install_dir/acton" --version) to $install_dir/acton"

case ":$PATH:" in
    *":$install_dir:"*) ;;
    *)
        log "$install_dir is not on your PATH; add this to your shell profile:"
        # shellcheck disable=SC2016 # print $PATH literally
        printf '    export PATH="%s:$PATH"\n' "$install_dir"
        ;;
esac
