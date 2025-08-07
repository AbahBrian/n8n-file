#!/bin/bash

# === KONFIGURASI ===
HOST_N8N_PATH="/DATA/AppData/n8n-file/.n8n"
CONTAINER_NAME="n8n"
EXPECTED_UID="1000"
EXPECTED_GID="1000"
EXPECTED_PERM="755"

echo "🔧 Auto-fix checker untuk n8n"
echo "=============================="

# 1. Cek dan buat folder jika belum ada
echo -n "🗂  Mengecek folder host $HOST_N8N_PATH... "
if [ ! -d "$HOST_N8N_PATH" ]; then
  echo "❌ TIDAK ADA"
  echo "➡️  Membuat folder..."
  mkdir -p "$HOST_N8N_PATH"
  echo "✅ Folder dibuat."
else
  echo "✅ ADA"
fi

# 2. Cek dan perbaiki ownership
echo -n "👤 Mengecek ownership folder... "
OWNER_UID=$(stat -c "%u" "$HOST_N8N_PATH")
OWNER_GID=$(stat -c "%g" "$HOST_N8N_PATH")
if [ "$OWNER_UID" != "$EXPECTED_UID" ] || [ "$OWNER_GID" != "$EXPECTED_GID" ]; then
  echo "⚠️  Salah ($OWNER_UID:$OWNER_GID), memperbaiki..."
  chown -R ${EXPECTED_UID}:${EXPECTED_GID} "$HOST_N8N_PATH"
  echo "✅ Ownership diperbaiki jadi ${EXPECTED_UID}:${EXPECTED_GID}"
else
  echo "✅ Ownership sudah benar"
fi

# 3. Cek dan perbaiki permission
echo -n "🔐 Mengecek permission folder... "
PERM=$(stat -c "%a" "$HOST_N8N_PATH")
if [ "$PERM" -lt "$EXPECTED_PERM" ]; then
  echo "⚠️  Terlalu rendah ($PERM), memperbaiki..."
  chmod -R 755 "$HOST_N8N_PATH"
  echo "✅ Permission diset ke 755"
else
  echo "✅ Permission aman ($PERM)"
fi

# 4. Tampilkan isi folder
echo "📦 Isi folder host:"
ls -la "$HOST_N8N_PATH"

# 5. Cek container
echo -n "🚦 Mengecek container '$CONTAINER_NAME'... "
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "❌ TIDAK JALAN"
  echo "➡️  Jalankan dengan: docker compose up -d"
  exit 1
else
  echo "✅ Berjalan"
fi

# 6. Cek volume mount di dalam container
echo -n "🔗 Mengecek apakah /home/node/.n8n termount... "
CONTAINER_CHECK=$(docker exec "$CONTAINER_NAME" test -d /home/node/.n8n && echo "yes" || echo "no")
if [ "$CONTAINER_CHECK" = "yes" ]; then
  echo "✅ Mount berhasil"
else
  echo "❌ Mount gagal"
  echo "➡️  Periksa kembali bagian 'volumes' di docker-compose.yml"
fi

# 7. Cek DB_TYPE
echo -n "🧠 Mengecek DB_TYPE di environment container... "
DB_TYPE=$(docker exec "$CONTAINER_NAME" printenv DB_TYPE 2>/dev/null)
if [ "$DB_TYPE" != "postgres" ]; then
  echo "❌ Salah: '$DB_TYPE'"
  echo "➡️  Harusnya: 'postgres'"
  echo "🔁 Edit docker-compose.yml dan ubah:"
  echo "    - DB_TYPE=postgres"
else
  echo "✅ DB_TYPE = postgres"
fi

# 8. Tampilkan file penting di container
echo "📁 Isi folder /home/node/.n8n dalam container:"
docker exec "$CONTAINER_NAME" ls -la /home/node/.n8n 2>/dev/null || echo "❌ Tidak dapat mengakses volume di dalam container"

# 9. Log akhir
echo "📜 Log terakhir n8n:"
docker logs "$CONTAINER_NAME" --tail=20 2>/dev/null

echo "✅ Pengecekan dan auto-fix selesai."
