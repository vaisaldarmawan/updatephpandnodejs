#!/usr/bin/env bash
# Ubuntu Maintenance — terminal-only audit / same-release package upgrades
# Intended for reviewed, trusted hosts. No network upload, external telemetry, or stored reports.
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_VERSION='0.3.3'
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

usage() {
cat <<'HELP'
Ubuntu Maintenance v0.3.3 — terminal-only (no report upload or saved logs)

  bash ubuntu-maintenance-v03.sh --audit             # regular user or root
  sudo bash ubuntu-maintenance-v03.sh --audit        # fuller host inventory
  sudo bash ubuntu-maintenance-v03.sh --apply        # apt upgrade + targeted restart
  bash ubuntu-maintenance-v03.sh --demo              # simulated terminal view

Options:
  --audit                 Read-only inventory (default), supports non-root/container
  --apply                 apt-get update && apt-get upgrade (Ubuntu, root only)
  --allow-container-apply Explicitly permit APT inside container (no auto restarts)
  --update-nvm            Update NVM default Node within its existing major (root, opt-in)
  --no-restart            Do not automatically restart affected services/PM2 apps
  --no-public-ip          Never contact an external IP lookup endpoint
  --disk-path PATH        Filesystem to report (default /)
  --demo                  Simulated, fictional output; no system operations
  -h, --help              Show this help

Important:
* APT updates installed Ubuntu-managed PHP/Node packages, NOT NVM/asdf/fnm,
  Docker images, or binaries installed manually. Major version changes require review.
* Apply needs no configuration file; post-upgrade verification checks process/systemd/PM2 status, not HTTP functionality.
* No automatic reboot, rollback, or container orchestration actions.
* apt-get itself can restart services before our controlled restart phase.
* Only terminal text is output; an internal temporary directory is removed on exit.
HELP
}

demo() {
cat <<'DEMO'
╔════════════════════════════════════════════════════════════════════╗
║  UBUNTU MAINTENANCE v0.3.3 • SIMULASI (BUKAN HASIL SERVER ASLI)   ║
╚════════════════════════════════════════════════════════════════════╝
[15:08:21] Mode              : APPLY
[15:08:21] Hostname          : prod-api-01
[15:08:21] OS                : Ubuntu 24.04 LTS
[15:08:21] Pengguna login    : deploy
[15:08:21] Pengguna efektif  : root (via sudo)
[15:08:21] Lingkungan        : Host / VM
[15:08:21] IP lokal          : 192.168.10.20
[15:08:21] IP publik (egress): 203.0.113.20
[15:08:21] CPU               : 12.8% terpakai | 8 vCPU | load 0.64 / 0.71 / 0.83
[15:08:21] RAM               : 3.20 GiB terpakai / 8.00 GiB total (4.80 GiB available)
[15:08:21] Disk /            : 42.00 GiB terpakai / 100.00 GiB total (58.00 GiB free)

──── [01] RUNTIME AWAL ────
[15:08:22] ✓ PHP   /usr/bin/php     : 8.3.34
[15:08:22] ✓ Node  /usr/bin/node    : v22.23.2
[15:08:22] ✓ NVM ditemukan (deploy): runtime dikelola terpisah

──── [02] APLIKASI / BASELINE ────
[15:08:23] ✓ systemd  api.service        active    /usr/bin/node
[15:08:23] ✓ pm2      webhook (deploy)   online    PID 8812
[15:08:23] ✓ php-fpm  php8.3-fpm.service active
[15:08:23] ✓ baseline api.service aktif dan webhook PM2 online

──── [03] PEMBARUAN PAKET ────
[15:08:25] ⠋ apt-get update ... (output APT tetap ditampilkan)
[15:08:35] ✓ apt-get update berhasil
[15:08:36] ⠙ apt-get upgrade ... (output APT tetap ditampilkan)
[15:08:57] ✓ apt-get upgrade berhasil

──── [04] RESTART TERARAH ────
[15:08:58] ✓ php8.3-fpm.service : restart berhasil; active
[15:09:01] ✓ api.service        : restart berhasil; active
[15:09:04] ✓ pm2 deploy/webhook : reload berhasil; online
[15:09:05] ✓ Verifikasi proses : systemd active; PM2 online

╔═══════════════════ RINGKASAN ═════════════════════════════════════╗
  Login / eksekusi   : deploy / root
  IP lokal / publik  : 192.168.10.20 / 203.0.113.20
  PHP               : 8.3.34 -> 8.3.36
  Node.js (APT)     : v22.23.2 -> v22.23.4
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
log "CPU               : $CPU_USED% terpakai ($CPU_VIEW) | $CPU_CORES logical CPU | load 1/5/15: $LOADAVG"
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
  (( count>0 )) || log "$label: tidak ditemukan pada path host standar"
}

