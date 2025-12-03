#!/bin/bash
# =============================================================================
# PadelBooker UPV - Despliegue en Google Cloud
# Cloud Function + Cloud Scheduler
# =============================================================================

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     🎾 PadelBooker UPV - Despliegue Cloud Function 🎾        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# =============================================================================
# VERIFICAR PRERREQUISITOS
# =============================================================================

echo "📋 Verificando prerrequisitos..."

# Verificar gcloud
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}❌ gcloud CLI no está instalado${NC}"
    echo "   Instálalo desde: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Verificar autenticación
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    echo -e "${RED}❌ No estás autenticado en gcloud${NC}"
    echo "   Ejecuta: gcloud auth login"
    exit 1
fi

echo -e "${GREEN}✅ Prerrequisitos OK${NC}"
echo ""

# =============================================================================
# CONFIGURACIÓN
# =============================================================================

echo -e "${YELLOW}⚙️  Configuración${NC}"
echo "─────────────────────────────────────────"

# Obtener proyecto actual o pedir uno
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [ -n "$CURRENT_PROJECT" ]; then
    read -p "   Proyecto GCP [$CURRENT_PROJECT]: " PROJECT_ID
    PROJECT_ID="${PROJECT_ID:-$CURRENT_PROJECT}"
else
    read -p "   Proyecto GCP: " PROJECT_ID
fi

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}❌ Debes especificar un proyecto${NC}"
    exit 1
fi

# Región
read -p "   Región [europe-southwest1]: " REGION
REGION="${REGION:-europe-southwest1}"

# Credenciales UPV
echo ""
echo "   Credenciales de la intranet UPV:"
read -p "      👤 Alias: " UPV_ALIAS
read -p "      🆔 DNI (solo números): " UPV_DNI
read -sp "      🔑 Contraseña: " UPV_PASSWORD
echo ""

# Horario
echo ""
read -p "   ⏰ Horario a reservar [20:00-21:00]: " PADEL_SCHEDULE
PADEL_SCHEDULE="${PADEL_SCHEDULE:-20:00-21:00}"

# Días de la semana (para Cloud Scheduler)
# IMPORTANTE: El scheduler se ejecuta 8 días ANTES del día de juego
# Para jugar Martes → ejecutar Lunes (8 días antes)
# Para jugar Jueves → ejecutar Miércoles (8 días antes)
echo ""
echo "   📅 ¿Qué días quieres JUGAR?"
echo "      1) Martes y Jueves → se ejecuta Lunes y Miércoles (default)"
echo "      2) Solo Martes → se ejecuta Lunes"
echo "      3) Solo Jueves → se ejecuta Miércoles"
echo "      4) Lunes, Miércoles y Viernes → se ejecuta Domingo, Martes y Jueves"
echo "      5) Todos los días"
read -p "      Opción [1]: " DAY_OPTION
DAY_OPTION="${DAY_OPTION:-1}"

case $DAY_OPTION in
    1) CRON_DAYS="1,3" ; PLAY_DAYS="Martes y Jueves" ;;      # Lunes y Miércoles
    2) CRON_DAYS="1" ; PLAY_DAYS="Martes" ;;                  # Solo Lunes
    3) CRON_DAYS="3" ; PLAY_DAYS="Jueves" ;;                  # Solo Miércoles
    4) CRON_DAYS="0,2,4" ; PLAY_DAYS="Lunes, Miércoles y Viernes" ;;  # Dom, Mar, Jue
    5) CRON_DAYS="*" ; PLAY_DAYS="Todos los días" ;;          # Todos
    *) CRON_DAYS="1,3" ; PLAY_DAYS="Martes y Jueves" ;;
esac

# Hora de ejecución
read -p "   🕐 Hora de ejecución (HH:MM) [09:00]: " EXEC_TIME
EXEC_TIME="${EXEC_TIME:-09:00}"
EXEC_HOUR=$(echo $EXEC_TIME | cut -d: -f1)
EXEC_MIN=$(echo $EXEC_TIME | cut -d: -f2)

echo ""
echo "─────────────────────────────────────────"
echo -e "${GREEN}📋 Resumen:${NC}"
echo "   • Proyecto: $PROJECT_ID"
echo "   • Región: $REGION"
echo "   • Usuario UPV: $UPV_ALIAS"
echo "   • Horario pádel: $PADEL_SCHEDULE"
echo "   • Días de juego: $PLAY_DAYS"
echo "   • Scheduler: $EXEC_TIME (8 días antes)"
echo "─────────────────────────────────────────"
echo ""
read -p "¿Continuar? (s/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
    echo "Cancelado."
    exit 0
fi

# =============================================================================
# CONFIGURAR PROYECTO
# =============================================================================

echo ""
echo -e "${YELLOW}🔧 Configurando proyecto...${NC}"

gcloud config set project $PROJECT_ID

# Habilitar APIs necesarias
echo "   Habilitando APIs..."
gcloud services enable cloudfunctions.googleapis.com --quiet
gcloud services enable cloudscheduler.googleapis.com --quiet
gcloud services enable secretmanager.googleapis.com --quiet
gcloud services enable cloudbuild.googleapis.com --quiet

echo -e "${GREEN}   ✅ APIs habilitadas${NC}"

# =============================================================================
# CREAR SECRETOS
# =============================================================================

echo ""
echo -e "${YELLOW}🔐 Guardando credenciales en Secret Manager...${NC}"

