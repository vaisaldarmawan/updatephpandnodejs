#!/usr/bin/env bash
# Ubuntu Maintenance — terminal-only audit, runtime upgrades, lifecycle verification
# Intended for reviewed, trusted hosts. No network upload, external telemetry, or stored reports.
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_VERSION='0.5.1'
MODE='audit'
RUNTIME_ONLY=0
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
PM2_DISCOVERY_INCOMPLETE=0
APPLY_ABORTED=0
NVM_PRESENT=0
NODE_LTS=0
AUTO_LTS=1
NODE_LTS_MAJOR=24
NODE_RELEASE='24.22.1'
NODE_APT_HOLD_ADDED=0
NODE_DIRECT_INSTALLED=0
NODE_DIRECT_TRANSACTION=0
NODE_DIRECT_PATHS=()
NODE_DIRECT_DIVERTED=()
NODE_DIRECT_OLD_LINKS=()
PHP_STABLE_SERIES='8.5'
PHP_MIGRATED=0
PHP_APACHE_SWITCHED=0
PHP_APACHE_ROLLED_BACK=0
PHP_APACHE_OLD_SERIES=''
PHP_APACHE_WAS_ENABLED=0
NODE_LTS_SKIPPED=0
UNMANAGED_NODE_UPGRADE=0
UNMANAGED_NODE_POST=0
RUNTIME_TARGET_FAILED=0
NODE_SOURCE_FILE=''
NODE_SOURCE_BACKUP=''
NODE_SOURCE_SWITCHED=0
NODE_NEW_REPO=0
NODE_REPO_CREATED_PATHS=()
NODE_REPO_BACKUP_PATHS=()
NODE_REPO_BACKUP_FILES=()
NODE_LTS_APT_ARGS=('nodejs')
NODE_APT_ALLOWED_REMOVALS=()
NODE_MAJOR_INSTALLED=0
START_PHASE_DONE=0
STOP_PHASE_ENTERED=0
CHECK_URLS=()
WEB_HEALTH_FAIL=0
WEB_HEALTH_WARN=0
WEB_PROBE_PASS=0
WEB_PROBE_FAIL=0
FORCE_UNMANAGED=0
FORCE_UNMANAGED_COUNT=0

usage() {
cat <<'HELP'
Ubuntu Maintenance v0.5.1 — terminal-only (no report upload or saved logs)

  bash ubuntu-maintenance-v0.5.1.sh --audit             # regular user or root
  sudo bash ubuntu-maintenance-v0.5.1.sh --audit        # fuller host inventory
  bash ubuntu-maintenance-v0.5.1.sh --demo              # simulated terminal view
  sudo bash ubuntu-maintenance-v0.5.1.sh --apply        # stop managed apps, upgrade runtimes, start and verify

Options:
  --audit                 Read-only inventory (default), supports non-root/container
  --apply                 Stop managed PHP/Node apps, upgrade runtimes, start apps, verify
  --allow-container-apply Explicitly permit APT inside container (no auto restarts)
  --update-nvm            Update NVM default within its existing major (optional)
  --node-lts              Require Node 24 LTS installation from official binary
  --runtime-only          Skip general apt-get update/upgrade; Node uses direct official binary. PHP (if installed) still needs APT/PPA.
  --no-restart            Skip automatic PHP/Node stop/start and local web-server restart
  --force-restart-unmanaged
                         Force stop/start standalone Node processes using original
                         user, argv, cwd and environment; may detach Screen/Tmux
                         sessions; use only with approved downtime and backup.
  --no-public-ip          Never contact an external IP lookup endpoint
  --check-url URL         Check an HTTP(S) endpoint before/after (repeatable)
                         Example: --check-url http://10.0.0.126:3000/
  --disk-path PATH        Filesystem to report (default /)
  --demo                  Simulated, fictional output; no system operations
  -h, --help              Show this help

Important:
* Node upgrades from an official nodejs.org Linux binary (verified SHA256), NOT APT; Ubuntu's webpack/eslint/terser packages are left installed. The original /usr/bin/node (and npm/npx where present) is protected with dpkg-divert, allowing restoration. Container images, NVM/asdf/fnm installations are not overwritten.
* PHP 8.5 uses signed apt packages (ppa:ondrej/php on supported Ubuntu if needed), because upstream does not distribute a universal production Linux PHP-FPM binary. PHP FPM/socket migrations are not automatically assumed safe.
* Root manages PM2 as each owning user with its own HOME/PM2_HOME (not the root PM2 list). PM2 installations with custom PM2_HOME need manual handling.
* Managed PHP/Node systemd services and online PM2 apps are stopped before changing packages and started afterward, including recovery attempts on failure. Local active Nginx/Apache is restarted after apps start, if its configuration test passes.
* --force-restart-unmanaged (explicit opt-in) captures startup argv/cwd/env for standalone Node apps, terminates them and starts detached copies as the original user. This CHANGES Screen/Tmux behavior and redirects future stdout/stderr to /dev/null; interactive apps, dynamic startup wrappers and nonpersistent dependencies can fail. If metadata cannot be captured, the script aborts before stopping any app. Prefer systemd/PM2 for production.
* A process with /proc/PID/exe marked (deleted), or an executable inode different from the current binary, is reported STALE on every run (audit and apply), including when APT changed no packages.
* PHP 8.5 CLI + available matching extensions are installed using APT (ppa:ondrej/php if needed). OPcache is built into PHP 8.5 (no php8.5-opcache package). Enabled Apache mod_php is switched with configtest and rollback on failure; FPM virtual hosts are NOT blindly rewritten. Third-party PPA may use provider-specific changes/telemetry.
* Apply needs no configuration file; HTTP GET is checked on identified local TCP ports and optional --check-url values. HTTP response checks do not guarantee database/queue functionality. During the stop→start window, monitored applications may be unavailable.
* No automatic reboot, complete runtime rollback, or container orchestration actions. Review changed systemd interpreter paths and PHP virtual hosts.
* apt-get itself can restart services before our controlled restart phase.
* Only terminal text is output; an internal temporary directory is removed on exit.
HELP
}