# Commands that produce useful live output; do not hide APT output.
run_live() {
  local description=$1; shift
  log "$description"
  # No background command, so output stays in chronological order and visible.
  # Spinner is on the left before each phase, while APT progress remains native.
  if [[ -t 1 ]]; then printf '  ↻ %s (output langsung)\n' "$description"; fi
  if "$@"; then ok "$description berhasil"; return 0
  else err "$description gagal"; return 1; fi
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

if [[ $MODE == apply ]]; then
  if [[ $ERRORS -ne 0 ]]; then err 'Baseline bermasalah; upgrade dibatalkan'; APPLY_ABORTED=1
  elif (( $(df -Pk / | awk 'NR==2 {print $4}') < 1048576 )); then
    err 'Free disk / < 1 GiB. Upgrade dibatalkan.'; APPLY_ABORTED=1
  elif command -v fuser >/dev/null 2>&1 && fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
    err 'APT/dpkg lock sedang digunakan. Upgrade dibatalkan.'; APPLY_ABORTED=1
  fi
  if ((APPLY_ABORTED==0)); then
    section 'APT UPDATE DAN UPGRADE (OUTPUT LANGSUNG)'
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
        err "Node APT kandidat major berbeda ($installed -> $candidate). Upgrade dibatalkan; review repo dahulu."
        return 1
      fi
      return 0
    }
    if run_live 'apt-get update' env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=l apt-get -o DPkg::Lock::Timeout=60 update; then
      if node_apt_major_check; then
        if run_live 'apt-get upgrade (paket mungkin memicu restart sendiri)' env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=l apt-get -o DPkg::Lock::Timeout=60 -o Dpkg::Options::=--force-confold -y upgrade; then
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

