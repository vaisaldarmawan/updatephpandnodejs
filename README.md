# Ubuntu PHP & Node.js Maintenance

Satu skrip Bash untuk audit Ubuntu, upgrade paket, pembaruan runtime stabil jika kompatibel, restart PHP-FPM/PM2, dan ringkasan server langsung di terminal. **Tanpa** `healthchecks.tsv`, database, upload laporan, atau konfigurasi tambahan.

**Versi:** v0.4.0

## Cara menggunakan

### 1. Download file

```bash
curl -fL --retry 3 -o ubuntu-maintenance-v03.sh https://raw.githubusercontent.com/vaisaldarmawan/updatephpandnodejs/main/ubuntu-maintenance-v03.sh
```

### 2. Audit

```bash
sudo bash ubuntu-maintenance-v03.sh --audit
```

Hanya memeriksa: hostname, username, IP lokal/publik, CPU, RAM, disk, PHP, Node.js, PM2, systemd, dan proses aplikasi. **Tidak mengubah server.**

### 3. Apply

```bash
sudo bash ubuntu-maintenance-v03.sh --apply
```

Secara otomatis:

- Menjalankan `apt-get update` dan `apt-get upgrade` untuk **semua paket APT yang memenuhi syarat**, bukan hanya PHP/Node.js.
- Jika Node.js APT/NodeSource terpasang, mencoba migrasi ke **Node.js 24 LTS**. Jika ada proses Node tanpa supervisor yang bisa direstart, migrasi mayor **dilewati** supaya aplikasi tidak diputus mendadak; update APT biasa tetap dilanjutkan.
- Jika PHP terpasang, memperbarui paketnya melalui APT dan mencoba migrasi **PHP CLI ke 8.5** hanya apabila paket tersedia di repository yang sudah aktif, semua ekstensi CLI yang diperlukan tersedia, serta tidak ada PHP-FPM/Apache/worker aktif yang perlu migrasi konfigurasi. **Tidak menambahkan PPA otomatis.** PHP-FPM tetap memakai versi/socket yang dikonfigurasi sampai dimigrasikan terpisah.
- Me-restart service PHP-FPM yang sebelumnya aktif dan me-reload aplikasi PM2 yang sebelumnya `online`, satu per satu dengan identitas pemiliknya. Service systemd yang terdeteksi terdampak juga direstart.
- Memeriksa ulang status service/proses dan versi runtime; menampilkan `[done]`, `[failed]`, dan peringatan yang relevan di terminal.

> [!IMPORTANT]
> **Skrip belum diuji melakukan upgrade mayor nyata di server produksi.** Jalankan dahulu di server canary dengan snapshot/backup dan maintenance window. Perpindahan Node/PHP mayor bisa membuat aplikasi tidak kompatibel, terutama native addon atau ekstensi PHP. Status `active`/`online` bukan bukti endpoint/DB/queue berfungsi normal. Tidak ada rollback atau reboot otomatis. Docker/Kubernetes harus diperbarui melalui image dan deployment-nya; NVM/asdf/fnm tidak dimigrasikan secara mayor otomatis.

**Repository:** [vaisaldarmawan/updatephpandnodejs](https://github.com/vaisaldarmawan/updatephpandnodejs)