demo() {
cat <<'DEMO'
╔════════════════════════════════════════════════════════════════════╗
║  UBUNTU MAINTENANCE v0.5.1 • SIMULASI (BUKAN HASIL SERVER ASLI)   ║
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

──── [03] WEB / PORT AKTIF ────
[15:08:23] ✓ Web node:api: http://192.168.10.20:3000/ [HTTP 200]
[15:08:23] ✓ Web custom (--check-url): http://10.0.0.126:3000/ [HTTP 200]

──── [04] STOP SERVICE (YANG SEBELUMNYA AKTIF) ────
[15:08:24] Stop php8.5-fpm.service   [done]
[15:08:25] Stop api.service          [done]
[15:08:26] Stop PM2 deploy/webhook   [done]
[15:08:27] Stop Node deploy/admin    [done] (opsional: --force-restart-unmanaged)

──── [05] UPGRADE RUNTIME & PAKET ────
[15:08:43] Apt Update               [done]
[15:08:38] Node Official Download     [done]
[15:08:39] Node SHA256 Check         [done]
[15:08:41] Node Binary Activate      [done]
[15:08:53] Apt Upgrade              [done]
[15:08:59] PHP Stable Check         [done]

──── [06] START SERVICE & VERIFIKASI ────
[15:09:03] Start php8.5-fpm.service  [done]
[15:09:05] Start api.service         [done]
[15:09:08] Start PM2 deploy/webhook  [done]
[15:09:09] Start Node deploy/admin   [done] (opsional)
[15:09:09] Restart nginx.service    [done]
[15:09:10] Verifikasi proses        [done]

╔═══════════════════ RINGKASAN ═════════════════════════════════════╗
  Login / eksekusi   : deploy / root
  IP lokal / publik  : 192.168.10.20 / 203.0.113.20
  PHP               : 8.5.12 -> 8.5.12
  Node.js           : v20.20.2 -> v24.22.1
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
    --runtime-only) RUNTIME_ONLY=1 ;;
    --no-restart) RESTART=0 ;;
    --force-restart-unmanaged) FORCE_UNMANAGED=1 ;;
    --no-public-ip) PUBLIC_IP_LOOKUP=0 ;;
    --check-url)
      (( $# >= 2 )) || { printf 'Missing URL after --check-url\n' >&2; exit 64; }
      CHECK_URLS+=("$2")
      shift ;;
    --disk-path)
      (( $# >= 2 )) || { printf 'Argument missing for %s\n' "$1" >&2; exit 64; }
      DISK_PATH=$2
      shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done
for weburl in "${CHECK_URLS[@]}"; do
  if [[ ! $weburl =~ ^https?://[^/[:space:]@\|]+(/[^[:space:]\|]*)?$ || $weburl == *'@'* ]]; then
    printf 'Invalid --check-url (use an HTTP/HTTPS address without credentials): %s\n' "$weburl" >&2
    exit 64
  fi
done
if ((FORCE_UNMANAGED)) && { [[ $MODE != apply ]] || ((RESTART==0)); }; then
  printf '%s\n' '--force-restart-unmanaged requires --apply without --no-restart' >&2
  exit 64
fi
if ((RUNTIME_ONLY)) && [[ $MODE != apply ]]; then
  printf '%s\n' '--runtime-only requires --apply' >&2
  exit 64
fi
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
  if ((NODE_APT_HOLD_ADDED == 1)); then
    apt-mark unhold nodejs >/dev/null 2>&1 || printf 'WARNING: gagal unhold nodejs; jalankan apt-mark unhold nodejs\n' >&2
  fi
  if ((NODE_DIRECT_TRANSACTION == 1 && NODE_DIRECT_INSTALLED == 0)); then
    printf '[RECOVERY] Memulihkan Node binary yang tidak selesai diaktifkan...\n' >&2
    for ((j=${#NODE_DIRECT_PATHS[@]}-1; j>=0; j--)); do
      path=${NODE_DIRECT_PATHS[j]}
      rm -f -- "$path"
      if [[ ${NODE_DIRECT_DIVERTED[j]} == yes ]]; then
        dpkg-divert --local --rename --remove "$path" >/dev/null 2>&1 || printf 'WARNING: diversion %s perlu diperbaiki manual\n' "$path" >&2
      elif [[ -n ${NODE_DIRECT_OLD_LINKS[j]} ]]; then
        ln -s "${NODE_DIRECT_OLD_LINKS[j]}" "$path" || true
      fi
    done
  fi
  if (( NODE_MAJOR_INSTALLED == 0 )); then
    if (( NODE_SOURCE_SWITCHED == 1 )) && [[ -n $NODE_SOURCE_FILE && -f $NODE_SOURCE_BACKUP ]]; then
      cp -p -- "$NODE_SOURCE_BACKUP" "$NODE_SOURCE_FILE" || printf 'WARNING: gagal mengembalikan sumber NodeSource %s\n' "$NODE_SOURCE_FILE" >&2
    fi
    if (( NODE_NEW_REPO == 1 )); then
      for path in "${NODE_REPO_CREATED_PATHS[@]}"; do
        rm -f -- "$path" || printf 'WARNING: gagal membersihkan %s\n' "$path" >&2
      done
      for i in "${!NODE_REPO_BACKUP_PATHS[@]}"; do
        cp -p -- "${NODE_REPO_BACKUP_FILES[$i]}" "${NODE_REPO_BACKUP_PATHS[$i]}" || printf 'WARNING: gagal memulihkan %s\n' "${NODE_REPO_BACKUP_PATHS[$i]}" >&2
      done
    fi
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
if ((FORCE_UNMANAGED)) && [[ $CONTAINER == yes ]]; then
  err '--force-restart-unmanaged tidak didukung di dalam container; gunakan orchestrator.'
  exit 2
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
: > "$TMP/web-endpoints"; : > "$TMP/web-before"; : > "$TMP/web-after"

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

# Process runtime checks never invoke the application or print its arguments.
# Compare the executable inode (device + inode), not just the path or APT delta.
# A running process can keep an unlinked Node ELF in memory after upgrades.
proc_user() {
  local uid
  uid=$(stat -c %u "/proc/$1" 2>/dev/null || true)
  [[ $uid =~ ^[0-9]+$ ]] || return 1
  getent passwd "$uid" | cut -d: -f1
}
node_exe() {
  local pid=$1 result owner
  result=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
  if [[ -z $result && $EUID -eq 0 ]]; then
    owner=$(proc_user "$pid" || true)
    if [[ -n $owner ]]; then
      result=$(runuser -u "$owner" -- readlink "/proc/$pid/exe" 2>/dev/null || true)
    fi
  fi
  printf '%s' "$result"
}
node_cwd() {
  local pid=$1 result owner
  result=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
  if [[ -z $result && $EUID -eq 0 ]]; then
    owner=$(proc_user "$pid" || true)
    if [[ -n $owner ]]; then result=$(runuser -u "$owner" -- readlink "/proc/$pid/cwd" 2>/dev/null || true); fi
  fi
  printf '%s' "$result"
}
node_runtime_state() {
  local pid=$1 exe path process_inode current_inode owner
  [[ $pid =~ ^[0-9]+$ && -L /proc/$pid/exe ]] || { printf 'missing'; return 0; }
  exe=$(node_exe "$pid")
  [[ -n $exe ]] || { printf 'unknown'; return 0; }
  if [[ $exe == *' (deleted)' ]]; then printf 'stale'; return 0; fi
  path=$exe
  [[ -e $path ]] || { printf 'stale'; return 0; }
  process_inode=$(stat -Lc '%d:%i' "/proc/$pid/exe" 2>/dev/null || true)
  if [[ -z $process_inode && $EUID -eq 0 ]]; then
    owner=$(proc_user "$pid" || true)
    if [[ -n $owner ]]; then process_inode=$(runuser -u "$owner" -- stat -Lc '%d:%i' "/proc/$pid/exe" 2>/dev/null || true); fi
  fi
  current_inode=$(stat -Lc '%d:%i' "$path" 2>/dev/null || true)
  if [[ -z $process_inode || -z $current_inode ]]; then
    printf 'unknown'
  elif [[ $process_inode == "$current_inode" ]]; then
    printf 'current'
  else
    printf 'stale'
  fi
}
# Only describe common parent supervisors; do not infer a safe startup command.
node_parent_manager() {
  local pid=$1 next cmd step
  for ((step=0; step<10; step++)); do
    next=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    [[ $next =~ ^[0-9]+$ && $next -gt 1 && $next != "$pid" ]] || break
    cmd=$(ps -o comm= -p "$next" 2>/dev/null || true)
    case "$cmd" in
      screen|SCREEN) printf 'screen'; return 0 ;;
      tmux|tmux\:*) printf 'tmux'; return 0 ;;
      supervisord) printf 'supervisord'; return 0 ;;
    esac
    pid=$next
  done
  printf 'unknown'
}
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
    cwd=$(node_cwd "$pid")
    # A Node process living under cron.service is normally a cron JOB, not
    # a Node application supervised by systemd. Restarting cron won't restart
    # an already-running job (and can disrupt unrelated scheduled tasks).
    case "$unit" in
      cron.service|crond.service|atd.service|ssh.service|sshd.service|systemd-*.service|user@*.service|dbus.service|containerd.service|docker.service)
        unit='' ;;
    esac
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
  for x in "$home"/.npm-global/bin/pm2 "$home"/.local/bin/pm2 "$home"/.local/share/pnpm/pm2 "$home"/.nvm/versions/node/v*/bin/pm2 /usr/bin/pm2 /usr/local/bin/pm2; do
    [[ -x $x ]] && { printf '%s' "$x"; return; }
  done
  return 1
}

pm2_inventory() {
  local target=$1 phase=$2 username unused uid gid gecos home shell pid bin raw parsed
  : > "$target"
  command -v python3 >/dev/null 2>&1 || { warn 'Python3 tidak tersedia: PM2 app discovery terbatas.'; PM2_DISCOVERY_INCOMPLETE=1; return; }
  while IFS=: read -r username unused uid gid gecos home shell; do
    [[ -r $home/.pm2/pm2.pid ]] || continue
    if ((EUID!=0)) && [[ $username != "$EXEC_USER" ]]; then continue; fi
    pid=$(cat "$home/.pm2/pm2.pid" 2>/dev/null || true)
    [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null || continue
    bin=$(pm2_for_home "$home" || true)
    if [[ -z $bin ]]; then
      warn "PM2 daemon user=$username terdeteksi, tetapi executable PM2 tidak ditemukan."
      PM2_DISCOVERY_INCOMPLETE=1
      continue
    fi
    raw="$TMP/pm2-${phase}-${username}.json"
    # Avoid pm2 starting daemons when none exist; existing pid was checked.
    if ((EUID==0)); then
      timeout 10 runuser -u "$username" -- env HOME="$home" PM2_HOME="$home/.pm2" PATH="$(dirname "$bin"):$PATH" "$bin" jlist > "$raw" 2>/dev/null || true
    else
      timeout 10 env PM2_HOME="$home/.pm2" PATH="$(dirname "$bin"):$PATH" "$bin" jlist > "$raw" 2>/dev/null || true
    fi
    if [[ ! -s $raw ]]; then
      warn "PM2 user=$username terdeteksi tetapi inventaris aplikasi tidak dapat dibaca."
      PM2_DISCOVERY_INCOMPLETE=1
      continue
    fi
    parsed="$TMP/pm2-${phase}-${username}.parsed"
    if python3 - "$raw" "$username" "$bin" > "$parsed" <<'PY'
import json,sys
try:
    with open(sys.argv[1]) as f: apps=json.load(f)
except (ValueError,OSError):
    sys.exit(3)
if not isinstance(apps,list):
    sys.exit(3)
for app in apps:
    if not isinstance(app,dict):
        sys.exit(3)
    e=app.get('pm2_env') or {}
    name=str(app.get('name') or 'unnamed').replace('|','/').replace('\n',' ')[:80]
    status=str(e.get('status') or 'unknown')[:24]
    pid=app.get('pid') or 0
    pm_id=app.get('pm_id')
    if not isinstance(pid,int): pid=0
    if not isinstance(pm_id,int): continue
    print('|'.join((sys.argv[2], name, status, str(pid), str(pm_id), sys.argv[3])))
PY
    then
      cat "$parsed" >> "$target"
    else
      warn "PM2 user=$username mengembalikan JSON tidak valid; daftar aplikasinya tidak aman untuk diubah."
      PM2_DISCOVERY_INCOMPLETE=1
    fi
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
  while IFS='|' read -r manager user name status pid exe; do
    state=$(node_runtime_state "$pid")
    if [[ $state == stale ]]; then
      warn "Node [$manager] user=$user app=$name PID=$pid: EXECUTABLE LAMA (deleted/inode berubah). Restart diperlukan; runtime=${exe:-N/A}"
    elif [[ $state == current ]]; then
      log "Node [$manager] user=$user app=$name status=$status PID=$pid runtime=${exe:-unknown} [runtime sesuai]"
    else
      warn "Node [$manager] user=$user app=$name status=$status PID=$pid: executable tidak bisa diverifikasi (${state})."
    fi
  done < "$TMP/node-apps-before"
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

# Capture only TCP listeners tied to Node/PHP and HTTP reverse proxies.
# No network-wide port scan and no guessing remote services.
web_discover() {
  local source_file="$TMP/ss-before" url clean_label
  : > "$TMP/web-endpoints"
  if command -v ss >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    ss -H -ltnp > "$source_file" 2>/dev/null || true
    python3 - "$source_file" "$TMP/node-apps-before" "$TMP/web-endpoints" "$LOCAL_IP" <<'PYWEB'
import re, sys, ipaddress
from pathlib import Path
socket_file, app_file, out_file = map(Path, sys.argv[1:4])
local_ip = sys.argv[4]
try:
    ipaddress.IPv4Address(local_ip)
except ValueError:
    local_ip = ''
node_by_pid = {}
for line in app_file.read_text(errors='replace').splitlines():
    parts = line.split('|')
    if len(parts) >= 5 and parts[4].isdigit():
        node_by_pid[parts[4]] = parts[2]
items, seen = [], set()
for line in socket_file.read_text(errors='replace').splitlines():
    fields = line.split()
    if len(fields) < 4:
        continue
    address = fields[3]
    m = re.search(r':(\d+)$', address)
    if not m or not local_ip:
        continue
    port = int(m.group(1))
    if not (0 < port <= 65535):
        continue
    pids = re.findall(r'pid=(\d+)', line)
    procnames = re.findall(r'"([^"\\]+)"\s*,\s*pid=', line)
    nodepid = next((pid for pid in pids if pid in node_by_pid), '')
    kind = ('node' if nodepid else
            'nginx' if any(x.startswith('nginx') for x in procnames) else
            'apache' if any(x in ('apache2','httpd') for x in procnames) else
            'php' if any(x.startswith('php-fpm') or x.startswith('php') for x in procnames) else '')
    if not kind:
        continue
    if kind in ('nginx', 'apache') and port not in (80, 443, 8080, 8443):
        continue
    bound = address[:m.start()].strip('[]')
    # Never claim a localhost-only listener is reachable through the LAN IP.
    if bound in ('127.0.0.1', '::1', 'localhost') or bound.startswith('127.'):
        continue
    if bound not in ('0.0.0.0', '*', '::', local_ip):
        continue
    label = (f'node:{node_by_pid[nodepid]}' if nodepid else kind)
    label = label.replace('|','/').replace('\n',' ')[:70]
    key = (kind, port, label)
    if key in seen:
        continue
    seen.add(key)
    scheme = 'https' if port in (443, 8443) else 'http'
    url = f'{scheme}://{local_ip}:{port}/'
    items.append(f'auto|{label}|{url}|{address}|{port}')
with out_file.open('a') as out:
    for item in items[:20]:
        out.write(item+'\n')
PYWEB
  fi
  for url in "${CHECK_URLS[@]}"; do
    if ! awk -F '|' -v target="$url" '$3==target {found=1} END{exit !found}' "$TMP/web-endpoints"; then
      printf 'manual|custom|%s|N/A|N/A\n' "$url" >> "$TMP/web-endpoints"
    fi
  done
}

# HTTP GET to root or explicit path; do not follow redirects, use proxies, or
# send secrets/HTTP request bodies. HTTP >=400 is not automatically 'offline'.
web_probe() {
  local target=$1 phase=$2 source label url addr port code rc state attempt idx=0
  : > "$target"
  while IFS='|' read -r source label url addr port; do
    [[ -n $url ]] || continue
    idx=$((idx+1))
    code='000'; rc=1; attempt=1
    local tries=1
    [[ $phase == AFTER && $MODE == apply ]] && tries=3
    for ((attempt=1;attempt<=tries;attempt++)); do
      if command -v curl >/dev/null 2>&1; then
        # IP-based HTTPS availability probe: ignore cert name mismatch.
        # It does not validate certificate trust.
        local -a tls_opts=()
        if [[ $source == auto && $url == https://* ]]; then tls_opts=(-k); fi
        if code=$(curl --noproxy '*' "${tls_opts[@]}" -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 4 --max-redirs 0 "$url" 2>/dev/null); then
          rc=0
          [[ $code =~ ^[0-9]{3}$ ]] || code=000
        else
          rc=$?; code=000
        fi
      else
        code=000; rc=127
      fi
      [[ $rc == 0 && $code != 000 ]] && break
      if (( attempt < tries )); then sleep 1; fi
    done
    if [[ $phase == AFTER && $source == auto && -f $TMP/ss-after ]] && ! awk -v addr="$addr" '$4==addr {found=1} END{exit !found}' "$TMP/ss-after"; then
      state='PORT_CLOSED'; code=000
    elif [[ $code =~ ^[23][0-9][0-9]$ ]]; then state='HTTP_OK'
    elif [[ $code == 401 || $code == 403 ]]; then state='AUTH'
    elif [[ $code =~ ^[45][0-9][0-9]$ ]]; then state='HTTP_ERROR'
    else state='NO_HTTP'; fi
    printf '%s|%s|%s|%s|%s\n' "$idx" "$url" "$source" "$state" "$code" >> "$target"
    case "$state" in
      HTTP_OK) ok "Web $label : $url [HTTP $code]" ;;
      AUTH) log "Web $label : $url [HTTP $code, akses dibatasi]" ;;
      HTTP_ERROR) warn "Web $label : $url [HTTP $code, aplikasi merespons error]" ;;
      PORT_CLOSED) err "Web $label : $url [port tidak lagi LISTEN]" ;; 
      NO_HTTP) log "Web $label : $url [tidak ada respons HTTP; mungkin port non-HTTP/firewall]" ;;
    esac
  done < "$TMP/web-endpoints"
}

web_compare() {
  local idx url source state code old oldstate oldcode
  local healthy=0 restricted=0 failed=0 unknown=0
  while IFS='|' read -r idx url source state code; do
    [[ -n $idx ]] || continue
    old=$(awk -F '|' -v id="$idx" '$1==id{print $4"|"$5;exit}' "$TMP/web-before")
    oldstate=${old%%|*}; oldcode=${old#*|}
    case "$state" in
      HTTP_OK) healthy=$((healthy+1)) ;;
      AUTH) restricted=$((restricted+1)) ;;
      PORT_CLOSED)
        failed=$((failed+1))
        WEB_HEALTH_FAIL=$((WEB_HEALTH_FAIL+1))
        ;;
      HTTP_ERROR)
        failed=$((failed+1))
        if [[ $source == manual || $oldstate == HTTP_OK || $oldstate == AUTH ]]; then
          err "Web gagal: $url sebelum=$oldcode sesudah=$code"
          WEB_HEALTH_FAIL=$((WEB_HEALTH_FAIL+1))
        else
          warn "Web $url: HTTP $code; perlu pemeriksaan aplikasi"
          WEB_HEALTH_WARN=$((WEB_HEALTH_WARN+1))
        fi ;;
      *)
        unknown=$((unknown+1))
        if [[ $source == manual || $oldstate == HTTP_OK || $oldstate == AUTH ]]; then
          err "Web tidak merespons: $url (sebelum ${oldcode:-000}, sesudah 000)"
          WEB_HEALTH_FAIL=$((WEB_HEALTH_FAIL+1))
        else
          warn "Web $url: port terdeteksi, tetapi HTTP belum terverifikasi"
          WEB_HEALTH_WARN=$((WEB_HEALTH_WARN+1))
        fi ;;
    esac
  done < "$TMP/web-after"
  WEB_PROBE_PASS=$((healthy+restricted))
  WEB_PROBE_FAIL=$((failed+unknown))
  log "HTTP URL: $healthy OK / $restricted dibatasi / $failed error / $unknown tidak terverifikasi."
}

