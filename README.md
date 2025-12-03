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

⭐ Si te ha sido útil, ¡dale una estrella al repo! - Script para reservar el gimnasio de la UPV

**Creado por Darío Pérez (aka M0B)**

Este script de bash te permite automatizar la reserva del gimnasio en la UPV. Simplemente sigue las instrucciones a continuación para comenzar a utilizarlo.

## Clonación del Repositorio

Para obtener este script y los archivos necesarios, puedes clonar este repositorio utilizando el siguiente comando `git clone` en tu terminal:

```bash
git clone https://github.com/ImM0B/GymBookerUPV.git
```

## Requisitos Previos

Antes de usar este script, asegúrate de tener los siguientes requisitos:

- **bash**: Asegúrate de tener `bash` instalado en tu sistema.

- **Permisos de Ejecución**: Dale permisos de ejecución al script `multiGymBooker.sh` utilizando el siguiente comando:

   ```bash
   chmod +x multiGymBooker.sh
   ```

- **Archivos de Configuración**: Los siguientes archivos deben estar presentes en el mismo directorio que el script:

  - `credentials.txt`: Archivo que contiene tus credenciales de acceso a la intranet de la UPV. Debe seguir el formato:

    ```
    Alias : DNI(solo números) : Contraseña 
    ```

  - `groups.txt`: Archivo que contiene los números de grupo que deseas reservar (Máximo 6 por cuenta). Los números tienen que ser de dos dígitos siempre, siguiendo el siguiente formato:

    ```
    NúmeroGrupo1 NúmeroGrupo2 NúmeroGrupo3 ...
    ```

  - `horarios`: Archivo con una tabla de horarios asignados a cada número de grupo.

## Ejecución

Para utilizar el script, sigue estos pasos:

1. Clona o descarga este repositorio en tu máquina local.

2. Asegúrate de que los archivos `credentials.txt` y `groups.txt` estén en el mismo directorio que el script.

3. Ejecuta el script `multiGymBooker.sh` con el siguiente comando:

   ```bash
   ./multiGymBooker.sh
   ```

   El script verificará las credenciales de acceso y esperará hasta que sea sábado a las 10:01 a.m. para realizar las reservas.

4. Una vez que sea el sábado a las 10:01 a.m. , el script procederá a realizar las reservas para cada conjunto de credenciales y grupos definidos en los archivos `credentials.txt` y `groups.txt`.

## Añadir Más Cuentas

Puedes añadir más cuentas de la intranet de la UPV al archivo `credentials.txt`. Cada cuenta debe estar asignada a una línea del archivo `groups.txt`. El script procesará todas las cuentas en secuencia del archivo `credentials.txt` y realizará las reservas para cada línea correspondiente del archivo `groups.txt`. Por ejemplo, para la línea 3 de `credentials.txt` se harán las reservas de la línea 3 de `groups.txt`.

## Ejecución en Segundo Plano

Para ejecutar el script en segundo plano y guardar el output en un archivo de registro (`log.txt`), puedes utilizar el siguiente comando:

   ```bash
   ./multiGymBooker.sh > log.txt 2>&1 &
   ```

Además, para desvincular el proceso del terminal actual y evitar que se detenga cuando cierras la terminal, puedes usar el comando `disown` después de ejecutar el script:

   ```bash
   disown
   ````

Esto permite que el script continúe ejecutándose incluso después de cerrar la terminal.  Si deseas mantener el script en ejecución en tu máquina sin apagarla puedes usar Google Cloud por ejemplo.

## Horarios

Aquí se muestra una tabla de horarios asignados a cada número de grupo:

```
·-----------------------------------------------------------------·
| Horario         | Lunes | Martes | Miércoles | Jueves | Viernes |
|-----------------|-------|--------|-----------|--------|---------|
| 07:30-08:30     |  01   |   15   |   29      |   43   |   57    |
| 08:30-09:30     |  02   |   16   |   30      |   44   |   58    |
| 09:30-10:30     |  03   |   17   |   31      |   45   |   59    |
| 11:30-12:30     |  04   |   18   |   32      |   46   |   60    |
| 12:30-13:30     |  05   |   19   |   33      |   47   |   61    |
| 13:30-14:30     |  06   |   20   |   34      |   48   |   62    |
| 14:30-15:30     |  07   |   21   |   35      |   49   |   63    |
| 15:30-16:30     |  08   |   22   |   36      |   50   |   64    |
| 16:30-17:30     |  09   |   23   |   37      |   51   |   65    |
| 17:30-18:30     |  10   |   24   |   38      |   52   |   66    |
| 18:30-19:30     |  11   |   25   |   39      |   53   |   67    |
| 19:30-20:30     |  12   |   26   |   40      |   54   |   68    |
| 20:30-21:30     |  13   |   27   |   41      |   55   |   69    |
| 21:30-22:30     |  14   |   28   |   42      |   56   |   70    |
·-----------------------------------------------------------------·
```
