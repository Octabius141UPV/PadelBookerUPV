#!/bin/bash

# Script de reservas para las pistas de padel de la UPV (basado en GymBookerUPV)

# Colores
greenColour="\e[0;32m\033[1m"
endColour="\033[0m\e[0m"
redColour="\e[0;31m\033[1m"
blueColour="\e[0;34m\033[1m"
yellowColour="\e[0;33m\033[1m"
purpleColour="\e[0;35m\033[1m"
turquoiseColour="\e[0;36m\033[1m"
grayColour="\e[0;37m\033[1m"

function ctrl_c(){
    echo -e "\n${redColour}[!] Saliendo...${endColour}"
    rm *_cookies.txt 2>/dev/null
    tput cnorm 2>/dev/null ; exit 1
}

trap ctrl_c INT

# Configuracion
log_in="https://intranet.upv.es/pls/soalu/est_aute.intraalucomp"
credentials_file="credentials.txt"        # Alias : DNI : Password
groups_file="padel_groups.txt"            # Lista de grupos a reservar, una linea por cuenta

# URL base de reservas de pádel (sin fecha). El día se inyecta dinámicamente.
sports_base="https://intranet.upv.es/pls/soalu/sic_depreservas.reservas?p_vista=intranet&p_idioma=c&p_fil_campus=V&p_fil_deporte=279&p_sel_pag=1&p_sel_pista="

# Prefijo que aparece antes del numero de grupo en el href de la pagina (dejalo vacio si no hay prefijo)
group_prefix=""

# Momento en el que se liberan las reservas (00:00, 8 dias antes del dia de juego)
release_offset_days=8
release_time="09:00"
book_date="${BOOK_DATE:-}"   # BOOK_DATE=YYYY-MM-DD para reservar ya (sin esperar)
skip_sudo="${SKIP_SUDO:-0}"
debug="${DEBUG:-0}"
dry_run="${DRY_RUN:-0}"   # DRY_RUN=1 para solo mostrar el enlace sin reservar

# Días de la semana permitidos para reservar (en inglés)
# Opciones: Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday
# Dejar vacío para permitir todos los días
allowed_weekdays="Tuesday Thursday"

attempts=8           # Numero de rondas de reserva cuando se abre el plazo
attempt_delay=15     # Segundos entre rondas
check_interval=60    # Segundos entre comprobaciones mientras se espera

function validate_setup(){
    if [[ "$sports_base" == *"XXXX"* || "$sports_base" == *"YYYY"* ]]; then
        echo -e "\n${redColour}[!] Configura sports_base con los valores reales de padel antes de ejecutar${endColour}"
        ctrl_c
    fi

    if [ ! -e "$credentials_file" ] || [ ! -e "$groups_file" ]; then
        echo -e "\n${redColour}[!] Faltan $credentials_file o $groups_file${endColour}"
        ctrl_c
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "\n${redColour}[!] Necesito python3 para calcular la siguiente ventana de apertura${endColour}"
        ctrl_c
    fi
}

function hour(){
	echo -ne "\n${grayColour}[$(date | awk '{print $4}')] ${endColour}"
}

function set_timezone(){
    if [ "$skip_sudo" = "1" ]; then
        return
    fi
    sudo timedatectl set-timezone Europe/Madrid > /dev/null 2>&1
}

function sports_url_for_date(){
    local date_iso="$1"  # YYYY-MM-DD
    if [ -z "$date_iso" ]; then
        echo "$sports_base"
        return
    fi
    # Convertir a DD/MM/YYYY
    local date_short
    date_short=$(python3 - "$date_iso" <<'PY'
import datetime, sys
try:
    d=datetime.date.fromisoformat(sys.argv[1])
    print(d.strftime("%d/%m/%Y"))
except Exception:
    sys.exit(1)
PY
)
    if [ -z "$date_short" ]; then
        echo "$sports_base"
        return
    fi
    echo "${sports_base}&p_sel_dia=${date_short}#filtro"
}