section 'WEB / PORT AKTIF (SEBELUM PERUBAHAN)'
web_discover
if [[ -s $TMP/web-endpoints ]]; then
  web_probe "$TMP/web-before" BEFORE
else
  log 'Tidak menemukan port TCP yang dapat dipetakan; gunakan --check-url URL untuk pemeriksaan tambahan.'
fi

section 'BASELINE SERVICE / PROSES'
log 'Baseline dicatat otomatis dari systemd, PM2, dan proses Node.js.'
log 'Tidak perlu konfigurasi tambahan. Status proses saja tidak menjamin fungsi API/DB/queue.'

restart_record() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$TMP/restart-results"; }

# Validate active local web servers BEFORE stopping applications. Never restart
# an invalid configuration just because a runtime was upgraded.
web_preflight() {
  local unit status check
  [[ $CONTAINER == no && $RESTART -eq 1 ]] || return 0
  while IFS='|' read -r unit status; do
    [[ $status == active ]] || continue
    case "$unit" in
      nginx.service)
        check=nginx
        if ! command -v "$check" >/dev/null 2>&1 || ! "$check" -t >"$TMP/web-preflight-nginx.log" 2>&1; then
          err "Konfigurasi nginx tidak valid: proses upgrade dibatalkan sebelum stop service."
          return 1
        fi
        ;;
      apache2.service)
        check=apache2ctl
        if ! command -v "$check" >/dev/null 2>&1 || ! "$check" configtest >"$TMP/web-preflight-apache.log" 2>&1; then
          err "Konfigurasi Apache tidak valid: proses upgrade dibatalkan sebelum stop service."
          return 1
        fi
        ;;
    esac
  done < "$TMP/services-before"
  return 0
}

