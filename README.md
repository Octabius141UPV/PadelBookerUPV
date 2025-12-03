# 🎾 PadelBooker UPV

**Reserva automática de pistas de pádel en la Universidad Politécnica de Valencia**

Script que automatiza la reserva de pistas de pádel en la intranet de la UPV, esperando al momento exacto de apertura (00:00, 8 días antes) para conseguir tu hora favorita.

![Bash](https://img.shields.io/badge/Bash-4.0+-green)
![Python](https://img.shields.io/badge/Python-3.6+-blue)
![License](https://img.shields.io/badge/License-MIT-yellow)

## ✨ Características

- 🕐 **Espera automática** hasta la apertura del plazo de reservas
- 📅 **Filtro por días** de la semana (ej: solo martes y jueves)
- 🔄 **Múltiples intentos** automáticos al abrirse el plazo
- 👥 **Soporte multi-cuenta** para reservar con varios usuarios
- 🧪 **Modo dry-run** para probar sin reservar
- 🐛 **Modo debug** para diagnóstico
- ☁️ **Listo para GCP** con script de instalación y servicio systemd

## 📋 Requisitos

- `bash` 4.0 o superior
- `curl`
- `python3`
- Cuenta de alumno/PAS/PDI en la UPV

## 🚀 Instalación

### 1. Clonar el repositorio

```bash
git clone https://github.com/TU_USUARIO/PadelBookerUPV.git
cd PadelBookerUPV
```

### 2. Configurar credenciales

```bash
cp credentials.example.txt credentials.txt
nano credentials.txt
```

Formato (una línea por cuenta):
```
MiAlias : 12345678A : miPassword123
```

### 3. Configurar horarios

```bash
cp padel_groups.example.txt padel_groups.txt
nano padel_groups.txt
```

Formato (una línea por cuenta, en el mismo orden que credentials.txt):
```
20:00-21:00
```

## 📖 Uso

### Modo automático (espera a la apertura)

```bash
./multiPadelBooker.sh
```

El script esperará hasta las 00:00 del día que se abren las reservas (8 días antes del día de juego).

### Modo inmediato (reservar ahora)

```bash
BOOK_DATE=2025-12-11 ./multiPadelBooker.sh
```

### Modo prueba (dry-run)

```bash
DRY_RUN=1 BOOK_DATE=2025-12-03 ./multiPadelBooker.sh
```

### Con debug

```bash
DEBUG=1 ./multiPadelBooker.sh
```

### Sin sudo (macOS)

```bash
SKIP_SUDO=1 ./multiPadelBooker.sh
```

## ⚙️ Configuración

Edita las variables al inicio de `multiPadelBooker.sh`:

| Variable | Descripción | Default |
|----------|-------------|---------|
| `allowed_weekdays` | Días permitidos (en inglés) | `"Tuesday Thursday"` |
| `release_offset_days` | Días antes que se abre el plazo | `8` |
| `release_time` | Hora de apertura | `"00:00"` |
| `attempts` | Intentos de reserva | `8` |
| `attempt_delay` | Segundos entre intentos | `15` |

### Variables de entorno

| Variable | Descripción |
|----------|-------------|
| `BOOK_DATE` | Fecha específica (YYYY-MM-DD) |
| `DEBUG` | Modo debug (1/0) |
| `DRY_RUN` | Solo mostrar, no reservar (1/0) |
| `SKIP_SUDO` | No usar sudo (1/0) |

## ☁️ Despliegue en Google Cloud Platform

### 1. Crear VM en GCP

```bash
gcloud compute instances create padel-booker \
  --zone=europe-southwest1-a \
  --machine-type=e2-micro \
  --image-family=debian-11 \
  --image-project=debian-cloud
```

### 2. Subir archivos

```bash
gcloud compute scp multiPadelBooker.sh credentials.txt padel_groups.txt setup_gcp.sh padel-booker:~/ --zone=europe-southwest1-a
```

### 3. Conectar e instalar

```bash
gcloud compute ssh padel-booker --zone=europe-southwest1-a
```

```bash
chmod +x setup_gcp.sh
./setup_gcp.sh
```

### 4. Gestionar el servicio

```bash
# Iniciar
sudo systemctl start padelBooker

# Ver estado
sudo systemctl status padelBooker

# Ver logs en tiempo real
sudo tail -f /var/log/padelBooker.log

# Habilitar inicio automático
sudo systemctl enable padelBooker

# Detener
sudo systemctl stop padelBooker
```

### 5. Editar configuración

```bash
sudo nano /opt/padelBooker/credentials.txt
sudo nano /opt/padelBooker/padel_groups.txt
sudo systemctl restart padelBooker
```

## 🔧 Troubleshooting

### "Login incorrecto"
- Verifica credenciales en `credentials.txt`
- Formato correcto: `Alias : DNI : Password` (espacios alrededor de `:`)
- Prueba a hacer login manual en la intranet

### "Grupo no encontrado"
- El horario puede estar ya ocupado
- Usa `DEBUG=1` para ver el HTML descargado
- Verifica que el horario existe para ese día

### "No se pudo descargar la página"
- Verifica conexión a internet
- La cookie puede haber expirado (el script hace login de nuevo)

### Errores de codificación
- El script maneja automáticamente ISO-8859-15
- Si hay problemas, verifica que `python3` está instalado

## 📁 Estructura del proyecto

```
PadelBookerUPV/
├── multiPadelBooker.sh      # Script principal
├── setup_gcp.sh             # Instalador para GCP
├── credentials.txt          # Tus credenciales (NO commitear)
├── credentials.example.txt  # Ejemplo de credenciales
├── padel_groups.txt         # Tus horarios (NO commitear)
├── padel_groups.example.txt # Ejemplo de horarios
├── .gitignore               # Archivos ignorados
└── README.md                # Este archivo
```

## 🤝 Contribuir

1. Fork del repositorio
2. Crea una rama (`git checkout -b feature/mejora`)
3. Commit de cambios (`git commit -am 'Añade mejora'`)
4. Push a la rama (`git push origin feature/mejora`)
5. Abre un Pull Request

## ⚠️ Disclaimer

Este script es solo para uso personal y educativo. Úsalo bajo tu propia responsabilidad. El autor no se hace responsable del mal uso o de cualquier problema derivado de su uso.

## 📄 Licencia

MIT License - ver [LICENSE](LICENSE) para más detalles.

---

⭐ Si te ha sido útil, ¡dale una estrella al repo!
