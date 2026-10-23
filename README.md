# Ubuntu PHP & Node.js Maintenance

Bash script untuk audit server Ubuntu, upgrade PHP/Node.js yang sudah terpasang, stop/start service, dan pengecekan URL/port. **Versi 0.4.9**. Output di terminal, tanpa upload laporan atau `healthchecks.tsv`.

## 1. Download

```bash
curl -fL --retry 3 -o ubuntu-maintenance-v0.4.9.sh https://raw.githubusercontent.com/vaisaldarmawan/updatephpandnodejs/main/ubuntu-maintenance-v0.4.9.sh
```

**Upload file versi 0.4.9 ke branch `main` GitHub lebih dahulu** agar URL di atas tersedia.

## 2. Audit

```bash
sudo bash ubuntu-maintenance-v0.4.9.sh --audit
```

Memeriksa user, IP lokal/publik, CPU/RAM/disk, PHP/Node.js, proses Node/PM2/systemd, port/URL web dan status runtime `STALE`. Tidak mengubah paket atau restart service.

## 3. Apply

```bash
sudo bash ubuntu-maintenance-v0.4.9.sh --apply
```

Mencoba menghentikan service yang dapat dikelola, upgrade APT, migrasi Node bawaan Ubuntu/NodeSource ke **Node 24 LTS** jika tersedia, migrasi PHP CLI terpasang ke **PHP 8.5** bila kompatibel, menghidupkan service lagi, restart Nginx/Apache aktif, dan memverifikasi versi serta HTTP. Server tanpa PHP/Node tidak akan dipasangi runtime yang sebelumnya tidak ada.

**Khusus aplikasi Node mandiri** (Screen/Tmux/proses tanpa PM2/systemd) yang *sudah jelas bisa dijalankan ulang*, Anda boleh memilih opsi:

```bash
sudo bash ubuntu-maintenance-v0.4.9.sh --apply --force-restart-unmanaged
```

Opsi ini berisiko: proses dijalankan ulang di luar sesi Screen/Tmux semula, dan stdout/stderr diarahkan ke `/dev/null`. Jangan gunakan tanpa snapshot/backup dan maintenance window. Bila startup tidak dapat direkonstruksi, proses tidak akan dihentikan.

### Perbaikan 0.4.9

Migrasi Node.js 18 bawaan Ubuntu ke NodeSource 24 tidak lagi otomatis gagal hanya karena APT perlu melepas `node-css-loader` atau modul `node-*` yang terinstal sebagai dependensi otomatis. **Setiap rencana penghapusan diperiksa:** penggantian paket Node build tooling yang diizinkan akan ditampilkan; penghapusan `nginx`, service Node, atau paket tidak dikenal tetap membatalkan migrasi. Tooling Ubuntu yang dilepas bisa perlu dipasang lagi sebagai dependensi proyek (`npm install`) bila memang digunakan dalam alur build.

### Penting

- Upgrade major bisa membuat aplikasi tidak kompatibel. Pengujian HTTP 200/302 hanya menunjukkan web merespons, bukan bahwa seluruh fungsi aplikasi sehat.
- `--apply` juga meng-upgrade paket Ubuntu lainnya, yang dapat memicu perubahan service, kernel, dan kebutuhan reboot. Tidak ada rollback otomatis paket OS.
- NodeSource dan `ppa:ondrej/php` (jika diperlukan) adalah sumber paket pihak ketiga. Migrasi handler/socket PHP-FPM yang tidak bisa diverifikasi tetap membutuhkan tindakan manual.
- Jika APT mengusulkan penghapusan paket aplikasi lain, skrip **sengaja gagal** daripada menggunakan `--force-yes` atau menghapusnya diam-diam.

[GitHub repository](https://github.com/vaisaldarmawan/updatephpandnodejs)
