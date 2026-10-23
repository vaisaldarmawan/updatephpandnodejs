#!/usr/bin/env bash
# Ubuntu Maintenance — terminal-only audit / same-release package upgrades
# Intended for reviewed, trusted hosts. No network upload, external telemetry, or stored reports.
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_VERSION='0.4.2'
MODE='audit'
ALLOW_CONTAINER=0
UPDATE_NVM=0
NVM_UPDATED=0
RESTART=1
PUBLIC_IP_LOOKUP=1
DISK_PATH='/'
WARN=0
ERRORS=0
STEP=0
ORIGINAL_USER="${SUDO_USER:-${DOAS_USER:-$(id -un)}}"
EXEC_USER="$(id -un)"
RUN_USER="${USER:-$(id -un)}"
TMP=''
CONTAINER='no'
PHP_CHANGED=0
NODE_CHANGED=0
WEB_CHANGED=0
APT_RAN=0
RESTART_FAILED=0
PM2_DISCOVERED=0
APPLY_ABORTED=0
NVM_PRESENT=0
NODE_LTS=0
AUTO_LTS=1
NODE_LTS_MAJOR=24
PHP_STABLE_SERIES='8.5'
PHP_MIGRATED=0
NODE_LTS_SKIPPED=0
UNMANAGED_NODE_UPGRADE=0
UNMANAGED_NODE_POST=0
RUNTIME_TARGET_FAILED=0
NODE_SOURCE_FILE=''
NODE_SOURCE_BACKUP=''
NODE_SOURCE_SWITCHED=0
NODE_MAJOR_INSTALLED=0
START_PHASE_DONE=0
STOP_PHASE_ENTERED=0

usage() {
cat <<'HELP'
Ubuntu Maintenance v0.4.2 — terminal-only (no report upload or saved logs)

  bash ubuntu-maintenance-v0.4.2.sh --audit             # regular user or root
  sudo bash ubuntu-maintenance-v0.4.2.sh --audit        # fuller host inventory
  bash ubuntu-maintenance-v0.4.2.sh --demo              # simulated terminal view
  sudo bash ubuntu-maintenance-v0.4.2.sh --apply        # stop managed apps, upgrade runtimes, start and verify

Options:
  --audit                 Read-only inventory (default), supports non-root/container
  --apply                 Stop managed PHP/Node apps, upgrade runtimes, start apps, verify
  --allow-container-apply Explicitly permit APT inside container (no auto restarts)
  --update-nvm            Update NVM default within its existing major (optional)
  --node-lts              Require a recognized NodeSource path to Node 24 LTS (strict mode)
  --no-restart            Do not stop/start managed apps (not recommended for major upgrades)
  --no-public-ip          Never contact an external IP lookup endpoint
  --disk-path PATH        Filesystem to report (default /)
  --demo                  Simulated, fictional output; no system operations
  -h, --help              Show this help

Important:
* APT updates installed Ubuntu-managed PHP/Node packages, NOT NVM/asdf/fnm,
  Docker images, or binaries installed manually. PHP 8.5 requires an existing compatible APT repository; the script never silently adds a PPA.
* Managed PHP/Node systemd services and online PM2 apps are stopped before changing packages and started afterward, including recovery attempts on failure. An unsupervised process cannot be safely restarted automatically and remains running; restart it manually.
* PHP 8.5 CLI migration runs only for CLI-only installs with matching modules; existing PHP-FPM virtual hosts are never automatically rewired. Latest PHP major may remain pending on FPM-backed sites.
* Apply needs no configuration file; post-upgrade verification checks process/systemd/PM2 status, not HTTP functionality. During the stop→start window, monitored applications may be unavailable.
* No automatic reboot, rollback, or container orchestration actions.
* apt-get itself can restart services before our controlled restart phase.
* Only terminal text is output; an internal temporary directory is removed on exit.
HELP
}

demo() {
cat <<'DEMO'
╔════════════════════════════════════════════════════════════════════╗
║  UBUNTU MAINTENANCE v0.4.2 • SIMULASI (BUKAN HASIL SERVER ASLI)   ║
╚════════════════════════════════════════════════════════════════════╝
[15:08:21] Mode              : APPLY
[15:08:21] Hostname          : prod-api-01
[15:08:21] OS                : Ubuntu 24.04 LTS
[15:08:21] Pengguna login    : deploy
[15:08:21] Pengguna efektif  : root (via sudo)
[15:08:21] Lingkungan        : Host / VM
[15:08:21] IP lokal          : 192.168.10.20
[15:08:21] IP publik (egress): 203.0.113.20
[15:08:21] CPU               : 12.8% terpakai | 8 vCPU
[15:08:21] RAM               : 3.20 GiB terpakai / 8.00 GiB total (4.80 GiB available)
[15:08:21] Disk /            : 42.00 GiB terpakai / 100.00 GiB total (58.00 GiB free)

──── [01] RUNTIME AWAL ────
[15:08:22] ✓ PHP   /usr/bin/php     : 8.5.12
[15:08:22] ✓ Node  /usr/bin/node    : v22.23.2
[15:08:22] NVM: tidak ditemukan

──── [02] APLIKASI / BASELINE ────
[15:08:23] ✓ systemd  api.service        active    /usr/bin/node
[15:08:23] ✓ pm2      webhook (deploy)   online    PID 8812
[15:08:23] ✓ php-fpm  php8.5-fpm.service active
[15:08:23] ✓ baseline api.service aktif dan webhook PM2 online

──── [03] STOP SERVICE (YANG SEBELUMNYA AKTIF) ────
[15:08:24] Stop php8.5-fpm.service   [done]
[15:08:25] Stop api.service          [done]
[15:08:26] Stop PM2 deploy/webhook   [done]

──── [04] UPGRADE RUNTIME & PAKET ────
[15:08:30] Apt Update               [done]
[15:08:38] Node 24 LTS Upgrade      [done]
[15:08:53] Apt Upgrade              [done]
[15:08:59] PHP Stable Check         [done]

──── [05] START SERVICE & VERIFIKASI ────
[15:09:03] Start php8.5-fpm.service  [done]
[15:09:05] Start api.service         [done]
[15:09:08] Start PM2 deploy/webhook  [done]
[15:09:10] Verifikasi proses        [done]

╔═══════════════════ RINGKASAN ═════════════════════════════════════╗
  Login / eksekusi   : deploy / root
  IP lokal / publik  : 192.168.10.20 / 203.0.113.20
  PHP               : 8.5.12 -> 8.5.12
  Node.js (APT)     : v20.20.2 -> v24.22.1
  CPU / RAM / Disk  : 12.8% | 3.20 / 8.00 GiB | 58.00 / 100.00 GiB free
  Node apps         : api.service [active], webhook [online]
  Status aplikasi   : 2 aktif / 0 gagal (level proses)
  Restart           : 3 OK / 0 FAIL
  Hasil             : PASS (SIMULASI)
╚═══════════════════════════════════════════════════════════════════╝
DEMO
}

