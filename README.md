# Ubuntu PHP & Node.js Maintenance

**Audit, update APT, restart service terkait, dan laporan langsung di terminal — satu Bash script, tanpa file konfigurasi tambahan atau upload laporan.**

[![Platform](https://img.shields.io/badge/Platform-Ubuntu-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![Version](https://img.shields.io/badge/Version-0.3.2-blue)
![Status](https://img.shields.io/badge/Status-Pilot%20%2F%20Use%20with%20care-yellow)

> [!IMPORTANT]
> Lakukan **audit lebih dahulu**, buat backup/snapshot, dan jadwalkan maintenance. `--apply` memperbarui **semua paket APT yang tersedia**, bukan hanya PHP dan Node.js, dan APT bisa memicu restart service selama upgrade. Belum ada rollback otomatis. Uji dahulu di server nonproduksi.

## Perintah cepat (satu baris)

### Audit server — tanpa mengubah sistem

```bash
curl -fsSLo /tmp/ubuntu-maintenance-v03.sh https://raw.githubusercontent.com/vaisaldarmawan/updatephpandnodejs/main/ubuntu-maintenance-v03.sh && sudo bash /tmp/ubuntu-maintenance-v03.sh --audit
```

### Upgrade paket APT + restart service yang relevan

```bash
curl -fsSLo /tmp/ubuntu-maintenance-v03.sh https://raw.githubusercontent.com/vaisaldarmawan/updatephpandnodejs/main/ubuntu-maintenance-v03.sh && sudo bash /tmp/ubuntu-maintenance-v03.sh --apply
```

**Tidak memerlukan file konfigurasi tambahan.** Skrip melakukan pengecekan status proses Node, PM2, dan service systemd sebelum/sesudah upgrade secara otomatis. Pengecekan tersebut **bukan** pengganti HTTP/API health check, validasi database, ataupun job queue.

> [!CAUTION]
> Perintah di atas mengambil kode terbaru dari branch `main`, yang dapat berubah. Di server produksi, baca/review dulu skripnya dan gunakan URL dari commit SHA yang telah disetujui sebelum menjalankannya sebagai root.

## Jika file `.sh` sudah diunduh

Download file saja:

```bash
curl -fL --retry 3 -o ubuntu-maintenance-v03.sh https://raw.githubusercontent.com/vaisaldarmawan/updatephpandnodejs/main/ubuntu-maintenance-v03.sh
```

Lalu jalankan sesuai keperluan:

```bash
sudo bash ubuntu-maintenance-v03.sh --audit
sudo bash ubuntu-maintenance-v03.sh --apply
```

Bila Anda tidak memiliki akses sudo, audit tetap bisa dijalankan sebagai pengguna biasa (`bash ubuntu-maintenance-v03.sh --audit`), dengan visibilitas proses dan PM2 lintas-user yang mungkin terbatas. Upgrade (`--apply`) memerlukan root. Mode `--apply` dalam container ditolak secara default; rebuild image lalu redeploy adalah cara yang dianjurkan.

## Fitur

- **Identitas:** hostname, OS, user login, user efektif (root/sudo), host atau container, IP lokal dan IP publik (egress).
- **Penggunaan resource:** CPU (%) dan load average (1/5/15), memory terpakai/total/tersedia (GiB), serta disk terpakai/total/sisa (GiB).
- **PHP/Node.js:** deteksi lokasi binary dan versi sebelum → sesudah; instalasi NVM yang dapat diakses juga diinventarisasi.
- **Aplikasi:** inventaris proses Node.js, PM2 lintas-user jika tersedia, service systemd terkait, dan container Docker yang terlihat.
- **Upgrade:** `apt-get update` dan `apt-get upgrade` dengan output langsung di terminal; pembaruan PHP/Node hanya untuk paket yang dikelola APT dan tersedia di repository.
- **Restart terarah:** PHP-FPM, PHP worker systemd, Apache/Nginx yang terdampak, Node systemd menggunakan Node APT, serta aplikasi PM2 tertentu yang menggunakan Node APT.
- **Validasi otomatis:** membandingkan kondisi proses, PM2 online, dan service systemd aktif sebelum/sesudah; gagal bila service/proses yang sebelumnya aktif menjadi tidak tersedia.
- **Terminal-only:** status berwarna, spinner saat pengukuran, dan ringkasan akhir. Tidak ada pelaporan terpusat atau log permanen.

## Opsi CLI

| Opsi | Fungsi |
|---|---|
| `--audit` | Inventarisasi tanpa perubahan (default); bisa sebagai user biasa. |
| `--apply` | Update + upgrade seluruh paket APT pada host Ubuntu, kemudian restart terarah. Perlu root. |
| `--demo` | Simulasi output dengan data fiktif tanpa mengubah sistem. |
| `--update-nvm` | Bersama `--apply`, update default Node dari NVM dalam major version yang sama. Startup/proses yang memakai NVM tetap perlu diverifikasi dan dimigrasikan manual. |
| `--no-restart` | Matikan restart terarah dari skrip, tetapi APT sendiri masih dapat me-restart service. |
| `--no-public-ip` | Jangan mengakses layanan lookup IP publik. |
| `--disk-path PATH` | Tampilkan statistik filesystem yang dipilih (default `/`). |
| `--allow-container-apply` | Izinkan APT dijalankan dalam container secara eksplisit; restart otomatis tetap dinonaktifkan. Tidak disarankan untuk deployment container. |
| `-h`, `--help` | Tampilkan bantuan. |

Contoh melihat simulasi:

```bash
bash ubuntu-maintenance-v03.sh --demo
```

## Contoh ringkasan terminal

*Data di bawah fiktif.*

```text
Hostname          : prod-api-01
Pengguna login    : deploy
Pengguna efektif  : root
Mode / lingkungan : apply / host
IP lokal          : 192.168.10.20
IP publik (egress): 203.0.113.20
CPU               : 12.8% (host), load: 0.64 / 0.71 / 0.83
RAM               : 3.20 / 8.00 GiB used | 4.80 GiB available
Disk /            : 42.00 / 100.00 GiB used | 58.00 GiB free
PHP               : 8.3.34 -> 8.3.36
Node.js           : v22.23.2 -> v22.23.4
Aplikasi Node.js (PM2 / systemd / proses):
  • PM2     deploy  webhook       online    PID=8812
  • systemd deploy  api.service   active    PID=8833
Status aplikasi   : 2 aktif / 0 gagal / 0 unverified (proses saja)
Restart terkait   : 3 OK / 0 FAIL
HASIL             : PASS
```

**Arti status:** `PASS` berarti pemeriksaan yang dilakukan tidak menemukan masalah; **bukan** jaminan aplikasi telah lolos pengujian fungsi/API. `REVIEW` berarti ada keterbatasan atau peringatan; `FAIL` berarti ditemukan error atau upgrade dibatalkan.

## Batasan dan keamanan

1. PHP dan Node **tidak diinstal** jika belum ada. PHP/Node yang dipasang di luar APT (NVM/asdf/fnm, binary manual, Docker) tidak otomatis diperbarui oleh APT.
2. Pembaruan mengikuti repository yang sudah tersedia. Skrip tidak otomatis menambahkan PPA/NodeSource; security backport Ubuntu bisa membuat versi paket berbeda dari versi upstream.
3. Deteksi perpindahan **major Node APT** memblokir upgrade, tetapi kompatibilitas seluruh dependency tidak dapat dipastikan secara otomatis. Perubahan major PHP membutuhkan evaluasi tersendiri.
4. Tidak ada **rollback**, **reboot otomatis**, atau **redeploy Docker/Kubernetes**.
5. Restart dan pemeriksaan hanya mencakup proses/service yang berhasil ditemukan. Status PM2 `online` / systemd `active` tidak membuktikan database, endpoint HTTP, atau queue worker benar-benar berfungsi normal.
6. IP publik diperoleh dari `https://api.ipify.org` (kecuali `--no-public-ip`). Data laporan tidak dikirimkan ke mana pun.
7. **Pengujian produksi belum dilakukan secara menyeluruh.** Mulai dari satu server nonkritis dan siapkan cara rollback/snapshot sebelum upgrade massal.

## Repository

- Script: [`ubuntu-maintenance-v03.sh`](./ubuntu-maintenance-v03.sh)
- Maintainer: [vaisaldarmawan](https://github.com/vaisaldarmawan)
- Issues: [GitHub Issues](https://github.com/vaisaldarmawan/updatephpandnodejs/issues)