restart_record() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$TMP/restart-results"; }
if [[ $MODE == apply && $APT_RAN -eq 1 && $RESTART -eq 1 && $CONTAINER == no ]]; then
  section 'RESTART SERVICE YANG TERDAMPAK'
  : > "$TMP/restart-candidates"
  if ((PHP_CHANGED)); then
    awk -F '|' '$1 ~ /^php[0-9.]+-fpm\.service$/ {print $1}' "$TMP/services-before" >> "$TMP/restart-candidates"
    if grep -q '^libapache2-mod-php' "$TMP/packages-changed"; then
      printf 'apache2.service\n' >> "$TMP/restart-candidates"
    fi
    # PHP CLI workers (artisan queue, cron-managed daemons) with a systemd unit.
    while IFS=' ' read -r pid user comm; do
      [[ $pid =~ ^[0-9]+$ && $comm =~ ^php([0-9.]+)?$ ]] || continue
      unit=$(service_for_pid "$pid")
      [[ $unit == *.service ]] && printf '%s\n' "$unit" >> "$TMP/restart-candidates"
    done < <(ps -eo pid=,user=,comm= -ww 2>/dev/null || true)
  fi
  if ((WEB_CHANGED)); then
    awk -F '|' '$1=="nginx.service" || $1=="apache2.service" {print $1}' "$TMP/services-before" >> "$TMP/restart-candidates"
  fi
  if ((NODE_CHANGED)); then
    while IFS='|' read -r manager user name status pid exe; do
      [[ $manager == systemd && $exe == /usr/bin/node* ]] && printf '%s\n' "$name" >> "$TMP/restart-candidates"
    done < "$TMP/node-apps-before"
  fi
  awk 'NF && !seen[$0]++ {print}' "$TMP/restart-candidates" > "$TMP/restart-candidates-unique"
  # PHP workers first, then custom Node services, then web frontends.
  awk '{p=2;if($0 ~ /^php[0-9.]+-fpm\.service$/)p=0;else if($0 !~ /^(nginx|apache2)\.service$/)p=1;print p"|"$0}' "$TMP/restart-candidates-unique" | sort -t '|' -k1,1n | cut -d '|' -f2- > "$TMP/restart-candidates"
  while IFS= read -r unit; do
    [[ $unit =~ ^[A-Za-z0-9_.@-]+\.service$ ]] || continue
    status_before=$(awk -F '|' -v u="$unit" '$1==u{print $2;exit}' "$TMP/services-before")
    [[ $status_before == active ]] || { warn "$unit: skip (sebelum upgrade bukan active)"; restart_record "$unit" SKIP 'not previously active'; continue; }
    if [[ $unit == nginx.service ]] && command -v nginx >/dev/null 2>&1 && ! nginx -t; then err "nginx -t gagal; skip restart $unit"; restart_record "$unit" FAIL config; RESTART_FAILED=1; break; fi
    if [[ $unit == apache2.service ]] && command -v apache2ctl >/dev/null 2>&1 && ! apache2ctl configtest; then err "apache configtest gagal; skip restart $unit"; restart_record "$unit" FAIL config; RESTART_FAILED=1; break; fi
    log "Restart $unit ..."
    if systemctl try-restart "$unit" && systemctl is-active --quiet "$unit"; then
      ok "$unit: active setelah restart"; restart_record "$unit" OK active
    else err "$unit: restart gagal"; restart_record "$unit" FAIL restart; RESTART_FAILED=1; break; fi
  done < "$TMP/restart-candidates"

  # PM2 only for apps whose live Node executable WAS apt-managed (/usr/bin/node).
  # Never reload all apps, and don't wake stopped apps.
  if ((NODE_CHANGED && RESTART_FAILED==0)) && [[ -s $TMP/pm2-before ]]; then
    while IFS='|' read -r user name status pid id bin; do
      [[ $status == online && $pid =~ ^[0-9]+$ && $id =~ ^[0-9]+$ ]] || continue
      exe=$(node_exe "$pid")
      [[ $exe == /usr/bin/node* ]] || { warn "PM2 $user/$name tidak menggunakan Node APT: review/restart manual"; continue; }
      home=$(getent passwd "$user" | cut -d: -f6)
      [[ -n $home && -x $bin ]] || continue
      log "Reload PM2 $user/$name (id=$id) ..."
      if timeout 60 runuser -u "$user" -- env HOME="$home" PM2_HOME="$home/.pm2" PATH="$(dirname "$bin"):$PATH" "$bin" reload "$id"; then
        ok "PM2 $user/$name: reload selesai"; restart_record "pm2:$user/$name" OK online
      else err "PM2 $user/$name: gagal"; restart_record "pm2:$user/$name" FAIL reload; RESTART_FAILED=1; break; fi
    done < "$TMP/pm2-before"
  fi
  # A bare Node process cannot be safely restarted without knowing its supervisor.
  # Make this visible; a binary can be updated while the existing process stays old.
  if ((NODE_CHANGED)); then
    while IFS='|' read -r manager user name status pid exe; do
      [[ $manager == process && $exe == /usr/bin/node* ]] || continue
      if [[ -s $TMP/pm2-before ]] && awk -F '|' -v p="$pid" '$4==p {f=1} END {exit !f}' "$TMP/pm2-before"; then continue; fi
      warn "Node process $user/$name (PID $pid) tidak memiliki supervisor teridentifikasi; restart manual diperlukan agar memakai Node baru."
    done < "$TMP/node-apps-before"
  fi
  [[ -s $TMP/restart-results ]] || log 'Tidak ada restart yang diperlukan / terverifikasi aman.'
elif [[ $MODE == apply ]]; then
  section 'RESTART SERVICE'
  if ((RESTART==0)); then warn 'Restart dimatikan (--no-restart); aplikasi dapat memakai runtime lama'
  elif [[ $CONTAINER == yes ]]; then warn 'Container: restart otomatis dimatikan; rebuild/redeploy image untuk produksi'
  elif ((APT_RAN==0)); then warn 'APT tidak selesai; restart otomatis dilewati'; fi