function weekday_for_group(){
    local number="$1"
    # Si no es un número (ej: es una hora como 10:30-11:30), retornar vacío sin error
    if ! [[ "$number" =~ ^[0-9]+$ ]]; then
        echo ""
        return 1
    fi
    if (( number >= 1 && number <= 14 )); then echo "Monday" ; return 0; fi
    if (( number >= 15 && number <= 28 )); then echo "Tuesday" ; return 0; fi
    if (( number >= 29 && number <= 42 )); then echo "Wednesday" ; return 0; fi
    if (( number >= 43 && number <= 56 )); then echo "Thursday" ; return 0; fi
    if (( number >= 57 && number <= 70 )); then echo "Friday" ; return 0; fi
    echo "" ; return 1
}

function next_release_epoch_for_weekday(){
    local play_weekday="$1"
    python3 - "$play_weekday" "$release_time" "$release_offset_days" <<'PY'
import datetime, sys
play_weekday, release_time_str, offset_days = sys.argv[1:]
offset_days = int(offset_days)
weekday_map = {"Monday": 0, "Tuesday": 1, "Wednesday": 2, "Thursday": 3, "Friday": 4, "Saturday": 5, "Sunday": 6}
if play_weekday not in weekday_map:
    sys.exit(1)
hour, minute = map(int, release_time_str.split(":"))
now = datetime.datetime.now()
target_idx = weekday_map[play_weekday]
days_ahead = (target_idx - now.weekday() + 7) % 7
play_date = now.date() + datetime.timedelta(days=days_ahead)
release_date = play_date - datetime.timedelta(days=offset_days)
release_dt = datetime.datetime.combine(release_date, datetime.time(hour, minute))
if release_dt <= now:
    play_date = play_date + datetime.timedelta(days=7)
    release_date = play_date - datetime.timedelta(days=offset_days)
    release_dt = datetime.datetime.combine(release_date, datetime.time(hour, minute))
print(f"{int(release_dt.timestamp())} {release_dt.isoformat()} {play_date.isoformat()}")
PY
}

function collect_weekdays(){
    local -a unique_weekdays=()
    while IFS= read -r line; do
        for number in $line; do
            local wd
            wd=$(weekday_for_group "$number")
            [ -z "$wd" ] && continue
            if [[ ! " ${unique_weekdays[*]} " =~ " $wd " ]]; then
                unique_weekdays+=("$wd")
            fi
        done
    done < "$groups_file"
    echo "${unique_weekdays[@]}"
}

function weekday_from_date(){
    local date_str="$1"
    python3 - "$date_str" <<'PY'
import datetime, sys
try:
    d = datetime.date.fromisoformat(sys.argv[1])
except Exception:
    sys.exit(1)
print(d.strftime("%A"))
PY
}

# Función para obtener los días de la semana a procesar
function get_target_weekdays(){
    # Si hay días permitidos configurados, usar esos
    if [ -n "$allowed_weekdays" ]; then
        echo "$allowed_weekdays"
        return
    fi
    # Si no, usar los días de los grupos numéricos (comportamiento original)
    collect_weekdays
}

