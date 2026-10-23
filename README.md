# Ubuntu PHP & Node.js Maintenance

Audit dan upgrade PHP/Node.js yang sudah terpasang, kontrol service, dan verifikasi port/URL web dari terminal. **Versi v0.4.8.** Tidak membutuhkan `healthchecks.tsv` maupun collector laporan.

## 1. Download

```bash
curl -fL --retry 3 -o ubuntu-maintenance-v0.4.8.sh https://raw.githubusercontent.com/vaisaldarmawan/updatephpandnodejs/main/ubuntu-maintenance-v0.4.8.sh
```

## 2. Audit

```bash
sudo bash ubuntu-maintenance-v0.4.8.sh --audit
```

Memeriksa IP, user, CPU/RAM/disk, versi PHP/Node, PM2/systemd/proses Node, serta web/port menggunakan IP lokal server. Laporan aplikasi Node kosong ditulis `N/A`.

## 3. Apply

```bash
sudo bash ubuntu-maintenance-v0.4.8.sh --apply
```

Menghentikan service terkelola yang terdeteksi, memperbarui paket APT, mencoba migrasi Node sistem ke **24.x LTS**, dan migrasi **PHP CLI ke 8.5.x** jika PHP sudah terpasang. Jika PHP 8.5 belum tersedia, skrip menambahkan `ppa:ondrej/php` melalui Launchpad, memperbarui indeks APT, menyimulasikan instalasi (menolak penghapusan paket), memasang ekstensi yang setara, serta memilih interpreter PHP baru setelah memeriksa modul. Sesudahnya service yang sebelumnya aktif dijalankan kembali, Nginx/Apache lokal direstart setelah uji konfigurasi, lalu port/URL dan runtime diperiksa.

**Peringatan penting untuk PHP:** Skrip dapat menambahkan **PPA pihak ketiga** (`ppa:ondrej/php`), sehingga paket PHP berikutnya dapat berasal dari pengelola PPA, bukan repositori Canonical. PHP.net memberi peringatan bahwa build pihak ketiga ini memuat perubahan dari penyedia, termasuk patch telemetry pada modul Apache 2 dan PHP-FPM. Pastikan organisasi Anda menyetujui sumber paket tersebut. Untuk situs PHP-FPM/mod_php yang telah menggunakan socket, pool, atau vhost lama, **skrip memasang PHP 8.5 tetapi tidak mengubah konfigurasi web secara membabi buta**. Situs dapat tetap melayani PHP lama sampai migrasi handler diselesaikan; status akan `REVIEW`, bukan klaim seluruh web sudah PHP 8.5. Ekstensi pihak ketiga seperti ionCube juga perlu diverifikasi terpisah. Siapkan snapshot VM/backup, dan gunakan maintenance window.

**Peringatan Node.js:** Migrasi major dapat memerlukan perubahan dependency aplikasi. Skrip mendukung paket Node Ubuntu/NodeSource dan memverifikasi rencana APT, tetapi **tidak otomatis meng-upgrade NVM/custom binary**. Proses tanpa supervisor tidak dapat dijamin restart. Untuk percobaan restart paksa proses tersebut, tambahkan `--force-restart-unmanaged` hanya setelah memeriksa risiko Screen/Tmux, environment, dan logging.

Opsional pengecekan URL tambahan (tanpa file konfigurasi):

```bash
sudo bash ubuntu-maintenance-v0.4.8.sh --audit --check-url http://10.0.0.126:3000/
```

`--apply` dapat meng-upgrade paket Ubuntu lain, menyebabkan downtime, dan **tidak memiliki rollback otomatis** untuk seluruh sistem. HTTP 2xx/3xx berarti endpoint merespons, bukan jaminan database/queue atau aplikasi sehat secara keseluruhan.

[Repository GitHub](https://github.com/vaisaldarmawan/updatephpandnodejs)
