# Ubuntu Maintenance v0.5.0

Audit serta upgrade PHP dan Node.js untuk Ubuntu. Output terminal ringkas, restart service yang terdeteksi, dan pemeriksaan URL web. **Gunakan di maintenance window, uji dahulu di VM nonproduksi, dan siapkan snapshot/backup.**

## 1. Download

```bash
curl -fL --retry 3 -o ubuntu-maintenance-v0.5.0.sh https://raw.githubusercontent.com/vaisaldarmawan/updatephpandnodejs/main/ubuntu-maintenance-v0.5.0.sh
```

> Upload `ubuntu-maintenance-v0.5.0.sh` ke branch `main` sebelum menggunakan URL tersebut.

## 2. Audit

```bash
sudo bash ubuntu-maintenance-v0.5.0.sh --audit
```

## 3. Apply (upgrade + restart + verifikasi)

```bash
sudo bash ubuntu-maintenance-v0.5.0.sh --apply
```

Untuk **bot-agent** (PHP N/A) agar Node tidak melibatkan upgrade paket APT dan aplikasi `panel` dicoba restart, gunakan setelah snapshot:

```bash
sudo bash ubuntu-maintenance-v0.5.0.sh --apply --runtime-only --force-restart-unmanaged --check-url http://10.0.0.131:3000/
```

Untuk proses Node **mandiri** yang tidak memiliki service manager (contohnya berjalan lewat Screen), gunakan **hanya setelah mengecek startup dan menyiapkan backup**:

```bash
sudo bash ubuntu-maintenance-v0.5.0.sh --apply --force-restart-unmanaged
```

Untuk pemeriksaan URL tambahan (bisa diulang):

```bash
sudo bash ubuntu-maintenance-v0.5.0.sh --apply --check-url http://10.0.0.131:3000/
```

## Perubahan v0.5.0

- **Node.js:** instalasi binary **Node 24.22.1 LTS dari `nodejs.org`** untuk x64/ARM64, divalidasi dengan SHA256 dari rilis resmi. Node tidak lagi dimigrasikan melalui `apt-get install nodejs`, sehingga tidak perlu menghapus `webpack`, `eslint`, `terser`, `libnode109`, dll.
- Binary paket sebelumnya disimpan menggunakan `dpkg-divert` di `/usr/bin/node.distrib` (serta `npm`/`npx` jika ada). Skrip membuat symlink `/usr/bin/node`, `/usr/bin/npm`, dan `/usr/bin/npx` ke versi resmi di `/opt/ubuntu-maintenance/`. Direktori dibuat dapat dibaca dan dieksekusi pengguna non-root.
- Paket `nodejs` APT ditahan sementara saat `apt-get upgrade`, lalu status hold dipulihkan. Repositori NodeSource yang pernah ditambahkan oleh versi lama tidak dihapus otomatis.
- **PHP:** jika PHP terpasang, skrip mencoba memasang PHP **8.5** dari paket APT yang tersedia. Bila belum ada, skrip dapat menambahkan PPA `ondrej/php` di Ubuntu yang didukung dan memasang ekstensi yang sesuai. Default PHP CLI diganti hanya setelah validasi modul. **Tidak memasang PHP bila sebelumnya tidak ada.**
- PHP-FPM lama dan konfigurasi Nginx/Apache tidak otomatis dialihkan ke socket PHP 8.5; kompatibilitas website perlu pemeriksaan terpisah.
- Service systemd/PHP-FPM dan aplikasi PM2 yang teridentifikasi dihentikan dan dihidupkan kembali. Proses mandiri hanya dicoba restart dengan `--force-restart-unmanaged` karena bisa terlepas dari Screen/Tmux dan kehilangan output interaktif.
- URL HTTP(S) otomatis menggunakan IP lokal, bukan `127.0.0.1`, dan dicek sebelum dan sesudah upgrade.

## Batasan dan keamanan

`--apply` tetap menjalankan `apt-get update` dan `apt-get upgrade` untuk paket Ubuntu **selain migrasi Node**. Gunakan `--runtime-only` untuk melewati upgrade paket umum (pada server dengan PHP, instalasi PHP 8.5 tetap memerlukan APT/PPA). Paket PHP 8.5 menggunakan APT/PPA karena PHP tidak menyediakan universal precompiled Linux PHP-FPM yang dapat dipasang secara aman di semua konfigurasi.

Tidak ada jaminan kompatibilitas upgrade mayor Node 18→24 atau PHP 8.3→8.5. Node yang dikelola NVM/asdf/fnm, image Docker/Kubernetes, PM2 dengan `PM2_HOME` khusus, serta aplikasi dengan startup kompleks memerlukan pemeriksaan khusus. Proses lama yang masih memakai executable `(deleted)` akan ditandai `STALE`.

Tidak ada reboot otomatis, migrasi database, rollback menyeluruh, upload report, atau file konfigurasi `healthchecks.tsv`. Jika upgrade atau validasi gagal, baca ringkasan `FAIL/REVIEW` dan periksa kondisi service sebelum mengulang.