while (( $# > 0 )); do
  case "$1" in
    --audit) MODE='audit' ;;
    --apply) MODE='apply' ;;
    --demo) demo; exit 0 ;;
    --allow-container-apply) ALLOW_CONTAINER=1 ;;
    --update-nvm) UPDATE_NVM=1 ;;
    --node-lts) NODE_LTS=1; AUTO_LTS=0 ;;
    --no-restart) RESTART=0 ;;
    --no-public-ip) PUBLIC_IP_LOOKUP=0 ;;
    --disk-path)
      (( $# >= 2 )) || { printf 'Argument missing for %s\n' "$1" >&2; exit 64; }
      DISK_PATH=$2
      shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done
if ((NODE_LTS)) && [[ $MODE != apply ]]; then
  printf '%s\n' '--node-lts requires --apply' >&2
  exit 64
fi
if ((UPDATE_NVM)) && [[ $MODE != apply ]]; then
  printf '%s\n' '--update-nvm requires --apply' >&2
  exit 64
fi

# Output is both readable in pipes and animated on an interactive terminal.
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  CYAN=''; GREEN=''; YELLOW=''; RED=''; RESET=''
fi
log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
ok() { log "${GREEN}✓${RESET} $*"; }
warn() { WARN=$((WARN+1)); log "${YELLOW}!${RESET} $*"; }
err() { ERRORS=$((ERRORS+1)); log "${RED}✗${RESET} $*"; }
section() { STEP=$((STEP+1)); printf '\n%s──── [%02d] %s ────%s\n' "$CYAN" "$STEP" "$*" "$RESET"; }
cleanup() {
  local rc=$?
  trap - EXIT
  if (( STOP_PHASE_ENTERED == 1 && START_PHASE_DONE == 0 )) && declare -F bring_back_managed >/dev/null 2>&1; then
    printf '\n[RECOVERY] Upaya menghidupkan kembali service/aplikasi yang dihentikan...\n' >&2
    bring_back_managed || true
  fi
  if (( NODE_SOURCE_SWITCHED == 1 && NODE_MAJOR_INSTALLED == 0 )) && [[ -n $NODE_SOURCE_FILE && -f $NODE_SOURCE_BACKUP ]]; then
    cp -p -- "$NODE_SOURCE_BACKUP" "$NODE_SOURCE_FILE" || printf 'WARNING: failed restoring NodeSource repository %s\n' "$NODE_SOURCE_FILE" >&2
  fi
  if [[ -n $TMP && -d $TMP ]]; then rm -rf -- "$TMP"; fi
  exit "$rc"
}
trap cleanup EXIT
trap 'rc=$?; err "Perintah gagal di baris $LINENO (exit code $rc). Periksa output sebelumnya."; exit 2' ERR

TMP=$(mktemp -d /tmp/ubuntu-maintenance.XXXXXXXX)
chmod 700 "$TMP"

command -v ps >/dev/null 2>&1 || { err 'ps command is required'; exit 2; }
[[ -r /etc/os-release ]] && . /etc/os-release || { err '/etc/os-release is missing'; exit 2; }

if [[ -f /.dockerenv || -f /run/.containerenv || -n ${container:-} ]]; then
  CONTAINER='yes'
elif command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --quiet --container 2>/dev/null; then
  CONTAINER='yes'
elif [[ -r /proc/1/cgroup ]] && grep -Eiq '(docker|kubepods|containerd|podman|lxc)' /proc/1/cgroup; then
  CONTAINER='yes'
fi
if [[ $MODE == apply ]]; then
  if (( EUID != 0 )); then err 'Apply requires root. Run with sudo, or use --audit.'; exit 77; fi
  if [[ ${ID:-} != ubuntu ]]; then err "Apply supports Ubuntu only; detected ${ID:-unknown}."; exit 2; fi
  if [[ $CONTAINER == yes && $ALLOW_CONTAINER -ne 1 ]]; then
    err 'Detected a container: image rebuild/redeploy recommended. To update container packages explicitly use --allow-container-apply.'
    exit 2
  fi
  command -v apt-get >/dev/null || { err 'apt-get unavailable'; exit 2; }
fi
if [[ ! -d $DISK_PATH ]]; then err "Disk path not found: $DISK_PATH"; exit 64; fi

# Float formatting in GiB and CPU percentage; awk requires a dot decimal here.
gib() { LC_ALL=C awk -v n="${1:-0}" 'BEGIN {printf "%.2f", n/1073741824}'; }
# Animated spinner for quiet operations; live APT output is NOT buffered.
spinner_wait() {
  local pid=$1 description=$2 index=0
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  if [[ -t 1 ]]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r  %s %s' "${frames[index%10]}" "$description"
      index=$((index+1))
      sleep 0.12
    done
    printf '\r\033[K'
  fi
  wait "$pid"
}

cpu_sample() {
  local dest=$1 headline
  if [[ -r /proc/stat ]]; then
    read -r headline < /proc/stat
    printf '%s\n' "$headline" > "$dest"
  else echo '' > "$dest"; fi
}
cpu_host_percent() {
  local f1=$1 f2=$2
  LC_ALL=C awk 'NR==1 {for(i=2;i<=NF;i++) a+= $i; idle1=$5+$6} NR==2 {for(i=2;i<=NF;i++) b+=$i; idle2=$5+$6} END {if(b>a) printf "%.1f", 100*(1-(idle2-idle1)/(b-a)); else printf "n/a"}' "$f1" "$f2"
}
# Container-aware memory and CPU (cgroup v2 where available). /proc/loadavg is host-wide.
CPU_VIEW='host'
cpu_sample "$TMP/cpu1"
CG_CPU_1=''; CG_CPU_2=''
if [[ $CONTAINER == yes && -r /sys/fs/cgroup/cpu.stat ]]; then
  CG_CPU_1=$(awk '$1=="usage_usec"{print $2}' /sys/fs/cgroup/cpu.stat || true)
fi
sleep 1 &
spinner_wait "$!" 'Mengukur penggunaan CPU selama 1 detik...'
cpu_sample "$TMP/cpu2"
if [[ -n $CG_CPU_1 ]]; then CG_CPU_2=$(awk '$1=="usage_usec"{print $2}' /sys/fs/cgroup/cpu.stat || true); fi
CPU_USED="$(cpu_host_percent "$TMP/cpu1" "$TMP/cpu2")"
CPU_CORES="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo '?')"
if [[ -n $CG_CPU_1 && -n $CG_CPU_2 ]]; then
  CPU_VIEW='container quota'
  CPU_QUOTA=''
  if [[ -r /sys/fs/cgroup/cpu.max ]]; then
    IFS=' ' read -r CPU_QUOTA CPU_PERIOD < /sys/fs/cgroup/cpu.max || true
  fi
  if [[ ${CPU_QUOTA:-max} == max || -z ${CPU_QUOTA:-} ]]; then
    # Percentage of a single core if no finite CPU quota is set.
    CPU_USED="$(LC_ALL=C awk -v a="$CG_CPU_1" -v b="$CG_CPU_2" 'BEGIN {printf "%.1f", (b-a)/10000}')"
    CPU_VIEW='container (1 core = 100%)'
  else
    CPU_USED="$(LC_ALL=C awk -v a="$CG_CPU_1" -v b="$CG_CPU_2" -v q="$CPU_QUOTA" -v p="$CPU_PERIOD" 'BEGIN {if(q>0 && p>0) printf "%.1f", 100*(b-a)/1000000/(q/p); else print "n/a"}')"
  fi
fi
LOADAVG="$(LC_ALL=C awk '{printf "%s / %s / %s",$1,$2,$3}' /proc/loadavg 2>/dev/null || echo unavailable)"

MEM_TOTAL=$(awk '/^MemTotal:/ {print $2*1024;exit}' /proc/meminfo 2>/dev/null || echo 0)
MEM_AVAIL=$(awk '/^MemAvailable:/ {print $2*1024;exit}' /proc/meminfo 2>/dev/null || echo 0)
MEM_USED=$(LC_ALL=C awk -v a="$MEM_TOTAL" -v b="$MEM_AVAIL" 'BEGIN {printf "%.0f", a-b}')
MEM_SCOPE='host'
if [[ $CONTAINER == yes && -r /sys/fs/cgroup/memory.max && -r /sys/fs/cgroup/memory.current ]]; then
  MEM_LIMIT=$(cat /sys/fs/cgroup/memory.max)
  if [[ $MEM_LIMIT =~ ^[0-9]+$ ]] && (( MEM_LIMIT > 0 )) && (( MEM_LIMIT < MEM_TOTAL )); then
    MEM_TOTAL=$MEM_LIMIT
    MEM_USED=$(cat /sys/fs/cgroup/memory.current)
    MEM_AVAIL=$((MEM_TOTAL > MEM_USED ? MEM_TOTAL-MEM_USED : 0))
    MEM_SCOPE='container limit'
  fi
fi
read -r DISK_TOTAL DISK_USED DISK_AVAIL DISK_PC < <(df -B1 --output=size,used,avail,pcent "$DISK_PATH" | awk 'NR==2 {print $1,$2,$3,$4}' | tr ' ' '\t') || true
DISK_TOTAL=${DISK_TOTAL:-0}; DISK_USED=${DISK_USED:-0}; DISK_AVAIL=${DISK_AVAIL:-0}; DISK_PC=${DISK_PC:-?}

LOCAL_IP='unavailable'
if command -v ip >/dev/null 2>&1; then
  LOCAL_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}' || true)"
fi
if [[ -z $LOCAL_IP || $LOCAL_IP == unavailable ]]; then
  LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
fi
LOCAL_IP=${LOCAL_IP:-unavailable}
PUBLIC_IP='unavailable'
if (( PUBLIC_IP_LOOKUP )) && command -v curl >/dev/null 2>&1; then
  ip_candidate=$(curl -4 -fsS --connect-timeout 2 --max-time 4 https://api.ipify.org 2>/dev/null || true)
  if [[ $ip_candidate =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then PUBLIC_IP=$ip_candidate; fi
fi

printf '\n╔═════════════════════════════════════════════════════════════════╗\n'
printf '║            UBUNTU MAINTENANCE v%-8s                      ║\n' "$SCRIPT_VERSION"
printf '╚═════════════════════════════════════════════════════════════════╝\n'
log "Mode              : ${MODE^^}"
log "Hostname          : $(hostname -f 2>/dev/null || hostname)"
log "OS                : ${PRETTY_NAME:-unknown}"
log "Pengguna login    : $ORIGINAL_USER"
log "Pengguna efektif  : $EXEC_USER $( ((EUID==0)) && [[ $ORIGINAL_USER != root ]] && printf '(via sudo / su*)' || true)"
log "Lingkungan        : $([[ $CONTAINER == yes ]] && echo Container || echo 'Host / VM')"
log "IP lokal          : $LOCAL_IP"
log "IP publik (egress): $PUBLIC_IP"
log "CPU               : $CPU_USED% terpakai ($CPU_VIEW) | $CPU_CORES logical CPU"
log "RAM               : $(gib "$MEM_USED") GiB terpakai / $(gib "$MEM_TOTAL") GiB total ($(gib "$MEM_AVAIL") GiB available, $MEM_SCOPE)"
log "Disk $DISK_PATH            : $(gib "$DISK_USED") GiB terpakai / $(gib "$DISK_TOTAL") GiB total ($(gib "$DISK_AVAIL") GiB free, $DISK_PC used)"
[[ $PUBLIC_IP != unavailable || $PUBLIC_IP_LOOKUP -eq 0 ]] || warn 'IP publik tidak dapat diperoleh; lanjut tanpa IP publik.'
if (( EUID != 0 )); then warn 'Audit non-root: proses dan PM2 user lain mungkin tidak dapat dibaca.'; fi
if [[ $CONTAINER == yes ]]; then warn 'Dalam container: load average biasanya milik host; disk dapat berupa overlay. Host dan image container adalah dua entitas berbeda.'; fi

# Data captured to temporary files ONLY; removed on EXIT.
: > "$TMP/php-before"; : > "$TMP/node-before"; : > "$TMP/nvm-before"
: > "$TMP/php-after"; : > "$TMP/node-after"; : > "$TMP/nvm-after"
: > "$TMP/services-before"; : > "$TMP/services-after"
: > "$TMP/node-apps-before"; : > "$TMP/node-apps-after"
: > "$TMP/restart-results"
: > "$TMP/packages-before"; : > "$TMP/packages-after"; : > "$TMP/packages-changed"
: > "$TMP/pm2-before"; : > "$TMP/pm2-after"

version_snapshot() {
  local target=$1 runtime=$2 bin ver
  : > "$target"
  if [[ $runtime == php ]]; then
    for bin in /usr/bin/php /usr/bin/php[0-9]* /usr/local/bin/php /usr/local/bin/php[0-9]*; do
      [[ -x $bin && $bin =~ /php([0-9]+\.[0-9]+)?$ ]] || continue
      ver=$($bin -r 'echo PHP_VERSION;' 2>/dev/null || true)
      [[ $ver =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] && printf '%s|%s\n' "$bin" "$ver" >> "$target"
    done
  else
    for bin in /usr/bin/node /usr/local/bin/node /opt/node/bin/node; do
      [[ -x $bin ]] || continue
      ver=$($bin -v 2>/dev/null || true)
      [[ $ver =~ ^v[0-9]+\. ]] && printf '%s|%s\n' "$bin" "$ver" >> "$target"
    done
  fi
  # Respect the invoking process PATH, including NVM/asdf/fnm/custom installations.
  if [[ $runtime == node ]]; then
    bin=$(command -v node 2>/dev/null || true)
    if [[ -n $bin && -x $bin ]]; then
      ver=$($bin -v 2>/dev/null || true)
      [[ $ver =~ ^v[0-9]+\. ]] && printf '%s|%s\n' "$bin" "$ver" >> "$target"
    fi
  else
    bin=$(command -v php 2>/dev/null || true)
    if [[ -n $bin && -x $bin ]]; then
      ver=$($bin -r 'echo PHP_VERSION;' 2>/dev/null || true)
      [[ $ver =~ ^[0-9]+\. ]] && printf '%s|%s\n' "$bin" "$ver" >> "$target"
    fi
  fi
  sort -u "$target" -o "$target"
}

nvm_snapshot() {
  local target=$1 username unused uid gid gecos home shell exe ver
  : > "$target"
  while IFS=: read -r username unused uid gid gecos home shell; do
    [[ -d $home/.nvm/versions/node ]] || continue
    if ((EUID != 0)) && [[ $username != "$EXEC_USER" ]]; then continue; fi
    NVM_PRESENT=1
    for exe in "$home"/.nvm/versions/node/v*/bin/node; do
      [[ -x $exe ]] || continue
      ver=$($exe -v 2>/dev/null || true)
      printf '%s|%s|%s\n' "$username" "$exe" "$ver" >> "$target"
    done
  done < /etc/passwd
  # Capture calling PATH's externally managed Node even when not under a passwd home.
  local path_node
  path_node=$(command -v node 2>/dev/null || true)
  if [[ $path_node == */versions/node/v*/bin/node && -x $path_node ]]; then
    ver=$($path_node -v 2>/dev/null || true)
    printf '%s|%s|%s\n' "$EXEC_USER" "$path_node" "$ver" >> "$target"
    NVM_PRESENT=1
  fi
  sort -u "$target" -o "$target"
}

# POSIX name detection; process args not printed to avoid leaking secrets.
node_exe() { readlink "/proc/$1/exe" 2>/dev/null || true; }
service_for_pid() {
  local pid=$1
  [[ -r /proc/$pid/cgroup ]] || return 0
  grep -oE '[A-Za-z0-9_.@-]+\.service' "/proc/$pid/cgroup" 2>/dev/null | tail -n 1 || true
}
node_proc_inventory() {
  local target=$1 pid user cmd exe unit cwd desc state
  : > "$target"
  while IFS=' ' read -r pid user cmd; do
    [[ $pid =~ ^[0-9]+$ ]] || continue
    case "$cmd" in node|nodejs|npm) ;; *) continue;; esac
    exe=$(node_exe "$pid")
    unit=$(service_for_pid "$pid")
    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
    if [[ -n $unit ]]; then
      desc=$unit; state="$(systemctl is-active "$unit" 2>/dev/null || echo unknown)"
      printf 'systemd|%s|%s|%s|%s|%s\n' "$user" "$desc" "$state" "$pid" "$exe" >> "$target"
    else
      desc="${cwd##*/}"; [[ -n $desc ]] || desc="node-pid-$pid"
      state='running (health unverified)'
      printf 'process|%s|%s|%s|%s|%s\n' "$user" "$desc" "$state" "$pid" "$exe" >> "$target"
    fi
  done < <(ps -eo pid=,user=,comm= -ww 2>/dev/null || true)
}

pm2_for_home() {
  local home=$1 x
  for x in /usr/bin/pm2 /usr/local/bin/pm2 "$home"/.nvm/versions/node/v*/bin/pm2; do
    [[ -x $x ]] && { printf '%s' "$x"; return; }
  done
  return 1
}

pm2_inventory() {
  local target=$1 phase=$2 username unused uid gid gecos home shell pid bin raw
  : > "$target"
  command -v python3 >/dev/null 2>&1 || { warn 'Python3 tidak tersedia: PM2 app discovery terbatas.'; return; }
  while IFS=: read -r username unused uid gid gecos home shell; do
    [[ -r $home/.pm2/pm2.pid ]] || continue
    if ((EUID!=0)) && [[ $username != "$EXEC_USER" ]]; then continue; fi
    pid=$(cat "$home/.pm2/pm2.pid" 2>/dev/null || true)
    [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null || continue
    bin=$(pm2_for_home "$home" || true)
    if [[ -z $bin ]]; then warn "PM2 daemon user=$username terdeteksi, CLI tidak tersedia"; continue; fi
    raw="$TMP/pm2-${phase}-${username}.json"
    # Avoid pm2 starting daemons when none exist; existing pid was checked.
    if ((EUID==0)); then
      timeout 10 runuser -u "$username" -- env HOME="$home" PM2_HOME="$home/.pm2" PATH="$(dirname "$bin"):$PATH" "$bin" jlist > "$raw" 2>/dev/null || true
    else
      timeout 10 env PM2_HOME="$home/.pm2" PATH="$(dirname "$bin"):$PATH" "$bin" jlist > "$raw" 2>/dev/null || true
    fi
    [[ -s $raw ]] || continue
    python3 - "$raw" "$username" "$bin" >> "$target" <<'PY'
import json,sys
try:
    with open(sys.argv[1]) as f: apps=json.load(f)
except (ValueError,OSError):
    apps=[]
for app in apps if isinstance(apps,list) else []:
    e=app.get('pm2_env') or {}
    name=str(app.get('name') or 'unnamed').replace('|','/').replace('\n',' ')[:80]
    status=str(e.get('status') or 'unknown')[:24]
    pid=app.get('pid') or 0
    pm_id=app.get('pm_id')
    if not isinstance(pid,int): pid=0
    if not isinstance(pm_id,int): continue
    print('|'.join((sys.argv[2], name, status, str(pid), str(pm_id), sys.argv[3])))
PY
  done < /etc/passwd
}

services_inventory() {
  local target=$1 unit
  : > "$target"
  if ! command -v systemctl >/dev/null 2>&1 || [[ $CONTAINER == yes ]]; then return; fi
  systemctl list-units --all --type=service --plain --no-legend --no-pager 2>/dev/null |
    awk '{print $1}' | grep -E '^(php[0-9.]+-fpm|nginx|apache2|pm2-[A-Za-z0-9_.@-]+)\.service$' |
    while IFS= read -r unit; do
      printf '%s|%s\n' "$unit" "$(systemctl is-active "$unit" 2>/dev/null || echo unknown)"
    done > "$target" || true
  # Include custom PHP worker services (for example artisan queue workers).
  local php_pid php_user php_cmd php_unit
  while IFS=' ' read -r php_pid php_user php_cmd; do
    [[ $php_pid =~ ^[0-9]+$ && $php_cmd =~ ^php([0-9.]+)?$ ]] || continue
    php_unit=$(service_for_pid "$php_pid")
    [[ $php_unit == *.service ]] || continue
    printf '%s|%s\n' "$php_unit" "$(systemctl is-active "$php_unit" 2>/dev/null || echo unknown)" >> "$target"
  done < <(ps -eo pid=,user=,comm= -ww 2>/dev/null || true)
  # Also collect custom systemd Node units, where visible through process cgroups.
  while IFS='|' read -r manager user name status pid exe; do
    [[ $manager == systemd && $name == *.service ]] || continue
    printf '%s|%s\n' "$name" "$(systemctl is-active "$name" 2>/dev/null || echo unknown)" >> "$target"
  done < "$TMP/node-apps-before"
  sort -u "$target" -o "$target"
}

show_runtime() {
  local target=$1 label=$2 path ver count=0
  while IFS='|' read -r path ver; do
    [[ -n $path ]] || continue
    ok "$label  $path : $ver"
    count=$((count+1))
  done < "$target"
  (( count>0 )) || log "$label: N/A"
}

# Quiet command runner: never show raw APT output on success.
# On a real terminal, redraw ONE short spinner line. In pipes/log captures,
# show only the final result, never a frame for every tick.
run_quiet() {
  local description=$1; shift
  local slug logfile rc index=0 pid lastline
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  slug=$(printf '%s' "$description" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')
  logfile="$TMP/${slug:-step}.log"
  : > "$logfile"
  if [[ -t 1 && -z ${CI:-} && ${TERM:-dumb} != dumb ]]; then
    "$@" >"$logfile" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
      # \\033[2K wipes the whole line, including remnants of earlier frames.
      printf '\r\033[2K  %s %s' "${frames[index%10]}" "$description"
      index=$((index+1))
      sleep 0.24
    done
    if wait "$pid"; then rc=0; else rc=$?; fi
    printf '\r\033[2K'
  else
    if "$@" >"$logfile" 2>&1; then rc=0; else rc=$?; fi
  fi
  if (( rc == 0 )); then
    printf '[%s] %-23s %b[done]%b\n' "$(date '+%H:%M:%S')" "$description" "$GREEN" "$RESET"
    return 0
  fi
  printf '[%s] %-23s %b[failed]%b\n' "$(date '+%H:%M:%S')" "$description" "$RED" "$RESET"
  lastline=$(awk 'NF{line=$0} END{print line}' "$logfile" 2>/dev/null || true)
  if [[ -n $lastline ]]; then
    err "$description: ${lastline:0:220} (exit $rc)"
  else
    err "$description gagal tanpa detail dari program (exit $rc)."
  fi
  return "$rc"
}

section 'RUNTIME AWAL (PHP / NODE / NVM)'
version_snapshot "$TMP/php-before" php
version_snapshot "$TMP/node-before" node
nvm_snapshot "$TMP/nvm-before"
show_runtime "$TMP/php-before" 'PHP '
show_runtime "$TMP/node-before" 'Node'
if [[ -s $TMP/nvm-before ]]; then
  while IFS='|' read -r username path ver; do log "NVM user=$username $ver ($path): inventory only"; done < "$TMP/nvm-before"
else log 'NVM: tidak ditemukan / tidak dapat diakses'; fi

section 'APLIKASI NODE, PHP, PM2, SYSTEMD (BASELINE)'
node_proc_inventory "$TMP/node-apps-before"
pm2_inventory "$TMP/pm2-before" before
services_inventory "$TMP/services-before"
if [[ -s $TMP/node-apps-before ]]; then
  while IFS='|' read -r manager user name status pid exe; do log "Node [$manager] user=$user app=$name status=$status PID=$pid runtime=${exe:-unknown}"; done < "$TMP/node-apps-before"
else log 'Proses Node host: tidak ditemukan / tidak dapat diakses'; fi
if [[ -s $TMP/pm2-before ]]; then
  while IFS='|' read -r user name status pid id bin; do log "PM2 user=$user app=$name status=$status PID=$pid"; done < "$TMP/pm2-before"
else log 'PM2 aktif: tidak ditemukan / tidak dapat diakses'; fi
if [[ -s $TMP/services-before ]]; then
  while IFS='|' read -r unit status; do log "Service $unit: $status"; done < "$TMP/services-before"
else log 'systemd: tidak tersedia atau tidak ada service relevan'; fi
if command -v docker >/dev/null 2>&1 && [[ $CONTAINER == no ]]; then
  docker ps --format '  container={{.Names}} image={{.Image}} status={{.Status}}' 2>/dev/null || true
fi

section 'BASELINE SERVICE / PROSES'
log 'Baseline dicatat otomatis dari systemd, PM2, dan proses Node.js.'
log 'Tidak perlu konfigurasi tambahan. Status proses saja tidak menjamin fungsi API/DB/queue.'

restart_record() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$TMP/restart-results"; }

# Snapshot-driven lifecycle. Never stop bare process/screen/tmux workloads:
# their startup commands and environment cannot be faithfully reconstructed.
: > "$TMP/stopped-services"
: > "$TMP/stopped-pm2"
: > "$TMP/stop-plan-services"
: > "$TMP/stop-plan-pm2"

pm2_run_as() {
  local user=$1 home=$2 bin=$3; shift 3
  timeout 60 runuser -u "$user" -- env HOME="$home" PM2_HOME="$home/.pm2" PATH="$(dirname "$bin"):$PATH" "$bin" "$@"
}

managed_stop_plan() {
  local mgr user name status pid exe pmuser pmname pmstatus pmpid id bin home unit
  : > "$TMP/stop-plan-services"
  : > "$TMP/stop-plan-pm2"
  while IFS='|' read -r unit status; do
    [[ $status == active ]] || continue
    if [[ $unit =~ ^php[0-9.]+-fpm\.service$ ]]; then
      printf '%s\n' "$unit" >> "$TMP/stop-plan-services"
    elif [[ $unit == apache2.service ]] && grep -q '^libapache2-mod-php' "$TMP/packages-before" 2>/dev/null; then
      printf '%s\n' "$unit" >> "$TMP/stop-plan-services"
    fi
  done < "$TMP/services-before"
  while IFS='|' read -r mgr user name status pid exe; do
    [[ $mgr == systemd && $status == active && $name == *.service ]] || continue
    case "$name" in
      pm2-*.service|user@*.service|systemd-*.service) continue ;;
    esac
    [[ $name =~ ^[A-Za-z0-9_.@-]+\.service$ ]] || continue
    # If the PID belongs to a PM2-managed app, control it via PM2 instead.
    if awk -F '|' -v p="$pid" '$4==p {f=1} END{exit !f}' "$TMP/pm2-before"; then continue; fi
    printf '%s\n' "$name" >> "$TMP/stop-plan-services"
  done < "$TMP/node-apps-before"
  # Include PHP workers even when systemd unit names do not start with php.
  local php_pid php_comm
  while IFS=' ' read -r php_pid php_comm; do
    [[ $php_pid =~ ^[0-9]+$ && $php_comm =~ ^php([0-9.]+)?$ ]] || continue
    unit=$(service_for_pid "$php_pid")
    [[ $unit == *.service && $unit != user@*.service && $unit != pm2-*.service ]] || continue
    status=$(systemctl is-active "$unit" 2>/dev/null || true)
    [[ $status == active ]] && printf '%s\n' "$unit" >> "$TMP/stop-plan-services"
  done < <(ps -eo pid=,comm= -ww 2>/dev/null || true)
  sort -u "$TMP/stop-plan-services" -o "$TMP/stop-plan-services"

  while IFS='|' read -r pmuser pmname pmstatus pmpid id bin; do
    [[ $pmstatus == online && $id =~ ^[0-9]+$ ]] || continue
    home=$(getent passwd "$pmuser" 2>/dev/null | cut -d: -f6)
    if [[ -z $home || ! -x $bin ]]; then
      err "PM2 $pmuser/$pmname aktif namun CLI/home tidak dapat diverifikasi; stop otomatis dibatalkan."
      return 1
    fi
    printf '%s|%s|%s|%s|%s\n' "$pmuser" "$pmname" "$id" "$bin" "$home" >> "$TMP/stop-plan-pm2"
  done < "$TMP/pm2-before"
  return 0
}

stop_managed() {
  local unit user name id bin home
  (( RESTART == 1 )) && [[ $CONTAINER == no ]] || return 0
  section 'STOP SERVICE PHP/NODE SEBELUM UPGRADE'
  if ! managed_stop_plan; then return 1; fi
  STOP_PHASE_ENTERED=1
  while IFS= read -r unit; do
    [[ -n $unit ]] || continue
    printf '%s\n' "$unit" >> "$TMP/stopped-services"
    if run_quiet "Stop $unit" systemctl stop "$unit"; then
      :
    else
      err "Gagal menghentikan $unit; akan dicoba hidupkan kembali sebelum keluar."
      return 1
    fi
  done < "$TMP/stop-plan-services"
  while IFS='|' read -r user name id bin home; do
    [[ -n $user ]] || continue
    printf '%s|%s|%s|%s|%s\n' "$user" "$name" "$id" "$bin" "$home" >> "$TMP/stopped-pm2"
    if run_quiet "Stop PM2 $user/$name" pm2_run_as "$user" "$home" "$bin" stop "$id"; then
      :
    else
      err "Gagal menghentikan PM2 $user/$name; akan dicoba hidupkan kembali."
      return 1
    fi
  done < "$TMP/stop-plan-pm2"
  if [[ ! -s $TMP/stopped-services && ! -s $TMP/stopped-pm2 ]]; then
    log 'Tidak ada PHP/Node service terkelola yang perlu dihentikan.'
  fi
  # Unsupervised runtime processes cannot be restarted reliably.
  while IFS='|' read -r mgr user name status pid exe; do
    [[ $mgr == process ]] || continue
    if awk -F '|' -v p="$pid" '$4==p {f=1} END{exit !f}' "$TMP/pm2-before"; then continue; fi
    warn "Proses mandiri $user/$name (PID $pid) tidak dihentikan: perintah untuk menyalakannya kembali tidak diketahui."
  done < "$TMP/node-apps-before"
  return 0
}

bring_back_managed() {
  local unit user name id bin home failure=0
  # This function is also invoked by EXIT recovery. Do not defer starts on APT errors.
  while IFS= read -r unit; do
    [[ -n $unit ]] || continue
    if run_quiet "Start $unit" systemctl start "$unit" && systemctl is-active --quiet "$unit"; then
      restart_record "$unit" OK active
    else
      err "$unit tidak aktif setelah start."
      restart_record "$unit" FAIL start
      failure=1
    fi
  done < "$TMP/stopped-services"
  while IFS='|' read -r user name id bin home; do
    [[ -n $user ]] || continue
    if run_quiet "Start PM2 $user/$name" pm2_run_as "$user" "$home" "$bin" start "$id"; then
      restart_record "pm2:$user/$name" OK started
    else
      err "PM2 $user/$name gagal start."
      restart_record "pm2:$user/$name" FAIL start
      failure=1
    fi
  done < "$TMP/stopped-pm2"
  START_PHASE_DONE=1
  if ((failure)); then RESTART_FAILED=1; return 1; fi
  return 0
}

# NodeSource major migration is part of --apply when its repository is recognized.
# Only modify the single recognized NodeSource APT source (its signing key stays unchanged).
prepare_nodesource_lts() {
  local candidate file source_count=0 mgr user name status pid exe old_major new_content
  command -v dpkg-query >/dev/null 2>&1 || { err 'dpkg-query tidak tersedia.'; return 1; }
  [[ -x /usr/bin/node ]] || { err '--node-lts memerlukan instalasi Node.js sistem di /usr/bin/node.'; return 1; }
  candidate=$(dpkg-query -W -f='${Version}' nodejs 2>/dev/null || true)
  [[ -n $candidate ]] || { err '--node-lts hanya mendukung Node.js paket APT/NodeSource.'; return 1; }
  old_major=$(/usr/bin/node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)
  [[ $old_major =~ ^[0-9]+$ ]] || { err 'Versi Node sistem tidak dapat diperiksa.'; return 1; }
  if (( old_major > NODE_LTS_MAJOR )); then
    err "Node $old_major lebih baru daripada LTS $NODE_LTS_MAJOR; tidak melakukan downgrade otomatis."
    return 1
  fi
  if [[ $old_major == "$NODE_LTS_MAJOR" ]]; then
    log "Node.js sudah di cabang LTS $NODE_LTS_MAJOR.x. Upgrade patch tetap melalui APT."
    return 0
  fi
  # Do not stop a bare process; upgrading an installed binary does not replace
  # the interpreter of an already running application. Surface that fact later.
  while IFS='|' read -r mgr user name status pid exe; do
    [[ $mgr == process && $exe == /usr/bin/node* ]] || continue
    if [[ -s $TMP/pm2-before ]] && awk -F '|' -v p="$pid" '$4==p {f=1} END{exit !f}' "$TMP/pm2-before"; then continue; fi
    UNMANAGED_NODE_UPGRADE=1
  done < "$TMP/node-apps-before"
  if (( UNMANAGED_NODE_UPGRADE )); then
    warn 'Ada proses Node tanpa supervisor: runtime paket tetap akan di-upgrade, tetapi aplikasi tersebut perlu restart manual.'
  fi
  for file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [[ -f $file ]] || continue
    if grep -Eq 'deb\.nodesource\.com/node_[0-9]+\.x' "$file"; then
      NODE_SOURCE_FILE=$file
      source_count=$((source_count+1))
    fi
  done
  if ((source_count != 1)); then
    err "Ditemukan $source_count file repository NodeSource; diharapkan tepat satu. Tidak diubah otomatis."
    return 1
  fi
  if [[ ! -w $NODE_SOURCE_FILE ]]; then err "Source APT tidak dapat ditulis: $NODE_SOURCE_FILE"; return 1; fi
  NODE_SOURCE_BACKUP="$TMP/nodesource.original"
  cp -p -- "$NODE_SOURCE_FILE" "$NODE_SOURCE_BACKUP"
  sed -E "s|https?://deb\\.nodesource\\.com/node_[0-9]+\\.x|https://deb.nodesource.com/node_${NODE_LTS_MAJOR}.x|g" "$NODE_SOURCE_BACKUP" > "$TMP/nodesource.updated"
  if cmp -s "$TMP/nodesource.updated" "$NODE_SOURCE_BACKUP"; then
    err 'Repository NodeSource tidak berubah; format tidak dikenal.'
    return 1
  fi
  cat "$TMP/nodesource.updated" > "$NODE_SOURCE_FILE"
  NODE_SOURCE_SWITCHED=1
  log "NodeSource: cabang $old_major.x → $NODE_LTS_MAJOR.x (LTS; upgrade dari --apply)."
}

node_lts_install() {
  local candidate major rc
  candidate=$(awk '$1=="Candidate:" {print $2}' "$TMP/node-apt-policy")
  major=$(printf '%s\n' "${candidate#*:}" | awk -F'.' '$1~/^[0-9]+$/ {print $1}')
  if [[ $major != "$NODE_LTS_MAJOR" ]]; then
    err "NodeSource tidak menyediakan kandidat $NODE_LTS_MAJOR.x ($candidate). Repository akan dipulihkan."
    return 1
  fi
  if ! env DEBIAN_FRONTEND=noninteractive apt-get -s install nodejs > "$TMP/node-install-plan" 2>&1; then
    err 'Simulasi instalasi Node LTS gagal. Repository akan dipulihkan.'
    return 1
  fi
  if grep -q '^Remv ' "$TMP/node-install-plan"; then
    err 'Simulasi migrasi Node menunjukkan penghapusan paket lain; upgrade dibatalkan.'
    return 1
  fi
  # From this point dpkg may change the installed major; never restore the old repo blindly.
  NODE_MAJOR_INSTALLED=1
  if ! run_quiet 'Node LTS Upgrade' env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=l apt-get -qq -o DPkg::Lock::Timeout=60 -o Dpkg::Options::=--force-confold -y --only-upgrade install nodejs; then
    return 1
  fi
  major=$(/usr/bin/node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)
  if [[ $major != "$NODE_LTS_MAJOR" ]]; then
    err "Node.js sesudah instalasi bukan $NODE_LTS_MAJOR.x; periksa paket yang terpasang."
    NODE_MAJOR_INSTALLED=1  # leave new repository in place if package state is uncertain
    return 1
  fi
  NODE_MAJOR_INSTALLED=1
  ok "Node.js LTS $NODE_LTS_MAJOR.x terpasang; aplikasi akan divalidasi terpisah."
}

if [[ $MODE == apply ]]; then
  if [[ $ERRORS -ne 0 ]]; then err 'Baseline bermasalah; upgrade dibatalkan'; APPLY_ABORTED=1
  elif (( $(df -Pk / | awk 'NR==2 {print $4}') < 1048576 )); then
    err 'Free disk / < 1 GiB. Upgrade dibatalkan.'; APPLY_ABORTED=1
  elif command -v fuser >/dev/null 2>&1 && fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
    err 'APT/dpkg lock sedang digunakan. Upgrade dibatalkan.'; APPLY_ABORTED=1
  fi
  if ((APPLY_ABORTED==0)) && [[ $CONTAINER == no && $RESTART -eq 1 ]]; then
    if [[ -r /var/lib/dpkg/status ]]; then
      dpkg-query -W -f='${binary:Package}\t${Version}\n' > "$TMP/packages-before" 2>/dev/null || true
    fi
    if ! stop_managed; then APPLY_ABORTED=1; fi
  fi
  if ((APPLY_ABORTED==0)); then
    # Default --apply upgrades NodeSource-managed Node to production LTS.
    # Unmanaged applications are not terminated and remain pending restart.
    if ((NODE_LTS==0 && AUTO_LTS==1)) && [[ -x /usr/bin/node ]] &&
       dpkg-query -W -f='${Status}' nodejs 2>/dev/null | grep -q '^install ok installed$'; then
      if [[ -n $(grep -El 'deb\.nodesource\.com/node_[0-9]+\.x' /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true) ]]; then
        NODE_LTS=1
      else
        major_now=$(/usr/bin/node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)
        if [[ $major_now != "$NODE_LTS_MAJOR" ]]; then
          warn "Node $major_now.x tidak menggunakan repository NodeSource yang dikenali; migrasi LTS otomatis dilewati."
          NODE_LTS_SKIPPED=1
        fi
      fi
    fi
    # An unsupervised Node process is not reason to skip installing the requested
    # LTS runtime. It is, however, a reason NOT to claim the application migrated.
    if ((NODE_LTS==1)); then
      if ! prepare_nodesource_lts; then
        if ((AUTO_LTS==1)); then
          warn 'Migrasi NodeSource tidak tersedia. Upgrade APT reguler dilanjutkan.'
          NODE_LTS=0; NODE_LTS_SKIPPED=1
        else
          APPLY_ABORTED=1
        fi
      fi
    fi
  fi
  if ((APPLY_ABORTED==0)); then
    section 'APT UPDATE DAN UPGRADE'
    if [[ $CONTAINER == yes ]]; then warn 'Container APT mode enabled; no automatic service restarts in container'; fi
    if [[ -r /var/lib/dpkg/status ]]; then
      dpkg-query -W -f='${binary:Package}\t${Version}\n' > "$TMP/packages-before" 2>/dev/null || true
    fi
    # Resolve the APT candidate AFTER refreshing repository metadata.
    # Read the full apt-cache output into a temporary file: piping its output
    # into an early-exiting awk can raise SIGPIPE with `set -o pipefail`.
    # If the candidate cannot be checked for installed Node, fail safely.
    node_apt_major_check() {
      local installed candidate installed_major candidate_major error_message
      command -v dpkg-query >/dev/null 2>&1 || { err 'dpkg-query tidak tersedia; upgrade dibatalkan'; return 1; }
      installed=$(dpkg-query -W -f='${Version}' nodejs 2>/dev/null || true)
      if [[ -z $installed ]]; then
        log 'Node.js tidak dikelola paket APT: pemeriksaan major Node APT dilewati.'
        return 0
      fi
      command -v apt-cache >/dev/null 2>&1 || { err 'apt-cache tidak tersedia; upgrade dibatalkan'; return 1; }
      if ! apt-cache policy nodejs > "$TMP/node-apt-policy" 2> "$TMP/node-apt-policy-stderr"; then
        error_message=$(sed -n '1p' "$TMP/node-apt-policy-stderr")
        err "Gagal membaca apt-cache policy nodejs: ${error_message:-periksa konfigurasi repository APT}. Upgrade dibatalkan."
        return 1
      fi
      candidate=$(awk '$1=="Candidate:" {print $2}' "$TMP/node-apt-policy")
      if [[ -z $candidate || $candidate == '(none)' ]]; then
        warn "Node.js terpasang ($installed), tetapi kandidat APT tidak tersedia. Node tidak akan diperbarui oleh APT."
        return 0
      fi
      # Debian package versions may have an epoch (for example 2:22.2.0).
      installed_major=$(printf '%s\n' "${installed#*:}" | awk -F '.' '$1~/^[0-9]+$/ {print $1}')
      candidate_major=$(printf '%s\n' "${candidate#*:}" | awk -F '.' '$1~/^[0-9]+$/ {print $1}')
      if [[ -z $installed_major || -z $candidate_major ]]; then
        err "Tidak bisa membandingkan major Node APT: $installed -> $candidate. Upgrade dibatalkan."
        return 1
      fi
      log "Node APT: $installed -> $candidate (major $installed_major -> $candidate_major)"
      if [[ $installed_major != "$candidate_major" ]]; then
        if ((NODE_LTS == 1)) && [[ $candidate_major == "$NODE_LTS_MAJOR" ]]; then
          log "Node LTS: major $installed_major.x → $candidate_major.x diizinkan oleh kebijakan --apply."
        else
          err "Node APT kandidat major berbeda ($installed -> $candidate). Upgrade dibatalkan; review repo dahulu."
          return 1
        fi
      fi
      return 0
    }
    if run_quiet 'Apt Update' env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=l apt-get -qq -o DPkg::Lock::Timeout=60 update; then
      if node_apt_major_check && { ((NODE_LTS==0)) || node_lts_install; }; then
        if run_quiet 'Apt Upgrade' env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=l apt-get -qq -o DPkg::Lock::Timeout=60 -o Dpkg::Options::=--force-confold -y upgrade; then
          APT_RAN=1
        else
          APPLY_ABORTED=1
        fi
      else
        APPLY_ABORTED=1
      fi
    else
      APPLY_ABORTED=1
    fi
    dpkg-query -W -f='${binary:Package}\t${Version}\n' > "$TMP/packages-after" 2>/dev/null || true
    awk -F '\t' 'NR==FNR{v[$1]=$2;next} ($1 in v) && v[$1]!=$2 {print $1"|"v[$1]"|"$2}' "$TMP/packages-before" "$TMP/packages-after" > "$TMP/packages-changed"
    while IFS='|' read -r pkg v_old v_new; do
      case "$pkg" in
        php|php[0-9]*|libapache2-mod-php*) PHP_CHANGED=1 ;;
        nodejs) NODE_CHANGED=1 ;;
        nginx*|apache2*) WEB_CHANGED=1 ;;
      esac
    done < "$TMP/packages-changed"
  fi
else
  section 'MODE AUDIT: TANPA PERUBAHAN'
  ok 'Tidak menjalankan apt, mengubah versi runtime, atau restart aplikasi'
fi

# PHP latest stable: upgrade an existing CLI-only APT installation only when
# PHP 8.5 is already available from configured/trusted repositories. We never
# rewrite Nginx upstreams, Apache modules, or PHP-FPM pool/socket paths.
php_stable_cli_upgrade() {
  local oldver oldseries candidate oldmodules newmodules newbin oldbin oldreal pkg version wanted pkgname
  oldbin=$(command -v php 2>/dev/null || true)
  [[ -n $oldbin && -x $oldbin && -x /usr/bin/php ]] || return 0
  oldreal=$(readlink -f /usr/bin/php 2>/dev/null || true)
  oldver=$(/usr/bin/php -r 'echo PHP_VERSION;' 2>/dev/null || true)
  [[ $oldver =~ ^[0-9]+\.[0-9]+\. ]] || { warn 'PHP tidak berasal dari CLI APT yang dikenali; major upgrade dilewati.'; return 0; }
  oldseries=${oldver%.*}
  if [[ $oldseries == "$PHP_STABLE_SERIES" ]]; then
    log "PHP sudah di cabang $PHP_STABLE_SERIES; patch APT telah dijalankan."
    return 0
  fi
  if [[ $(printf '%s\n%s\n' "$PHP_STABLE_SERIES" "$oldseries" | sort -V | tail -n 1) == "$oldseries" ]]; then
    warn "PHP $oldver lebih baru daripada target stabil $PHP_STABLE_SERIES; tidak diturunkan otomatis."
    return 0
  fi
  # Do not rewire sites, queues, and extension-dependent FPM pools automatically.
  if grep -Eq '^php[0-9.]+-fpm\.service\|active$|^apache2\.service\|active$' "$TMP/services-before" ||
      grep -Eq '^libapache2-mod-php' "$TMP/packages-before"; then
    warn "PHP $oldver: upgrade major ke $PHP_STABLE_SERIES dilewati (PHP-FPM/Apache aktif atau mod_php). Perlu migrasi situs/socket dan ekstensi."
    return 0
  fi
  if grep -Eq '^php[^|]*\|' "$TMP/services-before" ||
     ps -eo comm= 2>/dev/null | grep -Eq '^php([0-9.]+)?$'; then
    warn "PHP $oldver: ada worker/proses PHP berjalan; migrasi major CLI perlu review."
    return 0
  fi
  if ! dpkg-query -W -f='${Status}' "php${oldseries}-cli" 2>/dev/null | grep -q '^install ok installed$'; then
    warn 'PHP CLI bukan paket versi APT yang dikenali; tidak memaksakan upgrade.'
    return 0
  fi
  if ! apt-cache policy "php${PHP_STABLE_SERIES}-cli" >"$TMP/php-target-policy" 2>/dev/null; then
    warn "APT tidak menyediakan PHP $PHP_STABLE_SERIES; tidak menambahkan repository pihak ketiga."
    return 0
  fi
  candidate=$(awk '$1=="Candidate:"{print $2}' "$TMP/php-target-policy")
  if [[ -z $candidate || $candidate == '(none)' ]]; then
    warn "PHP $PHP_STABLE_SERIES tidak ada di repository APT saat ini; upgrade major dilewati."
    return 0
  fi
  # Map versioned modules to the equivalent candidate version. Missing
  # extension packages cause a conservative skip, not partial migration.
  local -a installs=("php${PHP_STABLE_SERIES}-cli")
  while IFS= read -r pkgname; do
    [[ -n $pkgname ]] || continue
    wanted="php${PHP_STABLE_SERIES}-${pkgname#php${oldseries}-}"
    if [[ $wanted == "php${PHP_STABLE_SERIES}-cli" || $wanted == "php${PHP_STABLE_SERIES}-common" ]]; then continue; fi
    if [[ $wanted == *-fpm || $wanted == *-dev || $wanted == *-dbg || $wanted == *-phpdbg ]]; then
      warn "PHP extension/component $pkgname membutuhkan review; major CLI tidak dipindahkan."
      return 0
    fi
    candidate=$(apt-cache policy "$wanted" 2>/dev/null | awk '$1=="Candidate:" {print $2}')
    if [[ -z $candidate || $candidate == '(none)' ]]; then
      warn "PHP extension $pkgname tidak punya paket pengganti $wanted; upgrade major dilewati."
      return 0
    fi
    installs+=("$wanted")
  done < <(dpkg-query -W -f='${binary:Package}\n' "php${oldseries}-*" 2>/dev/null | grep -E "^php${oldseries//./\.}-" || true)
  if ! apt-get -s install "${installs[@]}" >"$TMP/php-upgrade-plan" 2>&1 || grep -q '^Remv ' "$TMP/php-upgrade-plan"; then
    warn "Rencana PHP $PHP_STABLE_SERIES memerlukan penghapusan paket atau gagal disimulasikan; dilewati."
    return 0
  fi
  oldmodules=$(/usr/bin/php -m 2>/dev/null | sed -n '/^\[PHP Modules\]/,/^\[Zend Modules\]/{/^\[/d;/^$/d;p;}' | sort -u)
  if ! run_quiet "PHP ${PHP_STABLE_SERIES} Install" env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=l apt-get -qq -y install "${installs[@]}"; then
    return 1
  fi
  newbin="/usr/bin/php${PHP_STABLE_SERIES}"
  if [[ ! -x $newbin ]]; then err "Binary $newbin tidak ditemukan"; return 1; fi
  # Installing a PHP release may automatically switch the default interpreter
  # in update-alternatives auto mode. Restore it until module validation passes.
  if [[ -n $oldreal && $oldreal != "$(readlink -f /usr/bin/php)" ]]; then
    if update-alternatives --list php 2>/dev/null | grep -Fxq "$oldreal"; then
      if ! run_quiet 'PHP Default Preserve' update-alternatives --set php "$oldreal"; then
        err "Gagal mempertahankan PHP default lama ($oldreal)."; return 1
      fi
    else
      err "Default PHP berubah setelah instalasi dan interpreter lama tidak ada di alternatives; perlu review manual."
      return 1
    fi
  fi
  newmodules=$($newbin -m 2>/dev/null | sed -n '/^\[PHP Modules\]/,/^\[Zend Modules\]/{/^\[/d;/^$/d;p;}' | sort -u)
  if [[ -n $(comm -23 <(printf '%s\n' "$oldmodules") <(printf '%s\n' "$newmodules")) ]]; then
    warn 'PHP baru belum memuat semua modul CLI lama; default CLI dipertahankan.'
    return 0
  fi
  if [[ $(readlink -f /usr/bin/php) == "$newbin" ]]; then
    PHP_MIGRATED=1
    ok "PHP CLI $oldver → $($newbin -r 'echo PHP_VERSION;')"
    return 0
  fi
  if [[ -L /usr/bin/php && $(readlink /usr/bin/php) == /etc/alternatives/php ]] &&
     update-alternatives --query php >"$TMP/php-alternatives" 2>/dev/null &&
     update-alternatives --list php 2>/dev/null | grep -Fxq "$newbin"; then
    if run_quiet 'PHP CLI Switch' update-alternatives --set php "$newbin"; then
      PHP_MIGRATED=1
      ok "PHP CLI $oldver → $(php -r 'echo PHP_VERSION;' 2>/dev/null || echo '?')"
    fi
  else
    warn 'PHP 8.5 terpasang tetapi default CLI tidak memakai update-alternatives; tidak mengubah symlink secara paksa.'
  fi
}

if [[ $MODE == apply && $APT_RAN -eq 1 && $CONTAINER == no && -s $TMP/php-before ]]; then
  section 'PHP STABLE AUTO UPGRADE'
  if ! php_stable_cli_upgrade; then
    APPLY_ABORTED=1
    err 'Upgrade PHP CLI gagal; periksa status paket sebelum melanjutkan.'
  fi
fi

# Optional NVM patch upgrade for user profiles with a resolvable default alias.
# NVM-managed live apps are deliberately NOT restarted: their PM2/systemd startup
# paths can point to an old interpreter until an operator validates/migrates them.
if [[ $MODE == apply && $APT_RAN -eq 1 && $UPDATE_NVM -eq 1 ]]; then
  section 'NVM UPDATE (OPT-IN, CABANG MAJOR TETAP)'
  updated_profiles=0
  while IFS=: read -r nuser _ nuid ngid ngecos nhome nshell; do
    [[ -f $nhome/.nvm/nvm.sh ]] || continue
    if ! command -v runuser >/dev/null 2>&1; then warn 'runuser tidak ditemukan: NVM profiles dilewati'; break; fi
    log "NVM user=$nuser: mencari default alias untuk update patch..."
    if runuser -u "$nuser" -- env HOME="$nhome" NVM_DIR="$nhome/.nvm" bash -c '
      set -euo pipefail
      . "$NVM_DIR/nvm.sh"
      current="$(nvm version default)"
      if [[ ! "$current" =~ ^v([0-9]+)\. ]]; then
        printf "SKIP: default alias tidak menunjuk versi major yang valid (%s)\n" "$current"
        exit 0
      fi
      major="${BASH_REMATCH[1]}"
      printf "NVM default: %s | update major %s.x\n" "$current" "$major"
      nvm install "$major"
      nvm alias default "$major"
    '; then
      ok "NVM operation $nuser selesai; verifikasi alias dan startup app"
      updated_profiles=$((updated_profiles+1))
    else
      err "NVM update gagal untuk user=$nuser"
    fi
  done < /etc/passwd
  if ((updated_profiles>0)); then
    NVM_UPDATED=1
    warn 'NVM: proses Node/PM2 mungkin masih memakai binary lama. Lakukan migrasi runtime dan restart app setelah verifikasi.'
  else
    warn 'Tidak ada profil ~/.nvm yang berhasil diproses. Instalasi NVM di lokasi custom perlu penanganan terpisah.'
  fi
fi

if [[ $MODE == apply ]]; then
  section 'START SERVICE PHP/NODE SETELAH UPGRADE'
  if (( STOP_PHASE_ENTERED == 1 )); then
    if ! bring_back_managed; then
      err 'Sebagian service gagal dihidupkan; periksa status secara manual.'
    fi
  elif (( RESTART==0 )); then
    warn 'Stop/start otomatis tidak dijalankan (--no-restart).'
  elif [[ $CONTAINER == yes ]]; then
    warn 'Container: stop/start service harus melalui orchestrator/redeploy image.'
  else
    log 'Tidak ada service yang dihentikan (maintenance dibatalkan sebelum tahap stop).'
  fi
  # Reload web server only if its own packages changed; PHP-FPM starts through snapshot.
  if (( WEB_CHANGED == 1 && APT_RAN == 1 && RESTART == 1 )) && [[ $CONTAINER == no ]]; then
    while IFS='|' read -r unit status; do
      [[ $status == active ]] || continue
      case "$unit" in
        nginx.service)
          if ! nginx -t >"$TMP/nginx-config.log" 2>&1 || ! run_quiet 'Reload nginx' systemctl reload nginx.service; then
            err 'Reload nginx gagal.'; RESTART_FAILED=1
          fi ;;
        apache2.service)
          if ! apache2ctl configtest >"$TMP/apache-config.log" 2>&1 || ! run_quiet 'Reload Apache' systemctl reload apache2.service; then
            err 'Reload Apache gagal.'; RESTART_FAILED=1
          fi ;;
      esac
    done < "$TMP/services-before"
  fi
