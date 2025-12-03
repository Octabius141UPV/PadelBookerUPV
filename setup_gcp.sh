#!/bin/bash
# Script de instalación para VM de GCP (Debian/Ubuntu)

set -e

INSTALL_DIR="/opt/padelBooker"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        🎾 PadelBooker UPV - Instalador para GCP 🎾           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# PASO 1: Instalar dependencias
# =============================================================================
echo "📦 [1/4] Instalando dependencias..."
sudo apt-get update -qq
sudo apt-get install -y curl python3 > /dev/null 2>&1
echo "✅ Dependencias instaladas"
echo ""

# =============================================================================
# PASO 2: Configurar timezone
# =============================================================================
echo "🕐 [2/4] Configurando zona horaria..."
sudo timedatectl set-timezone Europe/Madrid
echo "✅ Timezone: Europe/Madrid"
echo ""

# =============================================================================
# PASO 3: Configuración interactiva
# =============================================================================
echo "⚙️  [3/4] Configuración de tu cuenta UPV"
echo "─────────────────────────────────────────"
echo ""

# Preguntar credenciales
echo "Introduce tus credenciales de la intranet UPV:"
echo ""
read -p "   👤 Alias (nombre de usuario): " USER_ALIAS
read -p "   🆔 DNI (solo números, sin letra): " USER_DNI
read -sp "   🔑 Contraseña: " USER_PASS
echo ""
echo ""

# Preguntar horarios
echo "¿Qué horario quieres reservar?"
echo "   Ejemplos: 20:00-21:00, 10:30-11:30, 19:00-20:00"
echo ""
read -p "   ⏰ Horario (HH:MM-HH:MM): " USER_SCHEDULE
echo ""

# Preguntar días
echo "¿Qué días de la semana quieres jugar?"
echo "   Opciones: Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday"
echo "   (separados por espacio, en inglés)"
echo ""
read -p "   📅 Días [Tuesday Thursday]: " USER_DAYS
USER_DAYS="${USER_DAYS:-Tuesday Thursday}"
echo ""

# Confirmar configuración
echo "─────────────────────────────────────────"
echo "📋 Resumen de configuración:"
echo "   • Usuario: $USER_ALIAS"
echo "   • DNI: $USER_DNI"
echo "   • Horario: $USER_SCHEDULE"
echo "   • Días: $USER_DAYS"
echo "─────────────────────────────────────────"
echo ""
read -p "¿Es correcto? (s/n): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
    echo "❌ Instalación cancelada. Vuelve a ejecutar el script."
    exit 1
fi
echo ""

# =============================================================================
# PASO 4: Crear archivos y servicio
# =============================================================================
echo "📁 [4/4] Instalando PadelBooker..."

# Crear directorio de trabajo
sudo mkdir -p "$INSTALL_DIR"

# Copiar script principal
sudo cp multiPadelBooker.sh "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR/multiPadelBooker.sh"

# Crear archivo de credenciales
echo "$USER_ALIAS : $USER_DNI : $USER_PASS" | sudo tee "$INSTALL_DIR/credentials.txt" > /dev/null
sudo chmod 600 "$INSTALL_DIR/credentials.txt"

# Crear archivo de horarios
echo "$USER_SCHEDULE" | sudo tee "$INSTALL_DIR/padel_groups.txt" > /dev/null

# Actualizar días permitidos en el script
sudo sed -i "s/allowed_weekdays=\".*\"/allowed_weekdays=\"$USER_DAYS\"/" "$INSTALL_DIR/multiPadelBooker.sh"

echo "✅ Archivos creados en $INSTALL_DIR"
echo ""

echo "🔧 Creando servicio systemd..."

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

echo "✅ Servicio systemd creado"
echo ""

# =============================================================================
# FINALIZADO
# =============================================================================
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              ✅ INSTALACIÓN COMPLETADA ✅                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "🚀 Para iniciar el servicio:"
echo "   sudo systemctl start padelBooker"
echo ""
echo "📊 Comandos útiles:"
echo "   sudo systemctl status padelBooker      # Ver estado"
echo "   sudo systemctl stop padelBooker        # Detener"
echo "   sudo systemctl enable padelBooker      # Inicio automático"
echo "   sudo tail -f /var/log/padelBooker.log  # Ver logs"
echo ""
echo "📝 Archivos de configuración:"
echo "   $INSTALL_DIR/credentials.txt"
echo "   $INSTALL_DIR/padel_groups.txt"
echo ""
echo "🔄 Para cambiar la configuración:"
echo "   sudo nano $INSTALL_DIR/credentials.txt"
echo "   sudo nano $INSTALL_DIR/padel_groups.txt"
echo "   sudo systemctl restart padelBooker"
echo ""
echo "¿Quieres iniciar el servicio ahora? (s/n): "
read -p "" START_NOW

if [[ "$START_NOW" =~ ^[sS]$ ]]; then
    sudo systemctl start padelBooker
    echo ""
    echo "✅ Servicio iniciado. Verificando estado..."
    sleep 2
    sudo systemctl status padelBooker --no-pager
fi
