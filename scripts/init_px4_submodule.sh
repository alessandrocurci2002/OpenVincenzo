#!/usr/bin/env bash
# Inizializza il submodule px4-ws/PX4-Autopilot (fork PX4, repo privata) come
# checkout shallow + parziale + sparse: dell'intera repo servono solo msg/, srv/
# e Tools/copy_to_ros_ws.sh (usati da entrypoint.sh per generare px4_msgs).
# Working tree ~1.4 MB invece di ~400 MB, .git ridotto al minimo.
#
# Va lanciato sull'HOST (dove git ha le credenziali per la repo privata), non nel
# container. E' idempotente: rilanciato riapplica i pattern sparse e riallinea il
# submodule al commit fissato dal superproject (es. dopo un `git pull` che
# aggiorna il puntatore). Richiede git >= 2.25.
#
# In .gitmodules il submodule ha `update = none`: `git submodule update --init`
# lo salta di proposito, perche' scaricherebbe tutto il working tree.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SUB=px4-ws/PX4-Autopilot
# --no-cone: pattern in stile .gitignore, consente di includere un singolo file
PATTERNS=(/msg/ /srv/ /Tools/copy_to_ros_ws.sh)

URL=$(git config -f .gitmodules --get "submodule.$SUB.url")
BRANCH=$(git config -f .gitmodules --get "submodule.$SUB.branch")
SHA=$(git ls-files -s -- "$SUB" | awk '{print $2}')

if [ -z "$SHA" ]; then
    echo "!!! $SUB non e' registrato come submodule in questo repo" >&2
    exit 1
fi

if [ ! -e "$SUB/.git" ]; then
    echo "+++ Clone $URL ($BRANCH), shallow + partial + sparse"
    git submodule init -- "$SUB"
    git clone --sparse --depth 1 --filter=blob:none --branch "$BRANCH" "$URL" "$SUB"
    # sposta .git in .git/modules, come per gli altri submodule
    git submodule absorbgitdirs -- "$SUB"
fi

git -C "$SUB" sparse-checkout set --no-cone "${PATTERNS[@]}"

if [ "$(git -C "$SUB" rev-parse HEAD)" != "$SHA" ]; then
    echo "+++ Allineo $SUB al commit fissato $SHA"
    git -C "$SUB" fetch --depth 1 origin "$SHA"
    git -C "$SUB" checkout --detach "$SHA"
fi

echo "+++ $SUB @ $(git -C "$SUB" rev-parse --short HEAD), sparse: ${PATTERNS[*]}"
