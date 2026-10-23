# Ubuntu PHP & Node.js Maintenance

Script Bash untuk audit server Ubuntu, memperbarui paket APT, me-restart service terkait, dan menampilkan laporan **langsung di terminal**.

**Versi:** v0.3.4 · **Tidak memerlukan** file `healthchecks.tsv` atau konfigurasi tambahan.

## Cara menggunakan

### 1. Download file `.sh`

```bash
curl -fL --retry 3 -o ubuntu-maintenance-v03.sh https://raw.githubusercontent.com/vaisaldarmawan/updatephpandnodejs/main/ubuntu-maintenance-v03.sh
```

### 2. Audit server

```bash
sudo bash ubuntu-maintenance-v03.sh --audit
```

Menampilkan informasi server (hostname, username, IP lokal/publik), CPU, RAM, disk, versi PHP/Node.js, serta status aplikasi dan service. **Tidak melakukan upgrade.**

### 3. Apply — upgrade dan restart service

```bash
sudo bash ubuntu-maintenance-v03.sh --apply
```

Menjalankan `apt-get update` dan `apt-get upgrade`, me-restart service terkait yang terdeteksi, lalu memeriksa kembali status proses, systemd, dan PM2. Hasil akhirnya tampil di terminal.

> [!IMPORTANT]
> `--apply` memperbarui **seluruh paket APT yang tersedia**, bukan hanya PHP/Node.js. Siapkan backup/snapshot, tinjau skrip sebelum menjalankan sebagai root, dan uji pada server nonproduksi lebih dahulu. **Tidak ada rollback otomatis.**
>
> Node.js/PHP yang dikelola NVM atau berada dalam container tidak otomatis ikut diperbarui oleh APT. Pengecekan status `active`/`online` **tidak menjamin fungsi aplikasi normal**; skrip tidak melakukan HTTP health check. Upgrade dalam container ditolak secara default.

**Repository:** [vaisaldarmawan/updatephpandnodejs](https://github.com/vaisaldarmawan/updatephpandnodejs)
