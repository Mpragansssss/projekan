#!/bin/bash

# Fungsi untuk memulai ulang Docker jika tidak aktif
restart_docker_if_down() {
    # Periksa status Docker
    systemctl is-active --quiet docker
    if [ $? -ne 0 ]; then
        echo "Docker is down, restarting Docker..."
        systemctl restart docker
        
        # Tunggu sebentar agar Docker kembali online
        sleep 10
        
        # Cek kembali status Docker
        systemctl is-active --quiet docker
        if [ $? -ne 0 ]; then
            echo "Failed to restart Docker. Please check manually."
            exit 1
        else
            echo "Docker restarted successfully."
        fi
    else
        echo "Docker is running fine."
    fi
}

# Fungsi untuk memastikan container Windows berjalan
ensure_windows_container_running() {
    container_name="windows"

    # Periksa apakah container Windows sedang berjalan
    docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -w "$container_name" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Windows container is not running, starting it..."
        docker start $container_name
        if [ $? -eq 0 ]; then
            echo "Windows container started successfully."
        else
            echo "Failed to start Windows container. Please check Docker logs."
            exit 1
        fi
    else
        echo "Windows container is running fine."
    fi
}

# Fungsi untuk menambahkan firewall menggunakan iptables
setup_firewalls() {
    echo "Setting up firewalls..."

    # Allow only specific ports (8006 and 3389)
    iptables -A INPUT -p tcp --dport 8006 -j ACCEPT
    iptables -A INPUT -p tcp --dport 3389 -j ACCEPT
    iptables -A INPUT -p udp --dport 3389 -j ACCEPT

    # Block all other incoming connections except for Docker's internal bridge network
    iptables -A INPUT -i docker0 -j ACCEPT

    # Prevent the container from making external connections, except to necessary servers
    iptables -A OUTPUT -p tcp -d <necessary_server_ip> --dport 443 -j ACCEPT
    
    echo "Firewalls setup completed."
}

# Fungsi untuk melindungi Docker dari pengakhiran paksa (force-stop)
prevent_force_stop() {
    echo "Preventing force-stop..."

    # Disable specific signals to Docker that could be used to stop the container forcefully
    trap '' SIGINT SIGTERM SIGHUP
    
    # Monitor if Docker daemon is force-stopped and automatically restart
    while true; do
        systemctl is-active --quiet docker
        if [ $? -ne 0 ]; then
            echo "Docker daemon has been stopped forcefully, restarting..."
            systemctl restart docker
        fi
        sleep 60
    done
}

# Fungsi Python untuk mencetak waktu yang telah berlalu
print_elapsed_time() {
    python3 - <<END
import datetime
import time

def print_elapsed_time():
    start_time = datetime.datetime.now()

    try:
        while True:
            current_time = datetime.datetime.now()
            elapsed_time = current_time - start_time
            seconds_elapsed = elapsed_time.total_seconds()

            print(f"{int(seconds_elapsed)}s", end="\\r", flush=True)
            time.sleep(1)
    except KeyboardInterrupt:
        print("\\nProgram terminated.")

if __name__ == "__main__":
    print_elapsed_time()
END
}

# Instalasi awal Docker dan Docker Compose jika belum ada
setup_docker_environment() {
    # Bersihkan direktori /tmp dan update sistem
    cd /tmp && rm -rf * && clear
    apt update

    # Install screen jika belum terinstall
    apt install screen -y

    # Buat session screen
    screen -dmS win10_install

    # Buat file YAML untuk docker-compose
    cat <<EOF > /tmp/win10.yaml
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      USERNAME: "Mpragans"
      PASSWORD: "123456"
      DISK_SIZE: "90G"
      CPU_CORES: "4"
      RAM_SIZE: "11G"
      REGION: "en-US"
      KEYBOARD: "en-US"
      VERSION: "https://firebasestorage.googleapis.com/v0/b/theskynetku.appspot.com/o/win10ghost.iso?alt=media&token=2e5144b4-cdd8-4f81-aac8-d7a185ab77fe"
    volumes:
      - /tmp/win10:/storage
    devices:
      - /dev/kvm
    cap_add:
      - NET_ADMIN
    ports:
      - 8006:8006
      - 3389:3389/tcp
      - 3389:3389/udp
    stop_grace_period: 3m
EOF

    # Install docker-compose jika belum terinstall
    if ! command -v docker-compose &> /dev/null; then
        apt install docker-compose -y
    fi

    # Jalankan docker-compose untuk pertama kalinya
    docker-compose -f /tmp/win10.yaml up -d
}

# Pastikan instalasi sudah dilakukan sebelumnya
setup_docker_environment

# Setup firewall rules
setup_firewalls

# Jalankan pencetak waktu yang telah berlalu secara paralel
print_elapsed_time &

# Loop untuk terus memonitor status Docker dan container
while true; do
    restart_docker_if_down
    ensure_windows_container_running
    echo "Monitoring Docker and Windows container status..."
    
    # Prevent forced stops
    prevent_force_stop &
    
    # Tunggu 1 menit sebelum pengecekan berikutnya
    sleep 60
done