fi

section 'VERIFIKASI VERSI DAN APLIKASI TERBARU'
version_snapshot "$TMP/php-after" php
version_snapshot "$TMP/node-after" node
nvm_snapshot "$TMP/nvm-after"
node_proc_inventory "$TMP/node-apps-after"
pm2_inventory "$TMP/pm2-after" after
if (( NODE_MAJOR_INSTALLED == 1 && NODE_CHANGED == 1 )) && [[ -s $TMP/pm2-before ]]; then
  while IFS='|' read -r u app status pid id bin; do
    [[ $status == online && $pid =~ ^[0-9]+$ ]] || continue
    # Only check PM2 workloads that previously ran under system Node.
    prior=$(node_exe "$pid")
    [[ $prior == /usr/bin/node* ]] || continue
    newpid=$(awk -F '|' -v user="$u" -v want="$id" '$1==user && $5==want{print $4;exit}' "$TMP/pm2-after")
    [[ $newpid =~ ^[0-9]+$ && $newpid -gt 0 ]] || { err "PM2 $u/$app: PID pascamigrasi tidak ditemukan"; continue; }
    liveexe=$(node_exe "$newpid")
    livever=$("/proc/$newpid/exe" -p 'process.versions.node' 2>/dev/null || true)
    live_major=${livever%%.*}
    if [[ $live_major != "$NODE_LTS_MAJOR" ]]; then
      err "PM2 $u/$app: runtime aktif ${livever:-N/A}, bukan Node $NODE_LTS_MAJOR LTS (binary: $liveexe)"
    else
      ok "PM2 $u/$app: proses memakai Node $livever"
    fi
  done < "$TMP/pm2-before"
