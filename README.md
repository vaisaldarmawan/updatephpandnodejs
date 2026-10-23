# Ubuntu PHP & Node.js Maintenance

Skrip Bash untuk audit server Ubuntu, upgrade runtime PHP/Node.js yang **sudah terpasang**, serta stop/start service terkelola dengan laporan langsung di terminal. Tanpa `healthchecks.tsv`, collector, atau upload data.

**Versi: v0.4.2**

## Cara menggunakan

### 1. Download

```bash
curl -fL --retry 3 -o ubuntu-maintenance-v0.4.2.sh https://raw.githubusercontent.com/vaisaldarmawan/updatephpandnodejs/main/ubuntu-maintenance-v0.4.2.sh
```

### 2. Audit

```bash
sudo bash ubuntu-maintenance-v0.4.2.sh --audit
```

Membaca versi PHP/Node.js, aplikasi yang memakai runtime tersebut, status systemd/PM2, hostname, username, IP, CPU, RAM, dan disk. Tidak mengubah sistem.

### 3. Apply

```bash
sudo bash ubuntu-maintenance-v0.4.2.sh --apply
```

Urutan: **deteksi versi → inventaris service → stop PHP-FPM/Node systemd/PM2 yang sebelumnya aktif → pembaruan APT dan runtime → start service yang dihentikan → verifikasi status dan laporan**. Jika upgrade gagal, skrip tetap mencoba menghidupkan kembali service yang telah dihentikan.

- **Node.js:** instalasi NodeSource APT yang dikenali dimigrasikan ke **24.x LTS** (versi patch terbaru yang tersedia di repo), lalu diperiksa kembali. Instalasi NVM/asdf/fnm dan image container tidak otomatis dipindahkan ke major terbaru.
- **PHP:** update paket APT yang terpasang. Migrasi PHP CLI ke **8.5.x** dicoba apabila paket dan ekstensi cocok di repositori yang tersedia. Situs PHP-FPM/Apache **tidak dipindahkan otomatis ke socket/pool PHP baru**; jika target belum tercapai, laporan menampilkan `FAIL`/`REVIEW`. Skrip tidak menambahkan PPA pihak ketiga secara diam-diam.
- **Service:** hanya service systemd PHP/Node dan aplikasi PM2 **yang sebelumnya aktif** yang dihentikan dan dihidupkan kembali. Aplikasi proses mandiri (`screen`, `tmux`, `nohup`) **tidak dihentikan otomatis** karena skrip tidak memiliki cara yang andal untuk menghidupkannya kembali. Untuk server seperti `bot-gabungan`, `admin-panel` perlu dikelola systemd/PM2 atau direstart manual setelah upgrade runtime.
- **Pemeriksaan:** status proses `active/online` saja tidak menjamin endpoint API, database, dan queue berfungsi dengan benar.

> [!WARNING]
> `--apply` menyebabkan **downtime** pada layanan yang dihentikan dan memperbarui **seluruh paket APT**, bukan hanya PHP/Node.js. Simpan snapshot/backup, gunakan maintenance window dan uji terlebih dahulu pada server canary. Upgrade mayor dapat merusak kompatibilitas aplikasi. Tidak tersedia rollback paket otomatis maupun reboot otomatis.

**Repository:** [vaisaldarmawan/updatephpandnodejs](https://github.com/vaisaldarmawan/updatephpandnodejs)
