"""
PadelBooker UPV - Cloud Function
Reserva automática de pistas de pádel en la UPV
"""

import os
import re
import requests
from datetime import datetime, timedelta
from html.parser import HTMLParser
from google.cloud import secretmanager


# =============================================================================
# CONFIGURACIÓN
# =============================================================================

# Horario a reservar (se puede sobrescribir con variable de entorno)
SCHEDULE = os.environ.get("PADEL_SCHEDULE", "20:00-21:00")

# Intentos de reserva
MAX_ATTEMPTS = 8
ATTEMPT_DELAY = 15  # segundos entre intentos

# URLs de la UPV
LOGIN_URL = "https://intranet.upv.es/pls/soalu/est_aute.intraalucomp"
PADEL_URL = "https://intranet.upv.es/pls/soalu/sic_depreservas.Reservar?p_res_tipo=PDEL&p_fecha={date}"


# =============================================================================
# PARSER HTML PARA EXTRAER ENLACES DE RESERVA
# =============================================================================

class PadelLinkParser(HTMLParser):
    """Extrae los enlaces de reserva de pistas de pádel del HTML"""
    
    def __init__(self, target_time: str):
        super().__init__()
        self.target_time = target_time  # ej: "20:00"
        self.links = []
        self.in_target_row = False
        self.current_link = None
    
    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        
        # Buscar enlaces de reserva
        if tag == "a":
            href = attrs_dict.get("href", "")
            if "solicita_reservar" in href and f"p_res_horaini={self.target_time}:00" in href:
                # Decodificar &amp; a &
                clean_href = href.replace("&amp;", "&")
                if not clean_href.startswith("http"):
                    clean_href = "https://intranet.upv.es" + clean_href
                self.links.append(clean_href)
    
    def get_booking_links(self):
        return self.links


# =============================================================================
# FUNCIONES PRINCIPALES
# =============================================================================

def get_credentials():
    """Obtiene las credenciales desde Secret Manager"""
    client = secretmanager.SecretManagerServiceClient()
    
    project_id = os.environ.get("GCP_PROJECT")
    
    # Obtener cada secreto
    secrets = {}
    for secret_name in ["padel-alias", "padel-dni", "padel-password"]:
        name = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
        response = client.access_secret_version(request={"name": name})
        secrets[secret_name] = response.payload.data.decode("UTF-8")
    
    return secrets["padel-alias"], secrets["padel-dni"], secrets["padel-password"]


def login(session: requests.Session, alias: str, dni: str, password: str) -> bool:
    """Realiza login en la intranet UPV"""
    
    data = {
        "id": "c",
        "estession": "",
        "p_usuario": dni,
        "p_clave": password
    }
    
    headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }
    
    response = session.post(LOGIN_URL, data=data, headers=headers, allow_redirects=True)
    
    # Verificar login exitoso
    if response.status_code == 200:
        content = response.text.lower()
        if "col_horarios" in content or "depreservas" in content or "reserva" in content:
            print(f"✅ Login exitoso para {alias}")
            return True
    
    print(f"❌ Login fallido para {alias}")
    return False


def get_booking_page(session: requests.Session, date: str) -> str:
    """Descarga la página de reservas de pádel para una fecha"""
    
    url = PADEL_URL.format(date=date)
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }
    
    response = session.get(url, headers=headers)
    
    if response.status_code == 200:
        # La página usa ISO-8859-15
        response.encoding = "iso-8859-15"
        return response.text
    
    return None


def find_available_courts(html: str, target_time: str) -> list:
    """Busca pistas disponibles para el horario especificado"""
    
    parser = PadelLinkParser(target_time)
    parser.feed(html)
    
    return parser.get_booking_links()


def make_booking(session: requests.Session, booking_url: str) -> bool:
    """Intenta realizar una reserva"""
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }
    
    response = session.get(booking_url, headers=headers, allow_redirects=True)
    
    if response.status_code == 200:
        content = response.text.lower()
        # Verificar si la reserva fue exitosa
        if "reserva realizada" in content or "confirmada" in content or "éxito" in content:
            return True
        # También puede redirigir a la página de confirmación
        if "solicita_reservar" not in response.url:
            return True
    
    return False


