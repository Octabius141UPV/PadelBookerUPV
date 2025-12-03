#!/bin/bash
# Script de instalación para VM de GCP (Debian/Ubuntu)

set -e

echo "=== Instalando dependencias para PadelBooker ==="

# Actualizar sistema
sudo apt-get update

# Instalar dependencias
sudo apt-get install -y curl python3 python3-pip

# Configurar timezone
sudo timedatectl set-timezone Europe/Madrid

# Crear directorio de trabajo
INSTALL_DIR="/opt/padelBooker"
sudo mkdir -p "$INSTALL_DIR"
sudo cp multiPadelBooker.sh "$INSTALL_DIR/"
sudo cp credentials.txt "$INSTALL_DIR/"
sudo cp padel_groups.txt "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR/multiPadelBooker.sh"

# Crear usuario dedicado (opcional, más seguro)
# sudo useradd -r -s /bin/false padelBooker

echo "=== Creando servicio systemd ==="

sudo tee /etc/systemd/system/padelBooker.service > /dev/null <<EOF
[Unit]
Description=PadelBooker UPV - Reserva automática de pistas de pádel
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=/bin/bash $INSTALL_DIR/multiPadelBooker.sh
Restart=always
RestartSec=60
Environment="SKIP_SUDO=0"
Environment="DEBUG=0"
StandardOutput=append:/var/log/padelBooker.log
StandardError=append:/var/log/padelBooker.log

[Install]
WantedBy=multi-user.target
EOF

# Crear archivo de log
sudo touch /var/log/padelBooker.log
sudo chmod 644 /var/log/padelBooker.log

# Recargar systemd
sudo systemctl daemon-reload

echo ""
echo "=== Instalación completada ==="
echo ""
echo "Comandos útiles:"
echo "  sudo systemctl start padelBooker    # Iniciar el servicio"
echo "  sudo systemctl stop padelBooker     # Detener el servicio"
echo "  sudo systemctl status padelBooker   # Ver estado"
echo "  sudo systemctl enable padelBooker   # Iniciar automáticamente al arrancar"
echo "  sudo tail -f /var/log/padelBooker.log  # Ver logs en tiempo real"
echo ""
echo "Archivos de configuración en: $INSTALL_DIR"
echo "  - credentials.txt: Credenciales (Alias : DNI : Password)"
echo "  - padel_groups.txt: Horarios a reservar (ej: 10:30-11:30)"
echo ""
echo "IMPORTANTE: Edita los archivos de configuración antes de iniciar el servicio"