fi
show_runtime "$TMP/php-after" 'PHP '
show_runtime "$TMP/node-after" 'Node'
if [[ -s $TMP/nvm-after ]]; then
  while IFS='|' read -r user path ver; do log "NVM $user $ver: $( ((UPDATE_NVM)) && echo 'update opt-in dijalankan; app runtime perlu diperiksa' || echo 'tidak di-upgrade otomatis')"; done < "$TMP/nvm-after"
fi
if (( EUID==0 )); then
  if command -v nginx >/dev/null 2>&1; then
    if nginx -t >"$TMP/nginx-config.log" 2>&1; then ok 'nginx config valid'; else err 'nginx config invalid'; fi
  fi
  if command -v apache2ctl >/dev/null 2>&1; then
    if apache2ctl configtest >"$TMP/apache-config.log" 2>&1; then ok 'Apache config valid'; else err 'Apache config invalid'; fi
  fi
else
  log 'Tes konfigurasi Nginx/Apache dilewati pada non-root (tidak berarti failed).'
fi
if [[ $CONTAINER == no && -x $(command -v systemctl || echo /no/such/file) ]]; then
  while IFS='|' read -r unit before; do
    [[ $before == active ]] || continue
    after=$(systemctl is-active "$unit" 2>/dev/null || echo unknown)
    if [[ $after == active ]]; then ok "Service $unit: active"; else err "Service $unit: $before -> $after"; fi
  done < "$TMP/services-before"