def book_padel(date: str, schedule: str) -> dict:
    """
    Función principal de reserva
    
    Args:
        date: Fecha a reservar (YYYY-MM-DD)
        schedule: Horario deseado (HH:MM-HH:MM)
    
    Returns:
        dict con resultado de la operación
    """
    
    # Extraer hora de inicio del horario
    start_time = schedule.split("-")[0]  # "20:00-21:00" -> "20:00"
    
    print(f"🎾 PadelBooker UPV")
    print(f"📅 Fecha: {date}")
    print(f"⏰ Horario: {schedule}")
    print("")
    
    # Obtener credenciales
    try:
        alias, dni, password = get_credentials()
        print(f"👤 Usuario: {alias}")
    except Exception as e:
        return {"success": False, "error": f"Error obteniendo credenciales: {str(e)}"}
    
    # Crear sesión
    session = requests.Session()
    
    # Login
    if not login(session, alias, dni, password):
        return {"success": False, "error": "Login fallido"}
    
    # Intentar reservar
    import time
    
    for attempt in range(1, MAX_ATTEMPTS + 1):
        print(f"\n🔄 Intento {attempt}/{MAX_ATTEMPTS}...")
        
        # Descargar página de reservas
        html = get_booking_page(session, date)
        
        if not html:
            print("   ⚠️ No se pudo descargar la página")
            time.sleep(ATTEMPT_DELAY)
            continue
        
        # Buscar pistas disponibles
        available_courts = find_available_courts(html, start_time)
        
        if not available_courts:
            print(f"   ⚠️ No hay pistas disponibles para {start_time}")
            time.sleep(ATTEMPT_DELAY)
            continue
        
        print(f"   ✅ Encontradas {len(available_courts)} pistas disponibles")
        
        # Intentar reservar la primera pista disponible
        for court_url in available_courts:
            print(f"   🎯 Intentando reservar...")
            
            if make_booking(session, court_url):
                print(f"\n🎉 ¡RESERVA EXITOSA!")
                print(f"   Fecha: {date}")
                print(f"   Horario: {schedule}")
                return {
                    "success": True,
                    "date": date,
                    "schedule": schedule,
                    "message": "Reserva realizada correctamente"
                }
        
        print(f"   ❌ No se pudo completar la reserva")
        time.sleep(ATTEMPT_DELAY)
    
    return {
        "success": False,
        "error": f"No se pudo reservar después de {MAX_ATTEMPTS} intentos"
    }


# =============================================================================
# ENTRY POINT - CLOUD FUNCTION
# =============================================================================

def padel_booker(request):
    """
    Cloud Function HTTP entry point
    
    Se ejecuta cuando Cloud Scheduler hace la llamada.
    Cloud Scheduler ya está programado para ejecutarse 8 días antes,
    así que reservamos para hoy + 8 días (el día de juego).
    """
    
    # Calcular fecha a reservar (8 días desde hoy = día de juego)
    target_date = datetime.now() + timedelta(days=8)
    date_str = target_date.strftime("%Y-%m-%d")
    
    # Obtener horario de variable de entorno o usar default
    schedule = os.environ.get("PADEL_SCHEDULE", SCHEDULE)
    
    print(f"🚀 Cloud Function iniciada")
    print(f"📆 Fecha objetivo: {date_str} ({target_date.strftime('%A')})")
    
    # Ejecutar reserva
    result = book_padel(date_str, schedule)
    
    # Devolver resultado
    if result["success"]:
        return (result, 200)
    else:
        return (result, 500)


# Para testing local
if __name__ == "__main__":
    import sys
    
    # Si se pasa fecha como argumento, usarla
    if len(sys.argv) > 1:
        test_date = sys.argv[1]
    else:
        test_date = (datetime.now() + timedelta(days=8)).strftime("%Y-%m-%d")
    
    print(f"🧪 Modo test local - Fecha: {test_date}")
    result = book_padel(test_date, SCHEDULE)
    print(f"\nResultado: {result}")