# A --check-url may target ANOTHER host; we never restart that remote machine.
# Only web servers locally active at baseline are restarted here.
restart_local_web() {
  local unit status check validation_args
  [[ $CONTAINER == no && $RESTART -eq 1 && $APT_RAN -eq 1 ]] || return 0
  section 'RESTART WEB SERVER LOKAL'
  local found=0 failure=0
  while IFS='|' read -r unit status; do
    [[ $status == active ]] || continue
    case "$unit" in nginx.service|apache2.service) ;; *) continue ;; esac
    found=1
    # Apache with mod_php may already be included in the stop/start plan.
    # Avoid performing a second restart of a service just recovered.
    if [[ -s $TMP/stopped-services ]] && grep -Fxq -- "$unit" "$TMP/stopped-services"; then
      ok "$unit sudah direstart lewat siklus stop/start sebelumnya."
      continue
    fi
    if [[ $unit == nginx.service ]]; then
      if ! command -v nginx >/dev/null 2>&1 || ! nginx -t >"$TMP/nginx-config.log" 2>&1; then
        err "Restart $unit dibatalkan: konfigurasi Nginx tidak valid."
        restart_record "$unit" FAIL config
        failure=1
        continue
      fi
    else
      if ! command -v apache2ctl >/dev/null 2>&1 || ! apache2ctl configtest >"$TMP/apache-config.log" 2>&1; then
        err "Restart $unit dibatalkan: konfigurasi Apache tidak valid."
        restart_record "$unit" FAIL config
        failure=1
        continue
      fi
    fi
    if run_quiet "Restart $unit" systemctl restart "$unit" && systemctl is-active --quiet "$unit"; then
      restart_record "$unit" OK active
    else
      err "$unit gagal restart atau tidak active."
      restart_record "$unit" FAIL restart
      failure=1
    fi
  done < "$TMP/services-before"
  if (( found == 0 )); then log 'Nginx/Apache tidak aktif sebelumnya; tidak ada web server lokal yang direstart.'; fi
  if (( failure )); then RESTART_FAILED=1; return 1; fi
  return 0
}


# The helper runs only as root, preserves the process owner and original
# cwd/arguments/environment (stored in private temporary JSON), and refuses to
# stop processes if the startup information cannot be reconstructed.
# A forced unmanaged restart is explicitly opted into; it is NOT a replacement
# for a persistent systemd/PM2 service.
cat > "$TMP/restart-standalone.py" <<'PYRESTART'
import json, os, pwd, signal, subprocess, sys, time
from pathlib import Path


def fail(message):
    print('ERROR: ' + message, file=sys.stderr)
    raise SystemExit(1)


def stat_info(pid):
    try:
        data = Path(f'/proc/{pid}/stat').read_text()
        rest = data[data.rfind(')')+2:].split()
        return rest[19], rest[0]  # starttime, state
    except (OSError, ValueError, IndexError):
        return None, None


def capture(pid, out):
    if pid < 2:
        fail('PID tidak valid')
    proc = Path(f'/proc/{pid}')
    try:
        uid = proc.stat().st_uid
        pw = pwd.getpwuid(uid)
        comm = (proc / 'comm').read_text().strip()
        try:
            exe = os.readlink(proc / 'exe').removesuffix(' (deleted)')
            cwd = os.readlink(proc / 'cwd')
            argv_raw = (proc/'cmdline').read_bytes()
            environ_raw = (proc/'environ').read_bytes()
        except PermissionError:
            # Some kernels deny even root /proc/*/environ when CAP_SYS_PTRACE
            # is unavailable. The process owner may still inspect itself.
            read_as_owner = r"""
import json,os,sys
from pathlib import Path
p=Path('/proc')/sys.argv[1]
x={'exe':os.readlink(p/'exe'),'cwd':os.readlink(p/'cwd'),
   'argv':(p/'cmdline').read_bytes().decode('utf-8','surrogateescape'),
   'env':(p/'environ').read_bytes().decode('utf-8','surrogateescape')}
print(json.dumps(x,ensure_ascii=True))
"""
            output=subprocess.check_output(
                ['runuser','-u',pw.pw_name,'--','python3','-c',read_as_owner,str(pid)],
                stderr=subprocess.DEVNULL, timeout=6)
            info=json.loads(output)
            exe=info['exe'].removesuffix(' (deleted)')
            cwd=info['cwd']
            argv_raw=info['argv'].encode('utf-8','surrogateescape')
            environ_raw=info['env'].encode('utf-8','surrogateescape')
        argv = [x.decode('utf-8', 'surrogateescape') for x in argv_raw.split(b'\0') if x]
        environ = {}
        for part in environ_raw.split(b'\0'):
            if b'=' in part:
                k,v=part.split(b'=',1)
                environ[k.decode('utf-8','surrogateescape')]=v.decode('utf-8','surrogateescape')
        start, state = stat_info(pid)
    except (OSError, KeyError, subprocess.SubprocessError, ValueError) as e:
        fail(f'gagal membaca metadata PID {pid}: {e.__class__.__name__}')
    if comm not in ('node','nodejs','npm') or not argv or not start:
        fail(f'PID {pid} tidak memiliki metadata proses Node yang valid')
    if not os.path.isdir(cwd) or not os.access(exe, os.X_OK):
        fail(f'direktori kerja atau executable Node tidak tersedia untuk PID {pid}')
    if not os.path.isfile(exe):
        fail('Node executable tidak ditemukan')
    if not Path('/usr/bin/node').exists() or exe != '/usr/bin/node':
        fail(f'Node bukan executable APT /usr/bin/node ({exe}); restart otomatis ditolak')
    if any('\0' in x for x in argv) or not environ:
        fail('argumen atau environment asli tidak valid')
    spec=dict(pid=pid, uid=uid, gid=pw.pw_gid, user=pw.pw_name,
              exe=exe, argv=argv, cwd=cwd, env=environ, start=start)
    with open(out, 'w') as f:
        json.dump(spec, f, ensure_ascii=True)
    os.chmod(out, 0o600)
    print(f'Prepared user={pw.pw_name} PID={pid} cwd={cwd}')


def load(path):
    with open(path) as f:
        return json.load(f)


def stop(path):
    spec=load(path)
    pid=spec['pid']; start,state=stat_info(pid)
    if start != spec['start']:
        fail(f'PID {pid} berubah sejak snapshot; tidak dihentikan')
    os.kill(pid, signal.SIGTERM)
    for _ in range(60):
        start,state=stat_info(pid)
        if start != spec['start'] or state in ('Z','X'):
            print(f'Stopped PID={pid} (SIGTERM)'); return
        time.sleep(0.1)
    start,state=stat_info(pid)
    if start == spec['start'] and state not in ('Z','X'):
        os.kill(pid, signal.SIGKILL)
    for _ in range(30):
        start,state=stat_info(pid)
        if start != spec['start'] or state in ('Z','X'):
            print(f'Stopped PID={pid} (forced)'); return
        time.sleep(0.1)
    fail(f'PID {pid} belum berhenti setelah SIGKILL')


def start(path):
    spec=load(path)
    if not os.path.isdir(spec['cwd']) or not os.access(spec['exe'], os.X_OK):
        fail('cwd atau binary Node tidak tersedia setelah upgrade')
    if stat_info(spec['pid'])[0] == spec['start'] and stat_info(spec['pid'])[1] not in ('Z','X'):
        fail('proses lama masih hidup; tidak membuat duplikat')
    pw=pwd.getpwuid(spec['uid'])
    def drop():
        if os.geteuid() == 0:
            os.initgroups(pw.pw_name, pw.pw_gid)
            os.setgid(pw.pw_gid)
            os.setuid(pw.pw_uid)
    try:
        with open(os.devnull, 'rb') as stdin, open(os.devnull, 'ab') as stdout:
            child=subprocess.Popen(spec['argv'], executable=spec['exe'],
                cwd=spec['cwd'], env=spec['env'], start_new_session=True,
                stdin=stdin, stdout=stdout, stderr=subprocess.STDOUT,
                close_fds=True, preexec_fn=drop)
        time.sleep(1.25)
        if child.poll() is not None:
            fail(f'Node process baru exit cepat (code {child.returncode}); periksa kompatibilitas aplikasi')
        try:
            exe=os.readlink(f'/proc/{child.pid}/exe')
            exe_inode=os.stat(f'/proc/{child.pid}/exe').st_ino
        except PermissionError:
            inspect = "import os,sys; p='/proc/'+sys.argv[1]+'/exe'; print(os.readlink(p)); print(os.stat(p).st_ino)"
            lines=subprocess.check_output(['runuser','-u',pw.pw_name,'--','python3','-c',inspect,str(child.pid)],
                                          stderr=subprocess.DEVNULL, timeout=5).decode().splitlines()
            exe,exe_inode=lines[0],int(lines[1])
        if exe.endswith(' (deleted)') or exe_inode != os.stat(spec['exe']).st_ino:
            fail('proses baru masih menggunakan binary Node lama')
        print(f'Started user={pw.pw_name} PID={child.pid} with current Node')
    except (OSError, subprocess.SubprocessError) as e:
        fail(f'proses tidak dapat dijalankan ulang: {e.__class__.__name__}: {e}')


if __name__ == '__main__':
    if len(sys.argv) != 4 or sys.argv[1] not in ('capture','stop','start'):
        fail('expected capture|stop|start PID|spec-file spec-file')
    if sys.argv[1] == 'capture':
        capture(int(sys.argv[2]), sys.argv[3])
    elif sys.argv[1] == 'stop':
        stop(sys.argv[3])
    else:
        start(sys.argv[3])
PYRESTART

