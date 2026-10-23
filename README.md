# Ubuntu PHP & Node.js Maintenance

Script Bash untuk audit Ubuntu, upgrade PHP/Node.js **yang sudah terpasang**, stop/start layanan terkelola, dan cek URL/port web sebelum-sesudah maintenance. Semua hasil di terminal, **tanpa upload laporan** dan tanpa `healthchecks.tsv`.

**Versi: v0.4.5**

## Cara menggunakan

### 1. Download

```bash
curl -fL --retry 3 -o ubuntu-maintenance-v0.4.5.sh https://raw.githubusercontent.com/vaisaldarmawan/updatephpandnodejs/main/ubuntu-maintenance-v0.4.5.sh
```

### 2. Audit

```bash
sudo bash ubuntu-maintenance-v0.4.5.sh --audit
```

Memeriksa versi runtime, aplikasi Node/PHP, proses yang menggunakan executable lama (`(deleted)`), PM2/systemd, CPU, RAM, disk, IP, serta port TCP web yang dapat dikenali. Audit tidak mengubah paket atau me-restart service.

### 3. Apply

```bash
sudo bash ubuntu-maintenance-v0.4.5.sh --apply
```

Root akan mengelola PM2 milik masing-masing pengguna (misalnya `mpm`) dengan identitas pengguna dan `PM2_HOME` miliknya, bukan PM2 root. Instalasi PM2 dengan lokasi data nonstandar mungkin tidak terdeteksi.

Urutannya: **inventaris → cek URL sebelum upgrade → stop PHP-FPM/Node systemd/PM2 terkelola → upgrade paket/runtime → start kembali → restart Nginx/Apache lokal yang semula aktif → cek runtime, service, URL/port → ringkasan**.

### Opsional: cek URL web tertentu

Jika ingin memastikan alamat web tertentu—misalnya aplikasi yang berada di server lain—tambahkan `--check-url`:

```bash
sudo bash ubuntu-maintenance-v0.4.5.sh --audit --check-url http://10.0.0.126:3000/
```

Atau saat upgrade:

```bash
sudo bash ubuntu-maintenance-v0.4.5.sh --apply --check-url http://10.0.0.126:3000/
```

Opsi `--check-url` dapat diulang untuk beberapa URL, termasuk `https://`. Tidak ada file konfigurasi tambahan. Script juga berusaha mendeteksi port Node/PHP/Nginx/Apache yang `LISTEN` menggunakan `ss` (sejauh informasi PID dapat dibaca). **Web server di IP lain tidak direstart dari skrip ini**. **IP server lain tidak otomatis dipindai**; gunakan `--check-url` untuk URL eksternal.

**Arti pemeriksaan:** HTTP 2xx/3xx = endpoint merespons; HTTP 401/403 = endpoint dapat diakses tetapi memerlukan autentikasi; HTTP 4xx/5xx atau koneksi gagal = perlu investigasi. Respons HTTP belum membuktikan database, worker, atau seluruh fitur aplikasi normal. URL yang sebelumnya merespons tetapi menjadi gagal setelah upgrade akan menyebabkan hasil `FAIL`. Proses dengan binary `(deleted)` akan ditandai `STALE` meskipun URL masih merespons.

> [!WARNING]
> Mode `--apply` memperbarui seluruh paket APT, selain upaya upgrade PHP/Node yang didukung. Upgrade mayor dapat menyebabkan downtime dan ketidakcocokan aplikasi. Simpan snapshot/backup dan uji di server nonproduksi terlebih dahulu. Proses mandiri (misalnya Node di GNU Screen/Tmux) **tidak dihentikan secara paksa**, sebab perintah startup aslinya tidak selalu dapat dipulihkan. Aplikasi seperti itu mungkin perlu restart manual atau dipindah ke systemd/PM2. Skrip tidak membuat rollback otomatis dan tidak me-reboot server.

[Repository GitHub](https://github.com/vaisaldarmawan/updatephpandnodejs)

**Catatan restart:** Nginx/Apache lokal yang tadinya aktif akan di-restart setelah proses aplikasi terkelola hidup kembali, walaupun paket Nginx/Apache tidak berubah. Konfigurasi diuji sebelum upgrade dan sebelum restart. `--no-restart` menonaktifkan tindakan tersebut. Proses Node yang berjalan di Screen/Tmux tanpa manajer tetap hanya ditandai `STALE`; skrip tidak mengirim `kill` tanpa perintah start yang pasti.