fi

# Compare the application inventory from before maintenance. We explicitly check
# process/service liveness only: without app-specific probes, functional health
# (database access, endpoints, queue throughput) cannot be guaranteed.
section 'VALIDASI APLIKASI (TANPA FILE KONFIGURASI)'
APP_OK=0
APP_FAIL=0
APP_UNVERIFIED=0
while IFS='|' read -r user name before pid id bin; do
  [[ -n $user ]] || continue
  if [[ $before == online ]]; then
    after=$(awk -F '|' -v u="$user" -v id="$id" '$1==u && $5==id {print $3;exit}' "$TMP/pm2-after")
    if [[ $after == online ]]; then
      ok "PM2 $user/$name: online setelah pemeriksaan"
      APP_OK=$((APP_OK+1))
    else
      err "PM2 $user/$name: sebelumnya online, sekarang ${after:-tidak ditemukan}"
      APP_FAIL=$((APP_FAIL+1))
    fi
  else
    log "PM2 $user/$name: status awal $before (tidak diasumsikan sehat)"
    APP_UNVERIFIED=$((APP_UNVERIFIED+1))
  fi
done < "$TMP/pm2-before"
# Count Node systemd services once per unit, even if multiple worker PIDs exist.
while IFS='|' read -r user name before; do
  [[ -n $name ]] || continue
  if [[ $before == active ]]; then
    after=$(awk -F '|' -v u="$user" -v n="$name" '$1=="systemd" && $2==u && $3==n {print $4;exit}' "$TMP/node-apps-after")
    if [[ $after == active ]]; then
      ok "Node systemd $name: active dan proses Node terdeteksi"
      APP_OK=$((APP_OK+1))
    else
      err "Node systemd $name: sebelumnya active, sekarang ${after:-proses tidak terdeteksi}"
      APP_FAIL=$((APP_FAIL+1))
    fi
  else
    log "Node systemd $name: status awal $before (tidak diasumsikan sehat)"
    APP_UNVERIFIED=$((APP_UNVERIFIED+1))
  fi