# Snapshot-driven lifecycle. Services managed by systemd/PM2 use their original
# supervisors. Standalone Node is changed only with explicit force opt-in.
: > "$TMP/stopped-services"
: > "$TMP/stopped-pm2"
: > "$TMP/stop-plan-services"
: > "$TMP/stop-plan-pm2"
: > "$TMP/stopped-unmanaged"
: > "$TMP/force-prepared"

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
    case "$unit" in cron.service|crond.service|atd.service|ssh.service|sshd.service|docker.service|containerd.service|dbus.service|systemd-*.service) continue ;; esac
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
  local unit user name id bin home spec mgr status pid exe
  (( RESTART == 1 )) && [[ $CONTAINER == no ]] || return 0
  section 'STOP SERVICE PHP/NODE SEBELUM UPGRADE'
  if ! managed_stop_plan; then return 1; fi
  if ((FORCE_UNMANAGED)); then
    command -v python3 >/dev/null 2>&1 || { err 'Python3 wajib untuk --force-restart-unmanaged'; return 1; }
    : > "$TMP/force-prepared"
    while IFS='|' read -r mgr user name status pid exe; do
      [[ $mgr == process && $pid =~ ^[0-9]+$ ]] || continue
      if [[ -s $TMP/pm2-before ]] && awk -F '|' -v p="$pid" '$4==p {f=1} END{exit !f}' "$TMP/pm2-before"; then continue; fi
      spec="$TMP/standalone-$pid.json"
      if python3 "$TMP/restart-standalone.py" capture "$pid" "$spec" > "$TMP/capture-$pid.log" 2>&1; then
        printf '%s|%s|%s|%s\n' "$user" "$name" "$pid" "$spec" >> "$TMP/force-prepared"
      else
        err "Restart paksa $user/$name PID=$pid tidak aman: $(tail -n 1 "$TMP/capture-$pid.log")"
        return 1
      fi
    done < "$TMP/node-apps-before"
    if [[ -s $TMP/force-prepared ]]; then
      warn 'Force restart proses mandiri: aplikasi akan dilepas dari Screen/Tmux; stdout/stderr dialihkan ke /dev/null.'
    fi
  fi
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
  if ((FORCE_UNMANAGED)); then
    while IFS='|' read -r user name pid spec; do
      [[ -n $pid ]] || continue
      # Add to recovery list BEFORE sending signals.
      printf '%s|%s|%s|%s\n' "$user" "$name" "$pid" "$spec" >> "$TMP/stopped-unmanaged"
      if ! run_quiet "Stop Node $user/$name PID=$pid" python3 "$TMP/restart-standalone.py" stop unused "$spec"; then
        err "Gagal stop $user/$name; recovery start akan dicoba bila proses sudah berhenti."
        return 1
      fi
    done < "$TMP/force-prepared"
  fi
  if [[ ! -s $TMP/stopped-services && ! -s $TMP/stopped-pm2 && ! -s $TMP/stopped-unmanaged ]]; then
    log 'Tidak ada PHP/Node service terkelola yang perlu dihentikan.'
  fi
  # Unsupervised runtime processes cannot be restarted reliably.
  while IFS='|' read -r mgr user name status pid exe; do
    [[ $mgr == process ]] || continue
    if awk -F '|' -v p="$pid" '$4==p {f=1} END{exit !f}' "$TMP/pm2-before"; then continue; fi
    if ((FORCE_UNMANAGED)); then continue; fi
    warn "Proses mandiri $user/$name (PID $pid) tidak dihentikan: jalankan --force-restart-unmanaged untuk percobaan restart paksa."
  done < "$TMP/node-apps-before"
  return 0
}

bring_back_managed() {
  local unit user name id bin home pid spec failure=0
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
  if [[ -s $TMP/stopped-unmanaged ]]; then
    while IFS='|' read -r user name pid spec; do
      [[ -n $pid ]] || continue
      if run_quiet "Start Node $user/$name" python3 "$TMP/restart-standalone.py" start unused "$spec"; then
        restart_record "process:$user/$name" OK relaunched
        FORCE_UNMANAGED_COUNT=$((FORCE_UNMANAGED_COUNT+1))
      else
        err "Node $user/$name tidak dapat dijalankan ulang! Kunjungi aplikasi untuk recovery manual."
        restart_record "process:$user/$name" FAIL start
        failure=1
      fi
    done < "$TMP/stopped-unmanaged"
    : > "$TMP/stopped-unmanaged"
  fi
  START_PHASE_DONE=1
  if ((failure)); then RESTART_FAILED=1; return 1; fi
  return 0
}

# Official Node.js binary installer: avoids apt package dependency removals.
# The Node package from Ubuntu is kept under /usr/bin/node.distrib by dpkg-divert.
# Runtime processes are stopped before activation and checked after restart.
node_official_install() {
  local arch filename base target release_url metadata key expected actual bin link_path old_link entry
  local -a commands=('node' 'npm' 'npx')
  command -v curl >/dev/null && command -v tar >/dev/null && command -v sha256sum >/dev/null && command -v dpkg-divert >/dev/null || {
    err 'Node official binary membutuhkan curl, tar, sha256sum, dan dpkg-divert.'; return 1;
  }
  case "$(uname -m)" in
    x86_64) arch=x64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) err "Node official tidak tersedia untuk arsitektur $(uname -m); upgrade dihentikan."; return 1 ;;
  esac
  filename="node-v${NODE_RELEASE}-linux-${arch}.tar.xz"
  base="https://nodejs.org/dist/v${NODE_RELEASE}"
  target="/opt/ubuntu-maintenance/node-v${NODE_RELEASE}-linux-${arch}"
  local managed_flag="/opt/ubuntu-maintenance/.node-binary-managed"
  section 'NODE.JS OFFICIAL BINARY (TANPA APT NODE)'
  if [[ -x "$target/bin/node" ]] && [[ "$("$target/bin/node" -v 2>/dev/null)" == "v$NODE_RELEASE" ]]; then
    ok "Binary Node.js $NODE_RELEASE sudah tersedia; memeriksa aktivasi."
  else
    if ! run_quiet 'Node Official Download' curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 10 --max-time 240 -o "$TMP/$filename" "$base/$filename"; then return 1; fi
    if ! run_quiet 'Node SHA256 Download' curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 10 --max-time 40 -o "$TMP/SHASUMS256.txt" "$base/SHASUMS256.txt"; then return 1; fi
    metadata=$(awk -v f="$filename" '$2==f {print $1}' "$TMP/SHASUMS256.txt")
    [[ $metadata =~ ^[0-9a-f]{64}$ ]] || { err 'SHA256 official tidak ditemukan; arsip Node ditolak.'; return 1; }
    # Independent, pinned digest from the Node.js official v24.22.1 release.
    # Protects against a malicious mirror returning both altered tarball and manifest.
    case "$arch" in
      x64) expected=6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6 ;;
      arm64) expected=9ce5728445016b29e49ad098f7a336061aa5f770d177d927278bc26fd626e643 ;;
    esac
    actual=$(sha256sum "$TMP/$filename" | awk '{print $1}')
    [[ $metadata == "$actual" && $actual == "$expected" ]] || { err 'Checksum Node official TIDAK cocok dengan manifest dan digest rilis resmi! Arsip ditolak.'; return 1; }
    ok 'Node SHA256: cocok dengan manifest nodejs.org'
    mkdir -p /opt/ubuntu-maintenance || return 1
    local stage="$TMP/node-stage"
    mkdir -p "$stage"
    if ! tar -xJf "$TMP/$filename" -C "$stage" --no-same-owner; then err 'Ekstraksi Node gagal'; return 1; fi
    [[ -x "$stage/node-v${NODE_RELEASE}-linux-${arch}/bin/node" ]] || { err 'Arsip Node tidak memuat executable'; return 1; }
    if [[ "$("$stage/node-v${NODE_RELEASE}-linux-${arch}/bin/node" -v 2>/dev/null)" != "v$NODE_RELEASE" ]]; then
      err 'Binary Node yang diunduh gagal dieksekusi/versi berbeda'; return 1
    fi
    if [[ ! -d $target ]]; then mv "$stage/node-v${NODE_RELEASE}-linux-${arch}" "$target" || return 1; fi
  fi
  # The script runs with umask 077. Applications owned by non-root users
  # must still be able to read and execute Node and its npm JS modules.
  chmod 755 /opt/ubuntu-maintenance || return 1
  chmod -R a+rX "$target" || return 1
  # Preflight entire diversion transaction before modifying /usr/bin.
  for bin in "${commands[@]}"; do
    link_path="/usr/bin/$bin"
    [[ -e "$target/bin/$bin" || -L "$target/bin/$bin" ]] || { err "Node bundle tidak memiliki $bin"; return 1; }
    if [[ -e "$link_path" || -L "$link_path" ]]; then
      entry=$(dpkg-divert --list "$link_path")
      if [[ -n $entry && $entry != *'local diversion of'* ]]; then
        err "Diversion $link_path milik paket lain; tidak ditimpa."; return 1
      fi
      if [[ -n $entry && ! -f $managed_flag ]]; then
        err "Diversion $link_path sudah ada tetapi bukan milik skrip ini; dibatalkan."; return 1
      fi
      if [[ -n $entry && ! -L $link_path ]]; then
        err "Diverted $link_path bukan symlink; intervensi manual diperlukan."; return 1
      fi
      if [[ -z $entry && -L $link_path ]]; then
        # Original symlinks are preserved in .distrib using dpkg-divert.
        :
      fi
    fi
  done
  NODE_DIRECT_TRANSACTION=1
  for bin in "${commands[@]}"; do
    link_path="/usr/bin/$bin"
    old_link=''
    entry=$(dpkg-divert --list "$link_path")
    if [[ -n $entry ]]; then
      [[ -L $link_path ]] && old_link=$(readlink "$link_path" || true)
      NODE_DIRECT_PATHS+=("$link_path")
      NODE_DIRECT_DIVERTED+=(no)
      NODE_DIRECT_OLD_LINKS+=("$old_link")
      rm -f -- "$link_path" || return 1
    else
      NODE_DIRECT_PATHS+=("$link_path")
      NODE_DIRECT_DIVERTED+=(yes)
      NODE_DIRECT_OLD_LINKS+=('')
      if ! dpkg-divert --local --rename --add "$link_path" >"$TMP/divert-$bin.log" 2>&1; then
        # This diversion may not have been registered. Drop the last
        # recovery entry instead of removing an unrelated package file.
        unset 'NODE_DIRECT_PATHS[-1]' 'NODE_DIRECT_DIVERTED[-1]' 'NODE_DIRECT_OLD_LINKS[-1]'
        err "Gagal melindungi $link_path via dpkg-divert"; return 1
      fi
    fi
    ln -s "$target/bin/$bin" "$link_path" || return 1
  done
  if [[ "$(/usr/bin/node -v 2>/dev/null)" != "v$NODE_RELEASE" ]] || ! /usr/bin/npm -v >"$TMP/npm-verified" 2>&1; then
    err 'Validasi Node/npm gagal. Node binary akan dicoba dipulihkan.'; return 1
  fi
  printf '%s\n' "v${NODE_RELEASE}" > "$managed_flag" || return 1
  chmod 644 "$managed_flag" || return 1
  NODE_DIRECT_INSTALLED=1
  NODE_MAJOR_INSTALLED=1
  NODE_CHANGED=1
  ok "Node.js v$NODE_RELEASE aktif di /usr/bin/node (source: official tarball)"
  ok "npm $(cat "$TMP/npm-verified") aktif di /usr/bin/npm"
  warn 'Binary Node Ubuntu lama dipertahankan melalui dpkg-divert (/usr/bin/node.distrib). Upgrade paket Node APT tidak menyentuh binary aktif.'
  return 0
}

