# Ubuntu PHP & Node.js Maintenance

**Audit, update, restart, dan verifikasi PHP/Node.js di Ubuntu melalui satu Bash script, dengan laporan langsung di terminal.**

[![Platform](https://img.shields.io/badge/Platform-Ubuntu-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![Version](https://img.shields.io/badge/Version-0.3.1-blue)
![Status](https://img.shields.io/badge/Status-Pilot%20%2F%20Use%20with%20care-yellow)

> [!IMPORTANT]
> Skrip ini ditujukan untuk administrator sistem yang memahami risiko maintenance server. **Jalankan `--audit` terlebih dahulu**, lakukan backup/snapshot, siapkan maintenance window, dan uji pada server nonkritis sebelum memakai `--apply` di produksi.

## Fitur

- **Identitas server:** hostname, versi OS, username login dan username efektif (`sudo`/root), host atau container, IP lokal, dan IP publik (*egress*).
- **Monitoring resource:** penggunaan CPU, jumlah logical CPU, load average 1/5/15 menit, RAM terpakai/total/tersedia, serta disk terpakai/total/sisa.
- **Inventaris runtime:** versi dan lokasi binary PHP/Node.js; deteksi instalasi Node.js melalui NVM yang dapat diakses.
- **Inventaris aplikasi:** proses Node.js, aplikasi PM2, service systemd terkait, dan container Docker yang terlihat dari host.
- **Pembaruan APT:** `apt-get update` dan `apt-get upgrade` pada Ubuntu, disertai pemeriksaan awal. Paket PHP/Node yang dikelola APT dapat ikut diperbarui jika repository menyediakan kandidat upgrade.
- **Proteksi versi Node:** membatalkan upgrade APT apabila kandidat paket `nodejs` berpindah major version.
- **Restart terarah:** PHP-FPM, PHP worker systemd, web server, service Node berbasis APT, serta reload PM2 yang memenuhi kriteria; bukan restart semua aplikasi secara membabi buta.
- **Health check HTTP:** memeriksa endpoint sebelum upgrade, setelah restart terkait, dan pada verifikasi akhir.
- **Output human-readable:** timestamp, status `✓` / `!` / `✗`, animasi saat pengukuran, output asli APT, dan ringkasan akhir yang mudah disalin.
- **Terminal-only:** tidak mengunggah laporan, tidak menyimpan log/JSON permanen. File kerja sementara dibersihkan saat skrip berakhir.

## Quick start

### 1. Audit langsung dengan satu baris (tanpa upgrade)

```bash
curl -fsSLo /tmp/ubuntu-maintenance-v03.sh https://raw.githubusercontent.com/vaisaldarmawan/updatephpandnodejs/main/ubuntu-maintenance-v03.sh && bash /tmp/ubuntu-maintenance-v03.sh --audit
```

Untuk inventaris proses dan service yang lebih lengkap:

```bash
sudo bash /tmp/ubuntu-maintenance-v03.sh --audit
```

> [!CAUTION]
> Tautan `main` dapat berubah ketika repository diperbarui. Untuk produksi, **review isi skrip dan pin URL ke full commit SHA** yang telah Anda setujui sebelum menjalankannya sebagai root. Jangan menjalankan skrip jarak jauh dengan pola `curl | sudo bash` tanpa pemeriksaan.

### 2. Lihat simulasi output

```bash
bash /tmp/ubuntu-maintenance-v03.sh --demo
```

Mode `--demo` menampilkan data **fiktif** dan tidak melakukan maintenance pada server.

### 3. Konfigurasi health check sebelum upgrade

Buat file `/etc/ubuntu-maintenance/healthchecks.tsv` dengan format berikut (**pemisah `|`**, bukan tab):

```text
# nama|url|expected_http_status
api|http://127.0.0.1:3000/health|200
webhook|http://127.0.0.1:3001/health|200
cms|http://127.0.0.1:8080/health|200
```

Contoh membuatnya:

```bash
sudo install -d -m 700 /etc/ubuntu-maintenance
sudo nano /etc/ubuntu-maintenance/healthchecks.tsv
sudo chmod 600 /etc/ubuntu-maintenance/healthchecks.tsv
```

Sesuaikan nama/port/endpoint dengan aplikasi Anda. Jangan memasukkan credential atau token rahasia dalam URL karena konfigurasi atau diagnostik dapat terekspos secara tidak sengaja. Endpoint sebaiknya dapat diakses dari **lingkungan tempat skrip dijalankan**.

> Status PM2 `online` atau systemd `active` hanya menunjukkan proses hidup; status aplikasi **belum terverifikasi sehat** apabila tidak ada health check yang relevan.

### 4. Jalankan upgrade (server Ubuntu, root)

```bash
sudo bash /tmp/ubuntu-maintenance-v03.sh --apply --health-file /etc/ubuntu-maintenance/healthchecks.tsv
```

`--apply` memerlukan root dan secara default menolak upgrade bila tidak ada HTTP health check yang valid. Penggunaan `--allow-unverified` tersedia sebagai *override* berisiko; **tidak disarankan untuk produksi**.

> [!WARNING]
> **`--apply` menjalankan `apt-get upgrade` untuk paket APT yang memiliki pembaruan, bukan hanya PHP dan Node.js.** Beberapa paket/daemon dapat me-restart service lewat mekanisme paket Ubuntu sebelum tahap restart terarah skrip. Tinjau daftar paket yang akan berubah, backup, dan lakukan rollout bertahap.

## Opsi CLI

| Opsi | Keterangan |
|---|---|
| `--audit` | Inventarisasi tanpa upgrade/restart; default ketika tidak ada argumen. Bisa sebagai user biasa. |
| `--apply` | `apt-get update` + `apt-get upgrade`, pemeriksaan dan restart terkait pada Ubuntu; harus root. |
| `--demo` | Simulasi terminal dengan data fiktif. |
| `--health-file PATH` | File endpoint HTTP; default `/etc/ubuntu-maintenance/healthchecks.tsv`. |
| `--update-nvm` | Saat `--apply`, update default Node NVM dalam major version yang sama; **tidak otomatis migrasi/restart aplikasi yang memakai NVM**. |
| `--no-restart` | Tidak menjalankan restart terarah setelah upgrade. |
| `--no-public-ip` | Tidak menghubungi layanan eksternal untuk mencari IP publik. |
| `--disk-path PATH` | Memilih filesystem yang dilaporkan; default `/`. |
| `--allow-container-apply` | Secara eksplisit mengizinkan upgrade APT di dalam container; restart otomatis tetap dimatikan. Bukan pola deployment container yang disarankan. |
| `--allow-unverified` | Mengizinkan upgrade tanpa HTTP health check; berisiko. |
| `-h`, `--help` | Bantuan penggunaan. |

### Contoh tambahan

Audit tanpa permintaan ke layanan lookup IP publik:

```bash
bash /tmp/ubuntu-maintenance-v03.sh --audit --no-public-ip
```

Periksa disk pada mount point lain:

```bash
sudo bash /tmp/ubuntu-maintenance-v03.sh --audit --disk-path /var
```

Upgrade APT sambil membiarkan restart ditangani operator:

```bash
sudo bash /tmp/ubuntu-maintenance-v03.sh --apply --no-restart
```

**Catatan:** `--no-restart` tidak mencegah restart yang mungkin dilakukan oleh sistem paket Ubuntu sendiri.

## Contoh tampilan terminal

```text
╔════════════════════════════════════════════════════════════════════╗
║ UBUNTU MAINTENANCE v0.3.1                                        ║
╚════════════════════════════════════════════════════════════════════╝
[15:08:21] Mode              : APPLY
[15:08:21] Hostname          : prod-api-01
[15:08:21] Pengguna login    : deploy
[15:08:21] Pengguna efektif  : root (via sudo)
[15:08:21] Lingkungan        : Host / VM
[15:08:21] IP lokal          : 192.168.10.20
[15:08:21] IP publik (egress): 203.0.113.20
[15:08:21] CPU               : 12.8% terpakai | 8 logical CPU
[15:08:21] RAM               : 3.20 GiB / 8.00 GiB
[15:08:21] Disk /            : 42.00 GiB / 100.00 GiB (58.00 GiB free)

──── [01] RUNTIME AWAL ────
[15:08:22] ✓ PHP /usr/bin/php : 8.3.34
[15:08:22] ✓ Node /usr/bin/node : v22.23.2

──── [02] APLIKASI / BASELINE ────
[15:08:23] ✓ api.service active
[15:08:23] ✓ webhook PM2 online
[15:08:23] ✓ Health api: HTTP 200

──── [03] PEMBARUAN PAKET ────
[15:08:35] ✓ apt-get update berhasil
[15:08:57] ✓ apt-get upgrade berhasil

──── [04] RESTART SERVICE ────
[15:08:58] ✓ php8.3-fpm.service: active setelah restart
[15:09:01] ✓ api.service: active setelah restart

──── RINGKASAN AKHIR ────
PHP               : 8.3.34 -> 8.3.36
Node.js           : v22.23.2 -> v22.23.4
Aplikasi Node.js  : api.service [active], webhook [online]
HTTP health       : 2 PASS / 0 FAIL
Restart terkait   : 2 OK / 0 FAIL
HASIL             : PASS
```

*Contoh di atas adalah ilustrasi dengan data fiktif. Output, urutan, dan status sebenarnya menyesuaikan server dan paket yang berubah. Jalankan `--demo` untuk simulasi bawaan skrip.*

## Bagaimana restart bekerja?

Restart hanya dipertimbangkan ketika paket yang relevan benar-benar berubah dan service sebelumnya aktif. Skrip melakukan pemeriksaan konfigurasi Nginx/Apache bila tersedia, me-restart service yang memenuhi syarat, lalu mencoba health check lagi. PM2 hanya di-*reload* untuk aplikasi online yang terdeteksi menggunakan `/usr/bin/node` dari paket APT.

**Tidak semua aplikasi akan ditemukan atau direstart otomatis.** Proses Node dari NVM/asdf/fnm, PM2 dengan konfigurasi khusus, job cron, service di luar pola deteksi, Docker, dan Kubernetes harus ditinjau terpisah. Untuk NVM, `--update-nvm` memasang Node terbaru pada **major** default yang sama bila profil didukung; perubahan binary yang dijalankan service/PM2 tetap menjadi tanggung jawab operator.

## Catatan keamanan dan batasan

1. **Upgrade hanya mengikuti repository APT yang sudah dikonfigurasi.** Skrip tidak otomatis menambahkan PPA, NodeSource, atau repository PHP baru. Nomor rilis upstream terbaru tidak selalu sama dengan versi paket Ubuntu yang telah menerima *security backport*.
2. **Tidak melakukan upgrade major PHP/Node secara otomatis.** Perubahan major PHP tetap perlu ditinjau terpisah; jika repository menawarkan perpindahan major untuk paket `nodejs`, upgrade APT dibatalkan.
3. **Tidak menginstal PHP/Node yang belum ada.** Skrip menginventarisasi yang ditemukan dan membiarkan instalasi lain tetap terpisah.
4. **Tidak ada rollback otomatis.** Siapkan snapshot/backup yang dapat dipulihkan dan prosedur recovery sebelum upgrade.
5. **Tidak ada reboot otomatis.** Jika Ubuntu menandai reboot diperlukan, skrip melaporkannya.
6. **Container berbeda dari host.** Audit dapat dilakukan dalam container, tetapi perbaikan yang tahan lama sebaiknya melalui perubahan Dockerfile/image dan redeploy. Docker/Kubernetes tidak diredeploy oleh skrip.
7. **IP publik menggunakan lookup eksternal** ke `https://api.ipify.org`, kecuali `--no-public-ip` digunakan. Tidak ada pengiriman laporan inventaris terpusat.
8. **Inventaris aplikasi bersifat *best effort*.** Proses yang tidak terlihat karena izin, namespace, atau metode peluncuran bisa terlewat. CPU/memori container mengikuti informasi cgroup jika tersedia; load average bisa tetap milik host.
9. **Status `PASS` bukan jaminan seluruh aplikasi sehat.** Status itu hanya mencerminkan pemeriksaan yang bisa dijalankan dan endpoint yang terdaftar. `REVIEW` berarti ada peringatan/keterbatasan; `FAIL` berarti pemeriksaan menemukan error atau upgrade dibatalkan.
10. **Tidak menyimpan log permanen.** Jika Anda ingin menyimpan output secara manual, gunakan `tee` saat menjalankan, dan perlakukan log tersebut sebagai data internal.

Contoh pengarsipan manual oleh operator:

```bash
sudo bash /tmp/ubuntu-maintenance-v03.sh --audit 2>&1 | tee ubuntu-maintenance-audit.log
```

## Persyaratan

- **Audit:** Linux dengan Bash, `/proc`, serta utilitas sistem standar. Beberapa informasi mungkin terbatas tanpa root.
- **Upgrade:** Ubuntu dengan `apt-get`, dijalankan sebagai root (`sudo`), dan akses ke repository APT.
- **Disarankan:** `curl` untuk health check/IP publik, `python3` untuk inventaris PM2, `systemctl` untuk service systemd, serta `runuser` untuk PM2 lintas-user/NVM.
- Konektivitas internet dibutuhkan untuk download skrip, pembaruan APT, dan NVM update jika dipilih. Audit lokal dapat dijalankan tanpa lookup IP publik dengan `--no-public-ip`.

## Troubleshooting

| Gejala | Yang perlu dicek |
|---|---|
| `Apply requires root` | Jalankan dengan `sudo` atau gunakan `--audit`. |
| `Upgrade dibatalkan: buat --health-file` | Siapkan endpoint HTTP health sebelum upgrade. |
| PHP/Node versi tidak berubah | Pastikan runtime berasal dari APT, repository menyediakan update, dan service memakai binary yang sesuai. |
| PM2 tidak terdeteksi | Audit dengan sudo; periksa user pemilik PM2, daemon aktif, lokasi CLI, dan `~/.pm2/pm2.pid`. |
| Aplikasi PM2 masih memakai Node lama | Cek `process.execPath` / `/proc/<PID>/exe`, NVM alias, PATH systemd, dan PM2 startup. |
| `IP publik: unavailable` | Periksa DNS/akses ke `api.ipify.org`, atau jalankan `--no-public-ip`. |
| Output container berbeda dari host | Jalankan audit pada host juga; lihat limit cgroup dan storage overlay. |
| `HASIL: REVIEW` | Baca baris peringatan; sering kali health check belum dikonfigurasi atau visibilitas runtime terbatas. |

## Repository

- **Source:** [`ubuntu-maintenance-v03.sh`](./ubuntu-maintenance-v03.sh)
- **Maintainer:** [vaisaldarmawan](https://github.com/vaisaldarmawan)
- **Issue / feedback:** [GitHub Issues](https://github.com/vaisaldarmawan/updatephpandnodejs/issues)

> **Lisensi:** file `LICENSE` belum disertakan di repository. Jika ingin menerima kontribusi dan mengizinkan redistribusi dengan ketentuan jelas, tambahkan lisensi open-source yang sesuai secara terpisah.
