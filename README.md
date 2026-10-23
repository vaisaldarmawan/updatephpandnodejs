# Ubuntu Maintenance v0.5.1

Skrip untuk audit, upgrade PHP/Node.js, restart service terkelola, dan pemeriksaan URL web. **Jalankan saat maintenance window dan siapkan snapshot/backup**, terutama untuk migrasi mayor PHP 8.3 → 8.5 dan Node 18 → 24.

## 1. Download

```bash
curl -fL --retry 3 -o ubuntu-maintenance-v0.5.1.sh https://raw.githubusercontent.com/vaisaldarmawan/updatephpandnodejs/main/ubuntu-maintenance-v0.5.1.sh
```

Unggah file `.sh` v0.5.1 ke branch `main` GitHub terlebih dahulu.

## 2. Audit

```bash
sudo bash ubuntu-maintenance-v0.5.1.sh --audit
```

## 3. Apply

```bash
sudo bash ubuntu-maintenance-v0.5.1.sh --apply
```

**Khusus upgrade runtime tanpa `apt-get upgrade` seluruh Ubuntu:**

```bash
sudo bash ubuntu-maintenance-v0.5.1.sh --apply --runtime-only
```

`--runtime-only` tetap menggunakan APT/PPA untuk pemasangan PHP karena PHP-FPM dan ekstensi tidak tersedia sebagai satu binary Linux universal siap pakai. Node.js dipasang dari arsip resmi Node.js terverifikasi SHA256, tanpa migrasi paket Node lewat APT.

## Yang diperbaiki pada v0.5.1

- **PHP 8.5:** OPcache sudah termasuk dalam runtime PHP. Tidak lagi mencari paket `php8.5-opcache`, sehingga instalasi tidak ditolak karena paket yang memang tidak ada.
- **Validasi:** bandingkan modul PHP lama dan baru, termasuk memastikan `Zend OPcache` masih tersedia; ganti PHP CLI setelah validasi.
- **Apache mod_php:** jika `libapache2-mod-php8.3` terpasang dan modul Apache PHP 8.3 memang aktif, pasang handler PHP 8.5, pindahkan modul dengan `a2dismod`/`a2enmod`, dan uji `apache2ctl configtest`. Handler lama dipertahankan untuk pemulihan. Jika startup Apache atau HTTP baseline gagal, coba kembalikan handler lama; hasil tetap `FAIL` untuk pemeriksaan manual.
- **PHP-FPM:** paket PHP-FPM 8.5 dapat dipasang, tetapi socket dan konfigurasi virtual host khusus **tidak diganti secara membabi buta**. Jika situs masih memakai socket PHP lama, laporan akan menandainya sebagai butuh migrasi manual.
- **Node.js:** upgrade lewat binary resmi Node 24 LTS; aplikasi PM2/systemd yang terdeteksi di-restart dengan user/pengelola masing-masing. Proses mandiri hanya dapat dicoba restart dengan `--force-restart-unmanaged` karena berisiko pada Screen/Tmux.
- **Web:** mendeteksi URL lokal menggunakan IP LAN; bisa menambahkan URL sendiri menggunakan `--check-url`, misalnya `--check-url http://10.0.0.124/`.

## Batasan penting

Upgrade mayor PHP maupun Node dapat membuat aplikasi tidak kompatibel. HTTP 200 berarti URL merespons, **bukan** bukti semua route PHP, database, cron, atau queue sehat. Perpindahan PHP Apache tidak dijamin kompatibel dan migrasi FPM harus diperiksa. Tidak ada rollback paket penuh atau reboot otomatis. Jangan menganggap `--force-restart-unmanaged` aman untuk semua proses; opsi ini merekonstruksi startup aplikasi dan dapat melepas proses dari Screen/Tmux.

Skrip tidak mengunggah laporan maupun memerlukan `healthchecks.tsv`.