if [[ $MODE == apply ]]; then
  if (( PM2_DISCOVERY_INCOMPLETE )); then
    err 'Inventaris PM2 belum lengkap; upgrade dihentikan agar tidak mematikan aplikasi milik user lain.'
    APPLY_ABORTED=1
  elif [[ $ERRORS -ne 0 ]]; then err 'Baseline bermasalah; upgrade dibatalkan'; APPLY_ABORTED=1
  elif (( $(df -Pk / | awk 'NR==2 {print $4}') < 1048576 )); then
    err 'Free disk / < 1 GiB. Upgrade dibatalkan.'; APPLY_ABORTED=1
  elif command -v fuser >/dev/null 2>&1 && fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
    err 'APT/dpkg lock sedang digunakan. Upgrade dibatalkan.'; APPLY_ABORTED=1
  fi
  if ((APPLY_ABORTED==0)) && [[ $CONTAINER == no && $RESTART -eq 1 ]]; then
    if [[ -r /var/lib/dpkg/status ]]; then
      dpkg-query -W -f='${binary:Package}\t${Version}\n' > "$TMP/packages-before" 2>/dev/null || true
    fi
    if ! web_preflight; then
      APPLY_ABORTED=1
    elif ! stop_managed; then
      APPLY_ABORTED=1
    fi
  fi
  if ((APPLY_ABORTED==0)); then
    # Install an official Node binary first; APT package conflicts cannot block it.
    if [[ -x /usr/bin/node ]]; then
      NODE_LTS=1
      if ! node_official_install; then
        APPLY_ABORTED=1
      fi
    fi
  fi
  if ((RUNTIME_ONLY==1 && APPLY_ABORTED==0)); then
    section 'UPGRADE RUNTIME SAJA'
    ok 'APT upgrade umum dilewati; Node menggunakan binary official (tanpa migrasi paket APT).'
  fi
  if ((RUNTIME_ONLY==0 && APPLY_ABORTED==0)); then
    section 'APT UPDATE DAN UPGRADE'
    if [[ $CONTAINER == yes ]]; then warn 'Container APT mode enabled; no automatic service restarts in container'; fi
    if [[ -r /var/lib/dpkg/status ]]; then
      dpkg-query -W -f='${binary:Package}\t${Version}\n' > "$TMP/packages-before" 2>/dev/null || true
    fi
    if ((NODE_LTS==1)) && command -v apt-mark >/dev/null 2>&1 && ! apt-mark showhold | grep -Fxq nodejs; then
      if apt-mark hold nodejs >"$TMP/node-hold.log" 2>&1; then NODE_APT_HOLD_ADDED=1
      else err 'Gagal menahan paket Node APT selama upgrade'; APPLY_ABORTED=1; fi
    fi
    if ((APPLY_ABORTED==0)) && run_quiet 'Apt Update' env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=l apt-get -qq -o DPkg::Lock::Timeout=60 update; then
      if run_quiet 'Apt Upgrade' env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=l apt-get -qq -o DPkg::Lock::Timeout=60 -o Dpkg::Options::=--force-confold -y upgrade; then
        APT_RAN=1
      else
        APPLY_ABORTED=1
      fi
    else
      APPLY_ABORTED=1
    fi
    if ((NODE_APT_HOLD_ADDED)); then
      if apt-mark unhold nodejs >"$TMP/node-unhold.log" 2>&1; then NODE_APT_HOLD_ADDED=0
      else warn 'nodejs masih apt-mark hold, perlu unhold manual.'; fi
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

# PHP stable upgrade for installed Ubuntu APT PHP runtimes. Add a signed
# Launchpad PPA only when the native repository lacks the stable major.
# Never change an unverified web FPM socket or Apache handler implicitly.
PHP_FPM_PENDING=0
PHP_PPA_ADDED=0
php_candidate() {
  local name=$1 candidate
  candidate=$(apt-cache policy "$name" 2>/dev/null | awk '$1=="Candidate:" {print $2}' || true)
  [[ -n $candidate && $candidate != '(none)' ]]
}

php_enable_stable_repo() {
  local candidate distro flag
  if php_candidate "php${PHP_STABLE_SERIES}-cli"; then return 0; fi
  # PPA is only added on supported Ubuntu base releases. No source builds,
  # --allow-unauthenticated, or curl|bash are ever attempted.
  if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 24.04 && ${VERSION_ID:-} != 22.04 ]]; then
    err "PHP ${PHP_STABLE_SERIES}: repositori APT tidak menyediakan versi target; versi Ubuntu ini belum diizinkan untuk auto-PPA."
    return 1
  fi
  if ! command -v add-apt-repository >/dev/null 2>&1; then
    if ! apt-get -s install software-properties-common > "$TMP/php-repo-preplan" 2>&1 ||
       grep -q '^Remv ' "$TMP/php-repo-preplan"; then
      err 'Persiapan software-properties-common gagal / berisiko menghapus paket.'
      return 1
    fi
    if ! run_quiet 'PHP Repository Tools' env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get -qq -y install software-properties-common; then return 1; fi
  fi
  command -v add-apt-repository >/dev/null 2>&1 || { err 'add-apt-repository belum tersedia.'; return 1; }
  # add-apt-repository handles Launchpad key registration. APT enforces GPG;
  # third-party package trust still needs operator approval at fleet level.
  log 'PHP: PHP 8.5 belum tersedia; menambahkan PPA pihak ketiga ppa:ondrej/php (signed via Launchpad).'
  if ! run_quiet 'PHP Repository Setup' env LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive add-apt-repository --yes --no-update ppa:ondrej/php; then
    err 'PPA PHP gagal ditambahkan; PHP tidak dipaksa melalui binary yang tidak diverifikasi.'
    return 1
  fi
  PHP_PPA_ADDED=1
  if ! run_quiet 'PHP Repository Update' env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get -qq -o DPkg::Lock::Timeout=60 update; then
    err 'APT update setelah penambahan PHP PPA gagal.'
    return 1
  fi
  if ! php_candidate "php${PHP_STABLE_SERIES}-cli"; then
    err "Paket PHP ${PHP_STABLE_SERIES} belum tersedia meskipun PPA sudah ditambahkan."
    return 1
  fi
}

# PHP 8.5 bundles Zend OPcache in the runtime; there is no php8.5-opcache
# package. Apache mod_php is moved only when the old module is actually
# enabled. Keep the old Apache handler installed as a rollback candidate.
php_apache_restore_handler() {
  local newseries="$PHP_STABLE_SERIES" oldseries="$PHP_APACHE_OLD_SERIES"
  [[ -n $oldseries && $PHP_APACHE_WAS_ENABLED -eq 1 ]] || return 0
  if ! command -v a2dismod >/dev/null 2>&1 || ! command -v a2enmod >/dev/null 2>&1; then
    err 'Pemulihan Apache gagal: a2dismod/a2enmod tidak tersedia.'
    return 1
  fi
  a2dismod -f "php${newseries}" >"$TMP/php-apache-rollback.log" 2>&1 || true
  if ! a2enmod "php${oldseries}" >>"$TMP/php-apache-rollback.log" 2>&1 ||
     ! apache2ctl configtest >>"$TMP/php-apache-rollback.log" 2>&1; then
    err "Tidak bisa mengembalikan Apache ke mod_php${oldseries}; periksa $TMP/php-apache-rollback.log sebelum sesi berakhir."
    return 1
  fi
  if systemctl is-active --quiet apache2.service; then
    if ! systemctl restart apache2.service >"$TMP/php-apache-rollback-restart.log" 2>&1; then
      err "Konfigurasi lama dipulihkan, tetapi Apache gagal restart."
      return 1
    fi
  fi
  PHP_APACHE_SWITCHED=0
  PHP_APACHE_ROLLED_BACK=1
  warn "Handler Apache dikembalikan ke PHP ${oldseries}; PHP CLI baru tidak menjamin PHP website baru."
  return 0
}