done < <(awk -F '|' '$1=="systemd" {k=$2 FS $3; if (!seen[k]++) print $2 "|" $3 "|" $4}' "$TMP/node-apps-before")
while IFS='|' read -r manager user name before pid exe; do
  [[ $manager == process ]] || continue
  # Exclude PM2-managed PIDs, which are checked above.
  if [[ -s $TMP/pm2-before ]] && awk -F '|' -v p="$pid" '$4==p {found=1} END {exit !found}' "$TMP/pm2-before"; then continue; fi
  if awk -F '|' -v u="$user" -v n="$name" '$1=="process" && $2==u && $3==n {found=1} END {exit !found}' "$TMP/node-apps-after"; then
    if ((NODE_CHANGED)) && [[ $exe == /usr/bin/node* ]]; then
      # Check matching active PID and executable to avoid claiming the old
      # running process has switched interpreter after /usr/bin/node is replaced.
      matching_pid=$(awk -F '|' -v u="$user" -v n="$name" '$1=="process" && $2==u && $3==n {print $5;exit}' "$TMP/node-apps-after")
      if [[ $matching_pid == "$pid" || $(readlink "/proc/$matching_pid/exe" 2>/dev/null || true) == *' (deleted)' ]]; then
        warn "Node process $user/$name PID=$pid masih memakai runtime lama; restart manual diperlukan."
        UNMANAGED_NODE_POST=$((UNMANAGED_NODE_POST+1))
        APP_UNVERIFIED=$((APP_UNVERIFIED+1))
      else
        ok "Node process $user/$name: proses berubah (status proses saja)"
        APP_OK=$((APP_OK+1))
      fi
    else
      ok "Node process $user/$name: proses masih terdeteksi"
      APP_OK=$((APP_OK+1))
    fi
  else
    err "Node process $user/$name: proses tidak ditemukan lagi"
    APP_FAIL=$((APP_FAIL+1))
  fi
