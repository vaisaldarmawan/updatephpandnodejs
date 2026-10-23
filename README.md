# Ubuntu PHP & Node.js Maintenance

Audit dan upgrade PHP/Node.js yang sudah terpasang, restart service, serta pengecekan web/port dari terminal. Tidak membutuhkan `healthchecks.tsv` atau server penyimpanan laporan.

**Versi: v0.4.6**

## 1. Download

```bash
curl -fL --retry 3 -o ubuntu-maintenance-v0.4.6.sh https://raw.githubusercontent.com/vaisaldarmawan/updatephpandnodejs/main/ubuntu-maintenance-v0.4.6.sh
```

## 2. Audit

```bash
sudo bash ubuntu-maintenance-v0.4.6.sh --audit
```

Memeriksa username, IP lokal/publik, CPU/RAM/disk, PHP/Node.js, PM2 milik root dan user lain, status service, executable Node lama `(deleted)`, serta port web otomatis dengan **IP lokal server**. Port yang hanya bind ke `127.0.0.1` tidak ditampilkan seolah-olah bisa diakses melalui IP LAN.

## 3. Apply

```bash
sudo bash ubuntu-maintenance-v0.4.6.sh --apply
```

Menghentikan service PHP/Node terkelola, memperbarui paket APT dan mencoba upgrade runtime yang tersedia, menjalankan kembali service/PM2, restart Nginx/Apache lokal yang sebelumnya aktif, lalu verifikasi status dan URL.

### Opsional: paksa restart aplikasi Node tanpa PM2/systemd

Jika Anda **secara sadar menerima downtime dan risiko perubahan startup**, gunakan:

```bash
sudo bash ubuntu-maintenance-v0.4.6.sh --apply --force-restart-unmanaged
```

Skrip mencoba mengambil username, direktori kerja, argumen dan environment awal proses Node dari `/proc`, lalu stop proses lama, upgrade paket dan menjalankannya lagi **sebagai user asal** (misalnya `mpm`, bukan root). Sebelum stop, semua metadata startup kandidat wajib terbaca. Jika tidak, upgrade dibatalkan tanpa menghentikan aplikasi. Setelah start, skrip memeriksa PID serta executable runtime baru; URL web diperiksa ulang. Saat APT gagal setelah service dihentikan, skrip mencoba pemulihan start.

**Peringatan:** Force restart bukan hal yang setara dengan PM2/systemd. Proses yang semula berjalan dalam Screen/Tmux akan dijalankan ulang **terpisah dari sesi tersebut**. Standard output dan error proses baru diarahkan ke `/dev/null`, sehingga log interaktif Screen tidak berlanjut. Aplikasi yang bergantung pada terminal, wrapper, variable environment dinamis, atau fitur yang tidak kompatibel dengan Node baru dapat gagal menyala. Kembalinya proses tidak menjamin seluruh fungsinya sehat, dan skrip **tidak menjamin rollback otomatis**. Untuk produksi, kelola aplikasi melalui systemd atau PM2 setelah migrasi.

### Opsional: cek URL web tambahan

```bash
sudo bash ubuntu-maintenance-v0.4.6.sh --audit --check-url http://10.0.0.126:3000/
```

Alamat di server lain hanya dicek, **tidak direstart** dari mesin lokal. URL otomatis menggunakan IP lokal server, tetapi tidak akan mengklaim port bind-only-loopback (`127.0.0.1`, `::1`) bisa diakses lewat IP lokal. HTTPS via IP otomatis hanya menguji ketersediaan layanan; pemeriksaan sertifikat/vhost perlu URL domain nyata lewat `--check-url`.

> **Catatan produksi:** `--apply` juga meng-upgrade paket APT selain PHP dan Node. Versi PHP major hanya dimigrasikan bila paket dan ekstensi kompatibel; skrip tidak diam-diam mengubah konfigurasi socket PHP-FPM atau menambahkan PPA. Selalu siapkan snapshot/backup dan maintenance window sebelum menjalankan perubahan pada server penting. Mode `--audit` aman untuk inventaris; tes otomatis bukan jaminan aplikasi sehat secara fungsional.

[Repository GitHub](https://github.com/vaisaldarmawan/updatephpandnodejs)