php_apache_cutover() {
  local oldseries=$1
  [[ $PHP_APACHE_WAS_ENABLED -eq 1 ]] || return 0
  command -v a2dismod >/dev/null 2>&1 && command -v a2enmod >/dev/null 2>&1 && command -v apache2ctl >/dev/null 2>&1 || {
    err 'Tool Apache tidak lengkap untuk migrasi mod_php.'
    return 1
  }
  # Keep old mod_php on disk; move enabled Apache module only after both
  # PHP CLI and extension validation have succeeded.
  if ! a2dismod -f "php${oldseries}" >"$TMP/php-apache-switch.log" 2>&1 ||
     ! a2enmod "php${PHP_STABLE_SERIES}" >>"$TMP/php-apache-switch.log" 2>&1 ||
     ! apache2ctl configtest >>"$TMP/php-apache-switch.log" 2>&1; then
    err 'Migrasi handler Apache tidak lolos configtest. Mengembalikan mod_php lama.'
    php_apache_restore_handler || true
    return 1
  fi
  PHP_APACHE_SWITCHED=1
  ok "Apache mod_php${oldseries} → mod_php${PHP_STABLE_SERIES} (configtest PASS; URL diverifikasi sesudah start)."
  return 0
}

php_stable_upgrade() {
  local oldver oldseries candidate oldmodules newmodules newbin oldreal wanted pkgname
  local has_fpm=0 has_modphp=0 phpbin missing_modules old_opcache new_opcache
  local -a installs=()
  phpbin=$(command -v php 2>/dev/null || true)
  [[ -n $phpbin && -x $phpbin && -x /usr/bin/php ]] || return 0
  oldreal=$(readlink -f /usr/bin/php 2>/dev/null || true)
  oldver=$(/usr/bin/php -r 'echo PHP_VERSION;' 2>/dev/null || true)
  [[ $oldver =~ ^[0-9]+\.[0-9]+\. ]] || { err 'PHP tidak berasal dari binary sistem yang dikenali'; return 1; }
  oldseries=${oldver%.*}
  if [[ $oldseries == "$PHP_STABLE_SERIES" ]]; then
    log "PHP ${PHP_STABLE_SERIES} terpasang; pembaruan patch dilakukan oleh APT."
    return 0
  fi
  if [[ $(printf '%s\n%s\n' "$PHP_STABLE_SERIES" "$oldseries" | sort -V | tail -n 1) == "$oldseries" ]]; then
    warn "PHP $oldver di atas target ${PHP_STABLE_SERIES}; downgrade otomatis dilewati."
    return 0
  fi
  if ! dpkg-query -W -f='${Status}' "php${oldseries}-cli" 2>/dev/null | grep -q '^install ok installed$'; then
    err "PHP ${oldseries} CLI bukan instalasi APT yang dikenal; tidak menimpa binary manual."
    return 1
  fi
  if ! php_enable_stable_repo; then return 1; fi
  installs=("php${PHP_STABLE_SERIES}-cli" "php${PHP_STABLE_SERIES}-common")
  PHP_APACHE_WAS_ENABLED=0
  PHP_APACHE_OLD_SERIES="$oldseries"
  if [[ -e "/etc/apache2/mods-enabled/php${oldseries}.load" ]]; then
    PHP_APACHE_WAS_ENABLED=1
  fi
  # Match every versioned PHP extension whose target equivalent exists.
  # FPM and Apache packages can be installed side-by-side; moving the actual
  # site handler requires verified configuration, not merely a service start.
  while IFS= read -r pkgname; do
    [[ -n $pkgname ]] || continue
    wanted="php${PHP_STABLE_SERIES}-${pkgname#php${oldseries}-}"
    case "$wanted" in
      "php${PHP_STABLE_SERIES}-cli"|"php${PHP_STABLE_SERIES}-common") continue ;;
      "php${PHP_STABLE_SERIES}-opcache")
        log 'PHP OPcache: terintegrasi dalam PHP 8.5; tidak memerlukan paket php8.5-opcache.'
        continue ;;
      *-dev|*-dbg|*-phpdbg) warn "Paket pengembangan $pkgname tidak otomatis dimigrasikan."; continue ;;
    esac
    if ! php_candidate "$wanted"; then
      err "Modul PHP $pkgname tidak punya pengganti $wanted; migrasi dibatalkan sebelum instalasi."
      return 1
    fi
    if [[ $wanted == "php${PHP_STABLE_SERIES}-fpm" ]]; then has_fpm=1; fi
    installs+=("$wanted")
  done < <(dpkg-query -W -f='${binary:Package}\t${Status}\n' "php${oldseries}-*" 2>/dev/null | awk -F'\t' '$2=="install ok installed" {print $1}' | grep -E "^php${oldseries//./\\.}-" || true)
  # Detect FPM/Apache regardless of whether the service is active during the
  # upgrade, as the stop phase has intentionally shut it down.
  if dpkg-query -W -f='${Status}' "php${oldseries}-fpm" 2>/dev/null | grep -q '^install ok installed$'; then has_fpm=1; fi
  if dpkg-query -W -f='${Status}' "libapache2-mod-php${oldseries}" 2>/dev/null | grep -q '^install ok installed$'; then has_modphp=1; fi
  if ((has_modphp)); then
    # Install the new handler alongside the old one. Do not remove old mod_php;
    # it is required for recovery if configuration / HTTP check fails.
    installs+=("libapache2-mod-php${PHP_STABLE_SERIES}")
    if ((PHP_APACHE_WAS_ENABLED==0)); then
      log "Apache mod_php${oldseries} terpasang tetapi tidak aktif: handler Apache tidak dialihkan."
    fi
  fi
  if ((has_fpm)); then installs+=("php${PHP_STABLE_SERIES}-fpm"); fi
  # Preserve installed package set: reject APT solutions that remove anything.
  if ! env DEBIAN_FRONTEND=noninteractive apt-get -s install "${installs[@]}" >"$TMP/php-upgrade-plan" 2>&1; then
    err 'Simulasi pemasangan PHP terbaru gagal (dependency conflict).'
    return 1
  fi
  if grep -q '^Remv ' "$TMP/php-upgrade-plan"; then
    err "Simulasi PHP ingin menghapus paket: $(grep '^Remv ' "$TMP/php-upgrade-plan" | head -n 1). Dibatalkan."
    return 1
  fi
  oldmodules=$(/usr/bin/php -m 2>/dev/null | sed -n '/^\[PHP Modules\]/,/^\[Zend Modules\]/{/^\[/d;/^$/d;p;}' | sort -u)
  old_opcache=$(/usr/bin/php -r 'echo (int) extension_loaded("Zend OPcache");' 2>/dev/null || echo 0)
  if ! run_quiet "PHP ${PHP_STABLE_SERIES} Install" env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=l apt-get -qq -o DPkg::Lock::Timeout=60 -o Dpkg::Options::=--force-confold -y install "${installs[@]}"; then
    err 'PHP terbaru gagal dipasang; service lama akan dicoba hidupkan kembali.'
    return 1
  fi
  newbin="/usr/bin/php${PHP_STABLE_SERIES}"
  [[ -x $newbin ]] || { err "$newbin tidak tersedia setelah instalasi."; return 1; }
  if ! "$newbin" -v > "$TMP/php-new-version" 2>&1; then
    err "PHP ${PHP_STABLE_SERIES} gagal dieksekusi setelah install."
    return 1
  fi
  newmodules=$("$newbin" -m 2>/dev/null | sed -n '/^\[PHP Modules\]/,/^\[Zend Modules\]/{/^\[/d;/^$/d;p;}' | sort -u)
  new_opcache=$("$newbin" -r 'echo (int) extension_loaded("Zend OPcache");' 2>/dev/null || echo 0)
  if [[ $old_opcache == 1 && $new_opcache != 1 ]]; then
    if [[ -n $oldreal ]] && update-alternatives --list php 2>/dev/null | grep -Fxq "$oldreal"; then
      update-alternatives --set php "$oldreal" >/dev/null 2>&1 || true
    fi
    err 'OPcache tersedia pada PHP lama, tetapi tidak aktif pada PHP 8.5; migrasi dibatalkan.'
    return 1
  fi
  missing_modules=$(comm -23 <(printf '%s\n' "$oldmodules") <(printf '%s\n' "$newmodules") || true)
  if [[ -n $missing_modules ]]; then
    # APT install may auto-switch php alternatives: revert before failure.
    if [[ -n $oldreal ]] && update-alternatives --list php 2>/dev/null | grep -Fxq "$oldreal"; then
      update-alternatives --set php "$oldreal" > /dev/null 2>&1 || true
    fi
    err "PHP $PHP_STABLE_SERIES belum memiliki semua modul lama: $(printf '%s' "$missing_modules" | tr '\n' ','). Default CLI dikembalikan."
    return 1
  fi
  if ! update-alternatives --list php 2>/dev/null | grep -Fxq "$newbin"; then
    err "PHP baru tidak terdaftar dalam update-alternatives: $newbin"
    return 1
  fi
  if ! run_quiet 'PHP CLI Switch' update-alternatives --set php "$newbin"; then return 1; fi
  PHP_MIGRATED=1
  ok "PHP CLI $oldver → $(/usr/bin/php -r 'echo PHP_VERSION;' 2>/dev/null || echo '?')"
  if ((PHP_APACHE_WAS_ENABLED)); then
    if ! php_apache_cutover "$oldseries"; then
      # The original CLI remains available; restore the original default
      # too, to avoid reporting a partially successful PHP migration.
      if [[ -n $oldreal ]] && update-alternatives --list php 2>/dev/null | grep -Fxq "$oldreal"; then
        update-alternatives --set php "$oldreal" >/dev/null 2>&1 || true
      fi
      PHP_MIGRATED=0
      return 1
    fi
  fi
  if ((has_fpm)); then
    # Install/start the new FPM daemon but do not blindly edit nginx/apache
    # vhosts, pool sockets, or custom pool configurations.
    if command -v php-fpm${PHP_STABLE_SERIES} >/dev/null 2>&1 &&
       php-fpm${PHP_STABLE_SERIES} -t > "$TMP/php-new-fpm-test" 2>&1 &&
       run_quiet "Start php${PHP_STABLE_SERIES}-fpm" systemctl start "php${PHP_STABLE_SERIES}-fpm.service" &&
       systemctl is-active --quiet "php${PHP_STABLE_SERIES}-fpm.service"; then
      ok "PHP-FPM $PHP_STABLE_SERIES aktif."
      warn "FPM lama php${oldseries}-fpm tetap dapat melayani situs; socket/pool/vhost belum dialihkan secara otomatis."
      PHP_FPM_PENDING=1
    else
      err "FPM ${PHP_STABLE_SERIES} gagal konfigurasi/start. FPM lama akan dihidupkan kembali."
      return 1
    fi
  fi

  return 0
}