done < "$TMP/node-apps-before"
log "Validasi proses: $APP_OK aktif / $APP_FAIL gagal / $APP_UNVERIFIED tidak terverifikasi; HTTP tidak diperiksa."

section 'RINGKASAN AKHIR — COPY/PASTE'
primary_version() {
  local path=$1 primary=$2 r
  r=$(awk -F '|' -v want="$primary" '$1==want{print $2;exit}' "$path")
  if [[ -z $r ]]; then r=$(awk -F '|' 'NR==1{print $2;exit}' "$path"); fi
  printf '%s' "${r:-N/A}"
}
PHP_OLD=$(primary_version "$TMP/php-before" /usr/bin/php)
PHP_NEW=$(primary_version "$TMP/php-after" /usr/bin/php)
if [[ $MODE == apply && $PHP_OLD != N/A && $CONTAINER == no ]]; then
  if [[ $PHP_NEW != "${PHP_STABLE_SERIES}."* ]]; then
    warn "PHP terpasang tetapi belum mencapai target ${PHP_STABLE_SERIES}.x ($PHP_OLD -> $PHP_NEW). Periksa repository/ekstensi/FPM."
    RUNTIME_TARGET_FAILED=1
  fi
fi
CURRENT_NODE_PATH=$(command -v node 2>/dev/null || echo /usr/bin/node)
NODE_OLD=$(primary_version "$TMP/node-before" "$CURRENT_NODE_PATH")
NODE_NEW=$(primary_version "$TMP/node-after" "$CURRENT_NODE_PATH")
if [[ $MODE == apply && -x /usr/bin/node && $CONTAINER == no && $NODE_NEW =~ ^v[0-9]+ ]]; then
  installed_major=${NODE_NEW#v}; installed_major=${installed_major%%.*}
  if (( installed_major < NODE_LTS_MAJOR )); then
    warn "Node.js belum mencapai target LTS ${NODE_LTS_MAJOR}.x: ${NODE_OLD} -> ${NODE_NEW}. Periksa sumber instalasi dan repository."
    RUNTIME_TARGET_FAILED=1
  fi
fi
NODE_APPS_COUNT=0
RESTART_OK=$(grep -c '|OK|' "$TMP/restart-results" || true)
RESTART_FAIL=$(grep -c '|FAIL|' "$TMP/restart-results" || true)
printf 'Hostname          : %s\n' "$(hostname)"
printf 'Pengguna login    : %s\n' "$ORIGINAL_USER"
printf 'Pengguna efektif  : %s\n' "$EXEC_USER"
printf 'IP lokal          : %s\nIP publik (egress): %s\n' "$LOCAL_IP" "$PUBLIC_IP"
printf 'CPU               : %s%% (%s)\n' "$CPU_USED" "$CPU_VIEW"
printf 'RAM               : %s / %s GiB used | %s GiB available\n' "$(gib "$MEM_USED")" "$(gib "$MEM_TOTAL")" "$(gib "$MEM_AVAIL")"
printf 'Disk %-12s : %s / %s GiB used | %s GiB free\n' "$DISK_PATH" "$(gib "$DISK_USED")" "$(gib "$DISK_TOTAL")" "$(gib "$DISK_AVAIL")"
printf 'PHP               : %s -> %s\n' "$PHP_OLD" "$PHP_NEW"
printf 'Node.js (%s): %s -> %s\n' "$CURRENT_NODE_PATH" "$NODE_OLD" "$NODE_NEW"
if ((UNMANAGED_NODE_POST>0)); then printf 'Node apps pending  : %s perlu restart manual (runtime lama masih berjalan)\n' "$UNMANAGED_NODE_POST"; fi
if [[ -s $TMP/nvm-after ]]; then printf 'NVM installations : %s detected (not necessarily active)\n' "$(wc -l < "$TMP/nvm-after")"; fi
log 'Aplikasi Node.js (PM2 / systemd / proses):'
if [[ -s $TMP/pm2-after ]]; then
  while IFS='|' read -r user name status pid id bin; do
    printf '  • PM2     %-18s %-28s %-15s PID=%s\n' "$user" "$name" "$status" "$pid"
    NODE_APPS_COUNT=$((NODE_APPS_COUNT+1))
  done < "$TMP/pm2-after"
fi
if [[ -s $TMP/node-apps-after ]]; then
  while IFS='|' read -r manager user name status pid exe; do
    # No double count of same PID if already listed under PM2.
    if [[ -s $TMP/pm2-after ]] && awk -F '|' -v needle="$pid" '$4==needle {found=1} END {exit !found}' "$TMP/pm2-after"; then continue; fi
    printf '  • %-7s %-18s %-28s %-15s PID=%s\n' "$manager" "$user" "$name" "$status" "$pid"
    NODE_APPS_COUNT=$((NODE_APPS_COUNT+1))
  done < "$TMP/node-apps-after"
fi
((NODE_APPS_COUNT>0)) || printf '  (tidak ditemukan / akses terbatas / ada di Docker/Kubernetes)\n'
printf 'Node app terdeteksi: %s (best-effort, bukan inventaris lengkap)\n' "$NODE_APPS_COUNT"
printf 'Status aplikasi    : %s aktif / %s gagal / %s unverified (proses saja)\n' "$APP_OK" "$APP_FAIL" "$APP_UNVERIFIED"
printf 'Restart terkait   : %s OK / %s FAIL\n' "$RESTART_OK" "$RESTART_FAIL"
if [[ -f /run/reboot-required ]]; then warn 'Server memerlukan reboot (tidak dilakukan otomatis)'; fi
if ((ERRORS>0 || APPLY_ABORTED==1 || RUNTIME_TARGET_FAILED==1)); then RESULT='FAIL'
elif ((WARN>0 || APP_UNVERIFIED>0)); then RESULT='REVIEW'
else RESULT='PASS'; fi
printf 'PERINGATAN        : %s | ERROR: %s\n' "$WARN" "$ERRORS"
printf 'HASIL             : %s\n' "$RESULT"
log 'Keterangan: active/online hanya memastikan proses berjalan; fungsi HTTP/DB/queue tidak diuji.'
log 'Tidak ada log/JSON diunggah atau disimpan permanen oleh skrip.'
if [[ $RESULT == FAIL ]]; then exit 2; fi
