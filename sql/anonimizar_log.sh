#!/usr/bin/env bash
# =====================================================================
# anonimizar_log.sh — Food Store, TP Unidad 5 (Parte C, punto 3)
# Recorta el tramo del simulacro de un log crudo del servidor y lo anonimiza
# antes de dárselo a un asistente de IA.
#
# Uso (desde la raíz del repo):
#   sql/anonimizar_log.sh <log_crudo> [salida]
#   salida por defecto: docs/log_simulacro_anonimizado.txt
#
# El log crudo NUNCA se guarda dentro del repositorio ni se commitea.
# Obtenerlo con (Git Bash; guardarlo fuera del repo, por ejemplo en $TEMP):
#   psql -U postgres -d bd2_tp5u5 -X -At -c \
#     "SELECT convert_from(pg_read_binary_file(pg_current_logfile()), 'WIN1252');" > "$TEMP/log_crudo.txt"
#
# Qué reemplaza:
#   * mails                      -> usuario_NNN@ejemplo.test (mismo mail = mismo valor)
#   * 2.º argumento de fn_autenticar (la contraseña) -> CLAVE_REDACTADA
#   * puertos del cliente        -> PUERTO
#   * IPv4 distintas de 127.0.0.1 -> IP_ANONIMA
#   * rutas de Windows al archivo pg_hba.conf -> <RUTA>/pg_hba.conf
# Se conservan marcas de tiempo y PID: sin ellos no se puede reconstruir la secuencia.
#
# IMPORTANTE: revisar el resultado a ojo antes de usarlo (ver el final del script).
# =====================================================================
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Uso: $0 <log_crudo> [salida]" >&2
    exit 1
fi

ENTRADA="$1"
SALIDA="${2:-docs/log_simulacro_anonimizado.txt}"

[ -f "$ENTRADA" ] || { echo "No existe el archivo: $ENTRADA" >&2; exit 1; }

# Tramo entre las marcas del script del simulacro; si no están, se usa todo el log.
if grep -q "INICIO_SIMULACRO_U5" "$ENTRADA"; then
    TRAMO=$(awk '/INICIO_SIMULACRO_U5/{p=1} p{print} /FIN_SIMULACRO_U5/{if(p) exit}' "$ENTRADA")
else
    echo "Aviso: no se encontró INICIO_SIMULACRO_U5; se anonimiza el archivo completo." >&2
    TRAMO=$(cat "$ENTRADA")
fi

# Paso 1 (sed): contraseña, puertos, IPv4 y ruta del pg_hba.conf.
#   - contraseña: segundo argumento de fn_autenticar(mail, clave)
#   - IPv4: se protege 127.0.0.1, se reemplaza el resto y se restaura
# Paso 2 (awk): mails, con numeración estable (el mismo mail recibe siempre el mismo valor).
printf '%s\n' "$TRAMO" | LC_ALL=C sed -E \
    -e "s/(fn_autenticar\('[^']*', *')[^']*('\))/\1CLAVE_REDACTADA\2/g" \
    -e 's/\([0-9]+\)/(PUERTO)/g' \
    -e 's/port=[0-9]+/port=PUERTO/g' \
    -e 's/127\.0\.0\.1/LOOPBACK_TMP/g' \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/IP_ANONIMA/g' \
    -e 's/LOOPBACK_TMP/127.0.0.1/g' \
    -e 's#[A-Za-z]:/[^»)]*pg_hba\.conf#<RUTA>/pg_hba.conf#g' \
| LC_ALL=C awk '
function anon_mail(m) {
    if (!(m in mapa)) { n++; mapa[m] = sprintf("usuario_%03d@ejemplo.test", n) }
    return mapa[m]
}
{
    resultado = ""
    resto = $0
    # un mail se reconoce por tener punto en el dominio, así no toca usuario@base
    while (match(resto, /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/)) {
        resultado = resultado substr(resto, 1, RSTART - 1) anon_mail(substr(resto, RSTART, RLENGTH))
        resto = substr(resto, RSTART + RLENGTH)
    }
    print resultado resto
}' > "$SALIDA"

echo "Escrito: $SALIDA ($(wc -l < "$SALIDA") líneas)"
echo
echo "REVISAR A MANO antes de usarlo con una IA o de commitearlo:"
echo "  grep -n -iE 'clave|pass|@|apellido|nombre' \"$SALIDA\""
echo "  No debe quedar ningún mail real, nombre, contraseña ni ruta de tu máquina."