if [[ $MODE == apply && ( $APT_RAN -eq 1 || $RUNTIME_ONLY -eq 1 ) && $CONTAINER == no && -s $TMP/php-before && $APPLY_ABORTED -eq 0 ]]; then
  section 'PHP STABLE AUTO UPGRADE'
  if ((RUNTIME_ONLY==1)); then
    if ! run_quiet 'PHP Repository Update' env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get -qq -o DPkg::Lock::Timeout=60 update; then
      APPLY_ABORTED=1
      err 'PHP membutuhkan metadata APT, update gagal. PHP tidak diubah.'
    fi
  fi
  if ((APPLY_ABORTED==0)) && ! php_stable_upgrade; then
    APPLY_ABORTED=1
    err 'Migrasi PHP gagal atau tidak dapat diverifikasi; periksa paket dan aplikasi sebelum menjalankan ulang.'
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
      if ((PHP_APACHE_SWITCHED)); then php_apache_restore_handler || true; fi
    fi
  elif (( RESTART==0 )); then
    warn 'Stop/start otomatis tidak dijalankan (--no-restart).'
  elif [[ $CONTAINER == yes ]]; then
    warn 'Container: stop/start service harus melalui orchestrator/redeploy image.'
  else
    log 'Tidak ada service yang dihentikan (maintenance dibatalkan sebelum tahap stop).'
  fi
  # Restart web servers that were previously active, even when their package
  # did not change. Service startup has completed before this stage.
  if ! restart_local_web; then
    err 'Sebagian web server lokal gagal direstart; lihat status service dan URL.'
  fi
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
      newpid=$(awk -F '|' -v u="$user" -v id="$id" '$1==u && $5==id {print $4;exit}' "$TMP/pm2-after")
      runtime_state=$(node_runtime_state "${newpid:-0}")
      case "$runtime_state" in
        current) ok "PM2 $user/$name: online; runtime sesuai (PID=$newpid)"; APP_OK=$((APP_OK+1)) ;;
        stale) warn "PM2 $user/$name: online tetapi executable Node lama/deleted (PID=$newpid); daemon/startup PM2 perlu diperiksa"; APP_UNVERIFIED=$((APP_UNVERIFIED+1)); UNMANAGED_NODE_POST=$((UNMANAGED_NODE_POST+1)) ;;
        *) warn "PM2 $user/$name: online, executable tidak dapat diverifikasi (PID=${newpid:-N/A})"; APP_UNVERIFIED=$((APP_UNVERIFIED+1)) ;;
      esac
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
      newpid=$(awk -F '|' -v u="$user" -v n="$name" '$1=="systemd" && $2==u && $3==n {print $5;exit}' "$TMP/node-apps-after")
      runtime_state=$(node_runtime_state "${newpid:-0}")
      case "$runtime_state" in
        current) ok "Node systemd $name: active; runtime sesuai (PID=$newpid)"; APP_OK=$((APP_OK+1)) ;;
        stale) warn "Node systemd $name: active tetapi executable Node lama/deleted (PID=$newpid); restart unit diperlukan"; APP_UNVERIFIED=$((APP_UNVERIFIED+1)); UNMANAGED_NODE_POST=$((UNMANAGED_NODE_POST+1)) ;;
        *) warn "Node systemd $name: active, executable tidak dapat diverifikasi"; APP_UNVERIFIED=$((APP_UNVERIFIED+1)) ;;
      esac
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
    matching_pid=$(awk -F '|' -v u="$user" -v n="$name" '$1=="process" && $2==u && $3==n {print $5;exit}' "$TMP/node-apps-after")
    runtime_state=$(node_runtime_state "${matching_pid:-0}")
    case "$runtime_state" in
      stale)
        supervisor=$(node_parent_manager "$matching_pid")
        warn "Node process $user/$name PID=$matching_pid memakai executable LAMA (deleted/inode berubah). Restart perlu melalui ${supervisor}; tidak dilakukan paksa."
        UNMANAGED_NODE_POST=$((UNMANAGED_NODE_POST+1))
        APP_UNVERIFIED=$((APP_UNVERIFIED+1))
        ;;
      current)
        ok "Node process $user/$name: berjalan dengan executable yang cocok (PID=$matching_pid; fungsi HTTP belum diuji)"
        APP_OK=$((APP_OK+1))
        ;;
      *)
        warn "Node process $user/$name PID=${matching_pid:-N/A}: executable tidak dapat diverifikasi ($runtime_state)."
        APP_UNVERIFIED=$((APP_UNVERIFIED+1))
        ;;
    esac
  else
    err "Node process $user/$name: proses tidak ditemukan lagi"
    APP_FAIL=$((APP_FAIL+1))
  fi
done < "$TMP/node-apps-before"
log "Validasi proses: $APP_OK aktif / $APP_FAIL gagal / $APP_UNVERIFIED tidak terverifikasi; HTTP diuji terpisah pada langkah web berikutnya."

section 'WEB / PORT AKTIF (VERIFIKASI)'
if command -v ss >/dev/null 2>&1; then
  ss -H -ltnp > "$TMP/ss-after" 2>/dev/null || true
fi
if [[ -s $TMP/web-endpoints ]]; then
  web_probe "$TMP/web-after" AFTER
  web_compare
  if ((WEB_HEALTH_FAIL>0 && PHP_APACHE_SWITCHED>0)); then
    err 'Web gagal setelah migrasi mod_php; mencoba mengembalikan handler Apache lama.'
    if php_apache_restore_handler; then
      web_probe "$TMP/web-rollback" ROLLBACK
      log 'Endpoint diperiksa ulang setelah pemulihan Apache; hasil maintenance tetap FAIL.'
    fi
  fi
else
  log 'Tidak ada URL yang diuji. Status aplikasi hanya berdasarkan proses/service.'
fi

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
if ((PHP_APACHE_WAS_ENABLED)); then
  if ((PHP_APACHE_SWITCHED)); then
    printf 'Apache PHP handler: %s -> %s (configtest OK; URL checked)\n' "$PHP_APACHE_OLD_SERIES" "$PHP_STABLE_SERIES"
  elif ((PHP_APACHE_ROLLED_BACK)); then
    printf 'Apache PHP handler: %s -> %s (rollback)\n' "$PHP_APACHE_OLD_SERIES" "$PHP_APACHE_OLD_SERIES"
  else
    printf 'Apache PHP handler: %s (unchanged)\n' "$PHP_APACHE_OLD_SERIES"
  fi
fi
printf 'Node.js (%s): %s -> %s\n' "$CURRENT_NODE_PATH" "$NODE_OLD" "$NODE_NEW"
if ((UNMANAGED_NODE_POST>0)); then printf 'Node apps pending  : %s perlu restart/cek runtime (executable lama masih berjalan)\n' "$UNMANAGED_NODE_POST"; fi
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
    runtime_state=$(node_runtime_state "$pid")
    case "$runtime_state" in stale) status='STALE (restart needed)' ;; current) status='running (exe OK)' ;; *) status='runtime unverified' ;; esac
    printf '  • %-7s %-18s %-28s %-23s PID=%s\n' "$manager" "$user" "$name" "$status" "$pid"
    NODE_APPS_COUNT=$((NODE_APPS_COUNT+1))
  done < "$TMP/node-apps-after"
fi
((NODE_APPS_COUNT>0)) || printf '  N/A\n'
printf 'Node app terdeteksi: %s (best-effort, bukan inventaris lengkap)\n' "$NODE_APPS_COUNT"
printf 'Status aplikasi    : %s aktif / %s gagal / %s unverified (proses saja)\n' "$APP_OK" "$APP_FAIL" "$APP_UNVERIFIED"
printf 'Restart terkait   : %s OK / %s FAIL\n' "$RESTART_OK" "$RESTART_FAIL"
printf 'Web URL diperiksa : %s respons / %s belum sehat/terverifikasi\n' "$WEB_PROBE_PASS" "$WEB_PROBE_FAIL"
if [[ -f /run/reboot-required ]]; then warn 'Server memerlukan reboot (tidak dilakukan otomatis)'; fi
if ((PHP_FPM_PENDING>0)); then warn 'PHP CLI terbaru sudah terpasang, tetapi situs yang memakai FPM/mod_php perlu verifikasi/migrasi handler.'; fi
if ((ERRORS>0 || APPLY_ABORTED==1 || RUNTIME_TARGET_FAILED==1)); then RESULT='FAIL'
elif ((WARN>0 || APP_UNVERIFIED>0)); then RESULT='REVIEW'
else RESULT='PASS'; fi
printf 'PERINGATAN        : %s | ERROR: %s\n' "$WARN" "$ERRORS"
printf 'HASIL             : %s\n' "$RESULT"
log 'Keterangan: HTTP 2xx/3xx berarti endpoint merespons, bukan bukti DB/queue atau keseluruhan fungsi sehat.'
log 'Tidak ada log/JSON diunggah atau disimpan permanen oleh skrip.'
if [[ $RESULT == FAIL ]]; then exit 2; fi
