#!/usr/bin/env bash
# Verifica, SENZA hardware, che l'ambiente per il bridge PX4 <-> ROS 2 sia a
# posto: agent, px4_msgs, workspace, scambio di messaggi. Da eseguire nel
# container (una volta finite tutte le build di entrypoint.sh), dall'host:
#   sudo docker cp scripts/check_px4_bridge.sh <container>:/tmp/
#   sudo docker exec <container> bash /tmp/check_px4_bridge.sh
# Exit code 0 se tutto ok, 1 se almeno un controllo fallisce.
# Non testa il collegamento col Pixhawk (serve l'hardware): vedi README.
set +e

PASS=0; FAIL=0
ok()   { echo "  [ OK ] $*"; PASS=$((PASS+1)); }
ko()   { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
info() { echo "  [info] $*"; }
# </dev/null: i comandi non devono mai leggere lo stdin dello script
check() { local d=$1; shift; if "$@" </dev/null >/dev/null 2>&1; then ok "$d"; else ko "$d"; fi; }

source /opt/ros/humble/setup.bash 2>/dev/null
for ws in depthai-ws px4-ws colcon_ws; do
    [ -f /root/$ws/install/setup.bash ] && source /root/$ws/install/setup.bash 2>/dev/null
done

echo "== 1. Micro-XRCE-DDS-Agent"
AGENT=$(command -v MicroXRCEAgent)
if [ -n "$AGENT" ]; then ok "MicroXRCEAgent nel PATH ($AGENT)"; else ko "MicroXRCEAgent non trovato"; fi
if [ -n "$AGENT" ]; then
    if ldd -r "$AGENT" 2>&1 | grep -qE "not found|undefined symbol"; then
        ko "librerie mancanti / simboli non risolti (ldd -r)"
    else
        ok "librerie e simboli risolti (ldd -r)"
    fi
    BAD=$(ldd "$AGENT" | grep -E "libfastrtps|libfastcdr" | grep -v "/opt/ros/humble/")
    if [ -z "$BAD" ]; then ok "Fast-DDS/Fast-CDR risolte solo da /opt/ros/humble (una sola copia)"; else ko "Fast-DDS/Fast-CDR da altrove: $BAD"; fi
    info "$(ldd "$AGENT" | grep -E 'libfastrtps' | awk '{print $1}')"
    # test funzionale: l'agent parte e apre la porta UDP (porta 8899, per non
    # collidere con un agent gia' attivo su 8888)
    PORT=8899
    MicroXRCEAgent udp4 -p $PORT >/tmp/agent_check.log 2>&1 </dev/null &
    APID=$!
    sleep 3
    HEX=$(printf '%04X' $PORT)
    if kill -0 $APID 2>/dev/null && grep -qi ":$HEX " /proc/net/udp; then
        ok "l'agent parte e ascolta su UDP $PORT"
    else
        ko "l'agent non parte / non ascolta su UDP $PORT (log: /tmp/agent_check.log)"; tail -5 /tmp/agent_check.log
    fi
    kill $APID 2>/dev/null; wait $APID 2>/dev/null
fi

echo "== 2. px4_msgs (generato dal fork PX4)"
for p in px4_msgs px4_msgs_old translation_node; do
    check "pacchetto $p installato" ros2 pkg prefix $p
done
NMSG=$(ros2 interface list 2>/dev/null </dev/null | grep -c "px4_msgs/msg/")
if [ "${NMSG:-0}" -ge 200 ]; then ok "px4_msgs espone $NMSG messaggi"; else ko "px4_msgs espone solo ${NMSG:-0} messaggi (attesi ~235)"; fi
check "servizio px4_msgs/srv/VehicleCommand" ros2 interface show px4_msgs/srv/VehicleCommand
for m in VehicleOdometry VehicleLocalPosition VehicleAttitude VehicleStatus SensorCombined; do
    check "messaggio px4_msgs/msg/$m" ros2 interface show px4_msgs/msg/$m
done
if ros2 interface show px4_msgs/msg/VehicleOdometry 2>/dev/null </dev/null | grep -q "POSE_FRAME_FRD"; then
    ok "VehicleOdometry ha POSE_FRAME_FRD"
else
    ko "VehicleOdometry senza POSE_FRAME_FRD"
fi
if [ "${NMSG:-0}" -ge 200 ]; then
    if ros2 interface list 2>/dev/null </dev/null | grep -q light_board; then
        info "light_board presente in px4_msgs (atteso escluso)"
    else
        ok "light_board.msg escluso come previsto"
    fi
fi
check "import Python px4_msgs" python3 -c "from px4_msgs.msg import VehicleOdometry, VehicleLocalPosition"

echo "== 3. Scambio messaggi ROS 2 con px4_msgs (QoS BEST_EFFORT, dominio isolato 99)"
ROS_DOMAIN_ID=99 python3 - <<'EOF' 2>&1 | tail -3
import sys, time
import rclpy
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from px4_msgs.msg import VehicleOdometry

rclpy.init()
n = rclpy.create_node('px4_check')
qos = QoSProfile(reliability=ReliabilityPolicy.BEST_EFFORT,
                 history=HistoryPolicy.KEEP_LAST, depth=1)
got = []
n.create_subscription(VehicleOdometry, '/px4_check/odom', got.append, qos)
pub = n.create_publisher(VehicleOdometry, '/px4_check/odom', qos)
m = VehicleOdometry()
m.position = [1.0, 2.0, 3.0]
m.pose_frame = VehicleOdometry.POSE_FRAME_FRD
t = time.time()
while time.time() - t < 8 and not got:
    pub.publish(m)
    rclpy.spin_once(n, timeout_sec=0.2)
good = bool(got) and list(got[0].position) == [1.0, 2.0, 3.0] \
    and got[0].pose_frame == VehicleOdometry.POSE_FRAME_FRD
print("roundtrip OK" if good else "roundtrip FALLITO")
sys.exit(0 if good else 1)
EOF
if [ ${PIPESTATUS[0]} -eq 0 ]; then ok "publish/subscribe VehicleOdometry (FastDDS + typesupport px4_msgs)"; else ko "publish/subscribe VehicleOdometry"; fi

echo "== 4. Altri workspace"
for p in depthai_ros_driver_v3 ov_core ov_init ov_msckf ov_eval; do
    check "pacchetto $p installato" ros2 pkg prefix $p
done
if command -v lsusb >/dev/null && lsusb | grep -qi "03e7"; then info "OAK-D (Luxonis, 03e7) visibile su USB"; else info "OAK-D non rilevata su USB (o lsusb assente): non bloccante"; fi

echo "== 5. Promemoria per il collegamento col Pixhawk"
info "ROS_DOMAIN_ID di questa shell: ${ROS_DOMAIN_ID:-non impostato (=0)}"
info "il client PX4 usa UXRCE_DDS_DOM_ID (default 0): deve coincidere col ROS_DOMAIN_ID, altrimenti /fmu/* non e' visibile"

echo
echo "Risultato: $PASS ok, $FAIL falliti"
[ $FAIL -eq 0 ]