# Función para crear o actualizar secreto
create_or_update_secret() {
    local name=$1
    local value=$2
    
    if gcloud secrets describe $name --project=$PROJECT_ID &>/dev/null; then
        echo -n "$value" | gcloud secrets versions add $name --data-file=- --project=$PROJECT_ID
        echo "   📝 Secreto '$name' actualizado"
    else
        echo -n "$value" | gcloud secrets create $name --data-file=- --project=$PROJECT_ID
        echo "   🆕 Secreto '$name' creado"
    fi
}

create_or_update_secret "padel-alias" "$UPV_ALIAS"
create_or_update_secret "padel-dni" "$UPV_DNI"
create_or_update_secret "padel-password" "$UPV_PASSWORD"

echo -e "${GREEN}   ✅ Credenciales guardadas de forma segura${NC}"

# =============================================================================
# DESPLEGAR CLOUD FUNCTION
# =============================================================================

echo ""
echo -e "${YELLOW}☁️  Desplegando Cloud Function...${NC}"

# Ir al directorio de la función
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/cloud_function"

# Desplegar
gcloud functions deploy padel-booker \
    --gen2 \
    --runtime=python311 \
    --region=$REGION \
    --source=. \
    --entry-point=padel_booker \
    --trigger-http \
    --no-allow-unauthenticated \
    --memory=256MB \
    --timeout=300s \
    --set-env-vars="GCP_PROJECT=$PROJECT_ID,PADEL_SCHEDULE=$PADEL_SCHEDULE" \
    --quiet

echo -e "${GREEN}   ✅ Cloud Function desplegada${NC}"

# Obtener URL de la función
FUNCTION_URL=$(gcloud functions describe padel-booker --region=$REGION --gen2 --format='value(serviceConfig.uri)')
echo "   📍 URL: $FUNCTION_URL"

# Dar permisos a la función para acceder a los secretos
echo ""
echo "   Configurando permisos..."
SERVICE_ACCOUNT=$(gcloud functions describe padel-booker --region=$REGION --gen2 --format='value(serviceConfig.serviceAccountEmail)')

for secret in padel-alias padel-dni padel-password; do
    gcloud secrets add-iam-policy-binding $secret \
        --member="serviceAccount:$SERVICE_ACCOUNT" \
        --role="roles/secretmanager.secretAccessor" \
        --project=$PROJECT_ID \
        --quiet
done

echo -e "${GREEN}   ✅ Permisos configurados${NC}"

# =============================================================================
# CREAR CLOUD SCHEDULER
# =============================================================================

echo ""
echo -e "${YELLOW}⏰ Configurando Cloud Scheduler...${NC}"

# Cloud Scheduler no está disponible en Madrid (europe-southwest1)
# Usamos europe-west1 (Bélgica) - la latencia no importa para un scheduler
SCHEDULER_REGION="europe-west1"

# Crear el job de scheduler (o actualizar si existe)
JOB_NAME="padel-booker-trigger"

# Cron: minuto hora día-del-mes mes día-de-la-semana
# Ejemplo: "0 0 * * 2,4" = A las 00:00, todos los meses, martes y jueves
CRON_EXPRESSION="$EXEC_MIN $EXEC_HOUR * * $CRON_DAYS"

# Eliminar job existente si existe
gcloud scheduler jobs delete $JOB_NAME --location=$SCHEDULER_REGION --quiet 2>/dev/null || true

# Crear nuevo job
gcloud scheduler jobs create http $JOB_NAME \
    --location=$SCHEDULER_REGION \
    --schedule="$CRON_EXPRESSION" \
    --time-zone="Europe/Madrid" \
    --uri="$FUNCTION_URL" \
    --http-method=POST \
    --oidc-service-account-email="$SERVICE_ACCOUNT" \
    --quiet

echo -e "${GREEN}   ✅ Cloud Scheduler configurado${NC}"
echo "   📅 Cron: $CRON_EXPRESSION (Europe/Madrid)"
echo "   📍 Región Scheduler: $SCHEDULER_REGION"

# =============================================================================
# RESUMEN FINAL
# =============================================================================

echo ""
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              ✅ DESPLIEGUE COMPLETADO ✅                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "📊 Recursos creados:"
echo "   • Cloud Function: padel-booker"
echo "   • Cloud Scheduler: $JOB_NAME"
echo "   • Secretos: padel-alias, padel-dni, padel-password"
echo ""
echo "🔧 Comandos útiles:"
echo ""
echo "   # Ver logs de la función"
echo "   gcloud functions logs read padel-booker --region=$REGION --gen2"
echo ""
echo "   # Ejecutar manualmente (test)"
echo "   gcloud scheduler jobs run $JOB_NAME --location=$SCHEDULER_REGION"
echo ""
echo "   # Ver estado del scheduler"
echo "   gcloud scheduler jobs describe $JOB_NAME --location=$SCHEDULER_REGION"
echo ""
echo "   # Actualizar horario de pádel"
echo "   gcloud functions deploy padel-booker --region=$REGION --update-env-vars=PADEL_SCHEDULE=19:00-20:00"
echo ""
echo "   # Eliminar todo"
echo "   gcloud scheduler jobs delete $JOB_NAME --location=$SCHEDULER_REGION"
echo "   gcloud functions delete padel-booker --region=$REGION --gen2"
echo ""
echo "💰 Coste estimado: ~\$0.01-0.10/mes"
echo ""
