#!/usr/bin/env bash
set -euo pipefail

PX4_DIR="${PX4_DIR:-/root/PX4-Autopilot}"

if [[ ! -f "${PX4_DIR}/Tools/setup/ubuntu.sh" ]]; then
  echo "PX4 setup script not found at ${PX4_DIR}/Tools/setup/ubuntu.sh" >&2
  echo "Run setup_px4_repo first, or initialize the PX4-Autopilot submodule on the host." >&2
  exit 1
fi

cd "${PX4_DIR}"
export PATH="/root/.local/bin:${PATH}"

cleanup_tmpdir=""
cleanup() {
  if [[ -n "${cleanup_tmpdir}" && -d "${cleanup_tmpdir}" ]]; then
    rm -rf "${cleanup_tmpdir}"
  fi
}
trap cleanup EXIT

arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
if [[ "${arch}" == "arm64" || "${arch}" == "aarch64" ]]; then
  cleanup_tmpdir="$(mktemp -d)"
  cat >"${cleanup_tmpdir}/apt-get" <<'EOF'
#!/usr/bin/env bash
set -e
filtered=()
for arg in "$@"; do
  case "${arg}" in
    gcc-multilib|g++-multilib)
      echo "Skipping ${arg} on arm64" >&2
      ;;
    *)
      filtered+=("${arg}")
      ;;
  esac
done
exec /usr/bin/apt-get "${filtered[@]}"
EOF
  chmod +x "${cleanup_tmpdir}/apt-get"
  ln -s apt-get "${cleanup_tmpdir}/apt"
  export PATH="${cleanup_tmpdir}:${PATH}"
fi

DEBIAN_FRONTEND=noninteractive bash ./Tools/setup/ubuntu.sh --no-nuttx
echo "PX4 Ubuntu dependencies installed"
