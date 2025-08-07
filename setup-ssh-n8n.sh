#!/bin/bash

set -e

# === CONFIG ===
KEY_NAME="n8n_monitor"
KEY_PATH="/root/.ssh/$KEY_NAME"
TARGET_USER="root"
TARGET_IP="192.168.1.9"
TARGET="$TARGET_USER@$TARGET_IP"
DOCKER_COMPOSE_FILE="/DATA/AppData/n8n-file/docker-compose.yml"
N8N_CONTAINER_NAME="n8n"

echo "=== 🔐 1. Generate SSH Key jika belum ada ==="
mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ ! -f "$KEY_PATH" ]; then
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N ""
    echo "✅ Key generated."
else
    echo "ℹ️ Key sudah ada: $KEY_PATH"
fi

echo "=== 🧹 2. Perbaiki Permission Key & Config ==="
chown root:root /root/.ssh/*
chmod 600 /root/.ssh/$KEY_NAME
chmod 644 /root/.ssh/$KEY_NAME.pub
[ -f /root/.ssh/config ] && chmod 600 /root/.ssh/config || true

echo "=== 📩 3. Kirim public key ke $TARGET ==="
PUBKEY_CONTENT=$(cat "$KEY_PATH.pub")
ssh $TARGET "mkdir -p ~/.ssh && chmod 700 ~/.ssh"

if ssh $TARGET "grep -q \"$PUBKEY_CONTENT\" ~/.ssh/authorized_keys"; then
    echo "✅ Public key sudah ada di remote."
else
    echo "$PUBKEY_CONTENT" | ssh $TARGET "cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    echo "✅ Public key ditambahkan ke remote."
fi

echo "=== 📦 4. Tambahkan mount ~/.ssh ke docker-compose.yml (jika belum) ==="
if ! grep -q "/root/.ssh" "$DOCKER_COMPOSE_FILE"; then
    sed -i "/n8n:/,/volumes:/{
        /volumes:/a \ \ \ \ - type: bind\n\ \ \ \ \ \ source: /root/.ssh\n\ \ \ \ \ \ target: /home/node/.ssh\n\ \ \ \ \ \ read_only: false\n\ \ \ \ \ \ bind:\n\ \ \ \ \ \ \ \ create_host_path: true
    }" "$DOCKER_COMPOSE_FILE"
    echo "✅ SSH volume ditambahkan."
else
    echo "ℹ️ Volume mount sudah ada."
fi

echo "=== 🔁 5. Restart container ==="
docker compose down
docker compose up -d

echo "⏳ Tunggu 10 detik untuk n8n siap..."
sleep 10

echo "=== 🔐 6. Perbaiki permission dalam container ==="
docker exec -u 0 $N8N_CONTAINER_NAME sh -c "
  chmod 700 /home/node/.ssh && \
  chmod 600 /home/node/.ssh/$KEY_NAME && \
  chmod 644 /home/node/.ssh/$KEY_NAME.pub || true
"

echo "=== 🧪 7. Uji koneksi SSH dari container ==="
docker exec $N8N_CONTAINER_NAME sh -c "
  ssh -i /home/node/.ssh/$KEY_NAME \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      $TARGET 'echo OK'" > ssh_test_output.txt 2>&1

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "\n✅ SSH BERHASIL tanpa password!"
    cat ssh_test_output.txt
else
    echo -e "\n❌ SSH GAGAL. Analisa:"
    cat ssh_test_output.txt

    if grep -q "Permission denied" ssh_test_output.txt; then
        echo "🧩 Server menolak key. Mungkin key belum benar-benar ditambahkan ke ~/.ssh/authorized_keys"
    elif grep -q "No such file or directory" ssh_test_output.txt; then
        echo "🧩 File key tidak ditemukan dalam container"
    elif grep -q "not accessible" ssh_test_output.txt; then
        echo "🧩 Key tidak dapat dibaca oleh user dalam container (perbaiki permission & ownership)"
    else
        echo "🧩 Masalah lain. Cek log di atas."
    fi
fi

rm -f ssh_test_output.txt