function wait_for_release(){
    echo -e "\n${grayColour}[!] Esperando a la siguiente ventana de apertura (00:00, $release_offset_days días antes del día de juego)${endColour}"
    if [ -n "$allowed_weekdays" ]; then
        echo -e "${grayColour}[!] Días configurados: $allowed_weekdays${endColour}"
    fi
    while true; do
        set_timezone

        read -r -a weekdays <<< "$(get_target_weekdays)"
        if [ ${#weekdays[@]} -eq 0 ]; then
            echo -e "${redColour}[!] No hay días configurados para reservar${endColour}"
            ctrl_c
        fi

        next_ts=""
        next_wd=""
        next_iso=""
        next_play=""
        for wd in "${weekdays[@]}"; do
            read -r ts iso play <<< "$(next_release_epoch_for_weekday "$wd")"
            if [ -z "$next_ts" ] || [ "$ts" -lt "$next_ts" ]; then
                next_ts="$ts"
                next_wd="$wd"
                next_iso="$iso"
                next_play="$play"
            fi
        done

        now_ts=$(date +%s)
        wait_seconds=$(( next_ts - now_ts ))

        if [ "$wait_seconds" -le 0 ]; then
            echo -e "\n${greenColour}[!] ¡Apertura de reservas para $next_wd ($next_play)!${endColour}"
            for ((i = 1; i <= attempts; i++)); do
                echo -e "${blueColour}[*] Intento $i de $attempts${endColour}"
                booking "$next_wd" "$next_play"
                [ "$i" -lt "$attempts" ] && sleep "$attempt_delay"
            done
            # Esperar un poco antes de buscar la siguiente ventana
            sleep 60
            continue
        fi

        human_time=$(date -r "$next_ts" "+%Y-%m-%d %H:%M" 2>/dev/null)
        if [ -z "$human_time" ]; then
            human_time=$(python3 - "$next_ts" <<'PY'
import datetime, sys
ts=int(sys.argv[1])
print(datetime.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M"))
PY
)
        fi
        echo -e "\n${grayColour}[!] Próxima ventana: $next_wd ($next_play) a las $release_time${endColour}"
        echo -e "${grayColour}[!] Fecha de apertura: $human_time${endColour}"
        echo -e "${grayColour}[!] Faltan $wait_seconds segundos ($(( wait_seconds / 3600 ))h $(( (wait_seconds % 3600) / 60 ))m)${endColour}"

        sleep_chunk=$check_interval
        [ "$wait_seconds" -lt "$sleep_chunk" ] && sleep_chunk="$wait_seconds"
        sleep "$sleep_chunk"
    done
}

function booking(){
    local target_weekday="$1"
    local target_date="$2"  # YYYY-MM-DD
    set_timezone
    if [ "$debug" = "1" ]; then
        echo -e "${turquoiseColour}[DEBUG] target_weekday=$target_weekday target_date=$target_date${endColour}"
        echo -e "${turquoiseColour}[DEBUG] Contenido credentials_file:${endColour}"
        cat "$credentials_file"
        echo -e "${turquoiseColour}[DEBUG] Contenido groups_file:${endColour}"
        cat "$groups_file"
    fi
    
    # Leer ambos archivos en arrays (compatible con bash 3.x de macOS)
    local cred_lines=()
    local group_lines=()
    while IFS= read -r l || [ -n "$l" ]; do
        cred_lines+=("$l")
    done < "$credentials_file"
    while IFS= read -r l || [ -n "$l" ]; do
        group_lines+=("$l")
    done < "$groups_file"
    
    local num_accounts=${#cred_lines[@]}
    if [ "$debug" = "1" ]; then
        echo -e "${turquoiseColour}[DEBUG] Número de cuentas: $num_accounts${endColour}"
    fi
    
    local i=0
    while [ $i -lt $num_accounts ]; do
        local cred_line="${cred_lines[$i]}"
        local line="${group_lines[$i]:-}"
        i=$((i + 1))
        
        # Saltar líneas vacías
        [ -z "$cred_line" ] && continue
        [ -z "$line" ] && continue
        
        IFS=' ' read -r alias _ dni _ password <<< "$cred_line"
        
        if [ "$debug" = "1" ]; then
            echo -e "${turquoiseColour}[DEBUG] Leyendo cuenta alias=$alias dni=$dni line_grupos=\"$line\"${endColour}"
        fi
        hour ; echo -e "${blueColour}[*] Reservando para $alias ...${endColour}"
        curl -s -X POST "$log_in" -d "dni=$dni&clau=$password" -c "${alias}_cookies.txt" > /dev/null 2>&1

        # Leer la pagina completa una vez por cuenta
        page_url=$(sports_url_for_date "$target_date")
        if [ "$debug" = "1" ]; then
            echo -e "${turquoiseColour}[DEBUG] page_url=$page_url${endColour}"
        fi
        page=$(curl -s -X GET "$page_url" -b "${alias}_cookies.txt")
        if [ "$debug" = "1" ]; then
            echo -e "${turquoiseColour}[DEBUG] Longitud HTML descargado: ${#page} bytes${endColour}"
        fi
        if [ -z "$page" ]; then
            hour ; echo -e "\t${redColour}[!] No se pudo descargar la pagina de padel, ¿login fallido?${endColour}"
            if [ "$debug" = "1" ]; then
                echo -e "${purpleColour}[DEBUG] Contenido de login (cuerpo):${endColour}"
                cat "${alias}_cookies.txt" 2>/dev/null
            fi
            continue
        fi
        IFS=' ' read -ra numbers <<< "$line"
        for number in "${numbers[@]}"; do
            group_weekday=$(weekday_for_group "$number")
            # Si hay dia objetivo, filtra por weekday cuando sea un grupo numerico; las cadenas (horas) pasan sin filtro
            # Si group_weekday está vacío (es una hora como 08:00-09:00), NO filtramos
            if [ -n "$target_weekday" ] && [ -n "$group_weekday" ] && [ "$group_weekday" != "$target_weekday" ]; then
                if [ "$debug" = "1" ]; then
                    echo -e "${turquoiseColour}[DEBUG] Saltando grupo $number (weekday $group_weekday != $target_weekday)${endColour}"
                fi
                continue
            fi

            group_pattern="${group_prefix}${number}"
            hour ; echo -e "\t${yellowColour}[!] Buscando grupo $group_pattern en $page_url ...${endColour}"
            # Primero intento el patrón antiguo (href en la misma linea que el identificador)
            book_path=$(echo "$page" | grep -e "$group_pattern" | awk '{print $3}' | sed 's/href=\"//g; s/\"//g')

            # Si no hay resultado y el patrón parece una hora (contiene ":"), parseo por celda de horario
            if [ -z "$book_path" ] && [[ "$group_pattern" == *":"* ]]; then
                # Guardar HTML en archivo temporal para que Python pueda leerlo con la codificación correcta
                local tmp_html="/tmp/padel_search_$$.html"
                echo "$page" > "$tmp_html"
                
                if [ "$debug" = "1" ]; then
                    cp "$tmp_html" /tmp/padel_debug.html
                    echo -e "${turquoiseColour}[DEBUG] HTML guardado en /tmp/padel_debug.html${endColour}"
                fi
                
                book_path=$(python3 - "$group_pattern" "$tmp_html" <<'PY'
import re, sys

target = sys.argv[1]  # ej: "10:30-11:30"
html_file = sys.argv[2]

# Leer con codificación iso-8859-15
try:
    with open(html_file, 'r', encoding='iso-8859-15', errors='ignore') as f:
        html = f.read()
except:
    with open(html_file, 'r', errors='ignore') as f:
        html = f.read()

# Extraer solo la hora de inicio (antes del guión)
hora_inicio = target.split('-')[0]  # "10:30"

# Buscar el enlace de reserva que contenga esa hora de inicio
pattern = rf'href="([^"]*solicita_reservar[^"]*p_res_horaini={re.escape(hora_inicio)}:00[^"]*)"'
m = re.search(pattern, html)
if m:
    url = m.group(1).replace('&amp;', '&')
    print(url)
    sys.exit(0)

# Método alternativo sin :00
pattern2 = rf'href="([^"]*solicita_reservar[^"]*p_res_horaini={re.escape(hora_inicio)}[^"]*)"'
m2 = re.search(pattern2, html)
if m2:
    url = m2.group(1).replace('&amp;', '&')
    print(url)
    sys.exit(0)

sys.exit(0)
PY
)
                rm -f "$tmp_html"
            fi

            if [ -z "$book_path" ]; then
                if [ "$debug" = "1" ]; then
                    echo -e "${purpleColour}[DEBUG] No se encontró href para $group_pattern${endColour}"
                fi
                hour ; echo -e "\t${redColour}[!] Grupo $group_pattern no encontrado en la pagina de padel${endColour}"
                continue
            fi

            book_url="https://intranet.upv.es/pls/soalu/$book_path"
            
            # Modo dry-run: solo mostrar el enlace sin reservar
            if [ "$dry_run" = "1" ]; then
                hour ; echo -e "\t${greenColour}[DRY-RUN] Encontrado enlace de reserva:${endColour}"
                echo -e "\t${turquoiseColour}$book_url${endColour}"
                hour ; echo -e "\t${yellowColour}[DRY-RUN] No se ha hecho click (modo prueba)${endColour}"
                continue
            fi
            
            hour ; echo -e "\t${blueColour}[*] Llamando a $book_url ${endColour}"
            curl -s -X GET "$book_url" -b "${alias}_cookies.txt" > /dev/null 2>&1

            # Comprobar inscripcion actualizada
            page=$(curl -s -X GET "$page_url" -b "${alias}_cookies.txt")
            if echo "$page" | grep -e "$group_pattern" | grep -q "inscrito"; then
                hour ; echo -e "\t${greenColour}[+] Grupo $group_pattern reservado${endColour}"
            else
                hour ; echo -e "\t${redColour}[!] No se pudo reservar el grupo $group_pattern${endColour}"
                if [ "$debug" = "1" ]; then
                    echo -e "${purpleColour}[DEBUG] Resumen de celda para $group_pattern:${endColour}"
                    echo "$page" | python3 - "$group_pattern" <<'PY'
import re, sys
html=sys.stdin.read()
target=sys.argv[1]
pat=rf'<td class="col_horarios">{re.escape(target)}</td>\\s*<td class="col_horarios">(?P<cell>.*?)</td>'
m=re.search(pat, html, re.S)
if m:
    cell=m.group('cell')
    print(cell.strip())
else:
    print("CELDA NO ENCONTRADA")
PY
                fi
            fi
        done
        rm "${alias}_cookies.txt" 2>/dev/null
    done
}

tput civis 2>/dev/null
validate_setup

while IFS=' ' read -r alias _ dni _ password || [ -n "$alias" ]; do
    # Saltar líneas vacías
    [ -z "$alias" ] && continue
    
    login_headers="/tmp/padel_login_${alias}_headers.txt"
    login_body="/tmp/padel_login_${alias}_body.html"
    curl -s -D "$login_headers" -c "${alias}_cookies.txt" -X POST "$log_in" -d "dni=$dni&clau=$password" -o "$login_body"
    
    # Verificar login: intentar acceder a una página protegida y ver si hay contenido válido
    test_page=$(curl -s -b "${alias}_cookies.txt" "https://intranet.upv.es/pls/soalu/sic_depreservas.reservas?p_vista=intranet&p_idioma=c&p_fil_campus=V&p_fil_deporte=279")
    
    # Si la página contiene "col_horarios" o "reservas", el login fue exitoso
    if echo "$test_page" | grep -qi "col_horarios\|depreservas\|reserva"; then
        echo -e "\n${greenColour}[+] Login de $alias correcto${endColour}"
        if [ "$debug" = "1" ]; then
            echo -e "${turquoiseColour}[DEBUG] Cabeceras login guardadas en $login_headers${endColour}"
            echo -e "${turquoiseColour}[DEBUG] Cuerpo login guardado en $login_body${endColour}"
        else
            rm -f "$login_headers" "$login_body"
        fi
        sleep 1
    else
        echo -e "\n${redColour}[!] Login de $alias incorrecto${endColour}"
        if [ "$debug" = "1" ]; then
            echo -e "${purpleColour}[DEBUG] Revisa los ficheros de login:${endColour}"
            echo "  $login_headers"
            echo "  $login_body"
            echo -e "${purpleColour}[DEBUG] Respuesta test_page (primeros 500 chars):${endColour}"
            echo "$test_page" | head -c 500
        else
            rm -f "$login_headers" "$login_body"
        fi
        ctrl_c
    fi
done < "$credentials_file"

sleep 2
[ "$debug" = "1" ] || clear

# Modo inmediato para pruebas: BOOK_DATE=YYYY-MM-DD ./multiPadelBooker.sh
if [ -n "$book_date" ]; then
    target_weekday="$(weekday_from_date "$book_date")"
    if [ -z "$target_weekday" ]; then
        echo -e "${redColour}[!] Formato BOOK_DATE inválido, usa YYYY-MM-DD${endColour}"
        ctrl_c
    fi
    echo -e "\n${yellowColour}[!] Modo inmediato: intentando reservar para el día $book_date ($target_weekday) sin esperar apertura${endColour}"
    booking "$target_weekday" "$book_date"
    exit 0
fi

wait_for_release