fi

section 'VERIFIKASI VERSI DAN APLIKASI TERBARU'
version_snapshot "$TMP/php-after" php
version_snapshot "$TMP/node-after" node
nvm_snapshot "$TMP/nvm-after"
node_proc_inventory "$TMP/node-apps-after"
pm2_inventory "$TMP/pm2-after" after
show_runtime "$TMP/php-after" 'PHP '
show_runtime "$TMP/node-after" 'Node'
if [[ -s $TMP/nvm-after ]]; then
  while IFS='|' read -r user path ver; do log "NVM $user $ver: $( ((UPDATE_NVM)) && echo 'update opt-in dijalankan; app runtime perlu diperiksa' || echo 'tidak di-upgrade otomatis')"; done < "$TMP/nvm-after"
fi
if (( EUID==0 )); then
  if command -v nginx >/dev/null 2>&1; then
    if nginx -t 2>&1; then ok 'nginx config valid'; else err 'nginx config invalid'; fi
  fi
  if command -v apache2ctl >/dev/null 2>&1; then
    if apache2ctl configtest 2>&1; then ok 'Apache config valid'; else err 'Apache config invalid'; fi
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
    ok "Node process $user/$name: proses masih terdeteksi"
    APP_OK=$((APP_OK+1))
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
  printf '%s' "${r:-tidak terpasang / tidak ditemukan}"
}
PHP_OLD=$(primary_version "$TMP/php-before" /usr/bin/php)
PHP_NEW=$(primary_version "$TMP/php-after" /usr/bin/php)
CURRENT_NODE_PATH=$(command -v node 2>/dev/null || echo /usr/bin/node)
NODE_OLD=$(primary_version "$TMP/node-before" "$CURRENT_NODE_PATH")
NODE_NEW=$(primary_version "$TMP/node-after" "$CURRENT_NODE_PATH")
NODE_APPS_COUNT=0
RESTART_OK=$(grep -c '|OK|' "$TMP/restart-results" || true)
RESTART_FAIL=$(grep -c '|FAIL|' "$TMP/restart-results" || true)
printf 'Hostname          : %s\n' "$(hostname)"
printf 'Pengguna login    : %s\n' "$ORIGINAL_USER"
printf 'Pengguna efektif  : %s\n' "$EXEC_USER"
printf 'Mode / lingkungan : %s / %s\n' "$MODE" "$([[ $CONTAINER == yes ]] && echo container || echo host)"
printf 'IP lokal          : %s\nIP publik (egress): %s\n' "$LOCAL_IP" "$PUBLIC_IP"
printf 'CPU               : %s%% (%s), load: %s\n' "$CPU_USED" "$CPU_VIEW" "$LOADAVG"
printf 'RAM               : %s / %s GiB used | %s GiB available\n' "$(gib "$MEM_USED")" "$(gib "$MEM_TOTAL")" "$(gib "$MEM_AVAIL")"
printf 'Disk %-12s : %s / %s GiB used | %s GiB free\n' "$DISK_PATH" "$(gib "$DISK_USED")" "$(gib "$DISK_TOTAL")" "$(gib "$DISK_AVAIL")"
printf 'PHP               : %s -> %s\n' "$PHP_OLD" "$PHP_NEW"
printf 'Node.js (%s): %s -> %s\n' "$CURRENT_NODE_PATH" "$NODE_OLD" "$NODE_NEW"
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
if ((ERRORS>0 || APPLY_ABORTED==1)); then RESULT='FAIL'
elif ((WARN>0 || APP_UNVERIFIED>0)); then RESULT='REVIEW'
else RESULT='PASS'; fi
printf 'PERINGATAN        : %s | ERROR: %s\n' "$WARN" "$ERRORS"
printf 'HASIL             : %s\n' "$RESULT"
log 'Keterangan: active/online hanya memastikan proses berjalan; fungsi HTTP/DB/queue tidak diuji.'
log 'Tidak ada log/JSON diunggah atau disimpan permanen oleh skrip.'
if [[ $RESULT == FAIL ]]; then exit 2; fi
