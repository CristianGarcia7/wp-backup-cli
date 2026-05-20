#!/bin/bash
# ═══════════════════════════════════════════════════════
# WP-BACKUP-CLI — Comando wpb v4.0
# ═══════════════════════════════════════════════════════

CONFIG_DIR="/etc/wp-backup"
SITES_FILE="$CONFIG_DIR/sites.conf"
SCRIPTS_DIR="/usr/local/bin"
LOG_FILE="/var/log/wp-backup.log"
MAX_BACKUPS=2
CMD=$1

# ── Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

header() {
  echo ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════╗${NC}"
  echo -e "${CYAN}${BOLD}║       WP-BACKUP-CLI  v4.0            ║${NC}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════╝${NC}"
  echo ""
}

# ── Helpers internos

save_site_credentials() {
  local site=$1 pass=$2
  printf 'DB_PASS=%s\n' "$(printf '%q' "$pass")" > "$CONFIG_DIR/$site.env"
  chmod 600 "$CONFIG_DIR/$site.env"
}

generate_backup_script() {
  local site=$1 wp_path=$2 bucket=$3 db_name=$4 db_user=$5
  cat > "$SCRIPTS_DIR/wp-backup-$site.sh" << SCRIPT
#!/bin/bash
source /etc/wp-backup/$site.env
WP_PATH="$wp_path"
S3_BUCKET="$bucket"
SITE_NAME="$site"
DB_NAME="$db_name"
DB_USER="$db_user"
DATE=\$(date +%Y-%m-%d_%H-%M-%S)
LOG="/var/log/wp-backup.log"
MAX_BACKUPS=$MAX_BACKUPS

echo "\$(date) - 🚀 Iniciando backup \$SITE_NAME" >> \$LOG

mysqldump -u "\$DB_USER" -p"\$DB_PASS" "\$DB_NAME" 2>/dev/null \
  | gzip \
  | aws s3 cp - "s3://\$S3_BUCKET/\$SITE_NAME/db/\$DATE.sql.gz" --quiet

if [ \${PIPESTATUS[0]} -eq 0 ]; then
  echo "\$(date) - ✅ BD exportada: \$SITE_NAME" >> \$LOG
  BACKUPS=\$(aws s3 ls "s3://\$S3_BUCKET/\$SITE_NAME/db/" | sort | awk '{print \$4}')
  COUNT=\$(echo "\$BACKUPS" | grep -c ".sql.gz" || true)
  if [ "\$COUNT" -gt "\$MAX_BACKUPS" ]; then
    TO_DELETE=\$((COUNT - MAX_BACKUPS))
    echo "\$BACKUPS" | grep ".sql.gz" | head -n \$TO_DELETE | while read -r OLD; do
      aws s3 rm "s3://\$S3_BUCKET/\$SITE_NAME/db/\$OLD" --quiet
      echo "\$(date) - 🗑️  BD antigua borrada: \$OLD" >> \$LOG
    done
  fi
else
  echo "\$(date) - ❌ ERROR exportando BD: \$SITE_NAME" >> \$LOG
  exit 1
fi

if aws s3 sync "\$WP_PATH" "s3://\$S3_BUCKET/\$SITE_NAME/files/" \
  --exclude "wp-content/cache/*" \
  --exclude "wp-content/uploads/cache/*" \
  --quiet; then
  echo "\$(date) - ✅ Backup completado: \$SITE_NAME" >> \$LOG
else
  echo "\$(date) - ❌ ERROR sincronizando archivos: \$SITE_NAME" >> \$LOG
  exit 1
fi
SCRIPT
  chmod +x "$SCRIPTS_DIR/wp-backup-$site.sh"
}

usage() {
  header
  echo -e "${BOLD}Uso:${NC} wpb <comando> [opciones]"
  echo ""
  echo -e "${BOLD}Comandos:${NC}"
  echo -e "  ${GREEN}add${NC} <sitio> <ruta> <bucket>   Agregar un sitio WordPress"
  echo -e "  ${GREEN}restore${NC} <sitio>               Restaurar un sitio desde S3"
  echo -e "  ${GREEN}recover${NC} <bucket>              Recuperar lista de sitios en instancia nueva"
  echo -e "  ${GREEN}list${NC}                          Ver todos los sitios registrados"
  echo -e "  ${GREEN}run${NC} <sitio>                   Correr backup ahora"
  echo -e "  ${GREEN}run-all${NC}                       Correr backup de todos"
  echo -e "  ${GREEN}status${NC}                        Ver estado de backups"
  echo -e "  ${GREEN}monitor${NC}                       Ver alertas y salud S3"
  echo -e "  ${GREEN}logs${NC}                          Ver logs"
  echo -e "  ${GREEN}remove${NC} <sitio>                Eliminar un sitio"
  echo -e "  ${GREEN}help${NC}                          Mostrar esta ayuda"
  echo ""
  echo -e "${BOLD}Emergencia (instancia nueva):${NC}"
  echo -e "  ${YELLOW}wpb recover backups-produ${NC}   → recupera la lista de sitios desde S3"
  echo -e "  ${YELLOW}wpb restore postobon${NC}        → restaura el sitio"
  echo ""
}

# ══════════════════════════════════════
# ADD
# ══════════════════════════════════════
cmd_add() {
  SITE_NAME=$1
  WP_PATH=$2
  S3_BUCKET=$3

  if [ -n "$SITE_NAME" ] && [[ ! "$SITE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}❌ Nombre inválido: '$SITE_NAME'${NC}"
    echo -e "   Solo se permiten letras, números, guiones ( - ) y guiones bajos ( _ )"
    exit 1
  fi

  if [ -z "$SITE_NAME" ]; then
    header
    echo -e "${BOLD}📖 Cómo usar wpb add:${NC}"
    echo ""
    echo -e "  ${YELLOW}wpb add <nombre> <ruta> <bucket>${NC}"
    echo ""
    echo -e "${BOLD}Parámetros:${NC}"
    echo -e "  ${CYAN}<nombre>${NC}   Nombre corto para identificar el sitio (sin espacios)"
    echo -e "             Ejemplos: postobon, natumalta-stg, cliente-juan"
    echo ""
    echo -e "  ${CYAN}<ruta>${NC}     Ruta completa donde está WordPress en el servidor"
    echo -e "             En HestiaCP la estructura es siempre:"
    echo -e "             ${YELLOW}/home/<usuario>/web/<dominio>/public_html${NC}"
    echo ""
    echo -e "  ${CYAN}<bucket>${NC}   Nombre del bucket S3 donde se guardan los backups"
    echo -e "             Ejemplo: backups-produ"
    echo ""
    echo -e "${BOLD}Ejemplos reales:${NC}"
    echo -e "  ${GREEN}wpb add postobon /home/postobon/web/postobon.quadi.io/public_html backups-produ${NC}"
    echo -e "  ${GREEN}wpb add natumalta /home/natumalta/web/natumalta-stg.quadi.io/public_html backups-produ${NC}"
    echo -e "  ${GREEN}wpb add bbdo /home/bbdo/web/bbdo.quadi.io/public_html backups-produ${NC}"
    echo ""
    echo -e "${BOLD}¿No sabes la ruta exacta?${NC} Corre esto:"
    echo -e "  ${CYAN}find /home/*/web/*/public_html -name \"wp-config.php\" 2>/dev/null${NC}"
    echo ""
    exit 0
  fi

  if [ -z "$WP_PATH" ] || [ -z "$S3_BUCKET" ]; then
    echo ""
    echo -e "${RED}❌ Faltan parámetros.${NC}"
    echo ""
    echo -e "  Uso: ${YELLOW}wpb add <nombre> <ruta> <bucket>${NC}"
    echo -e "  Ej:  ${GREEN}wpb add postobon /home/postobon/web/postobon.quadi.io/public_html backups-produ${NC}"
    echo ""
    echo -e "  En HestiaCP la ruta siempre es:"
    echo -e "  ${CYAN}/home/<usuario>/web/<dominio>/public_html${NC}"
    echo ""
    echo -e "  Para ver todas las rutas:"
    echo -e "  ${CYAN}find /home/*/web/*/public_html -name \"wp-config.php\" 2>/dev/null${NC}"
    echo ""
    exit 1
  fi

  if [ ! -d "$WP_PATH" ]; then
    echo ""
    echo -e "${RED}❌ La ruta no existe:${NC} $WP_PATH"
    echo ""
    echo -e "  En HestiaCP la ruta siempre es:"
    echo -e "  ${CYAN}/home/<usuario>/web/<dominio>/public_html${NC}"
    echo ""
    echo -e "  Para ver todas las rutas:"
    echo -e "  ${CYAN}find /home/*/web/*/public_html -name \"wp-config.php\" 2>/dev/null${NC}"
    echo ""
    exit 1
  fi

  if [ ! -f "$WP_PATH/wp-config.php" ]; then
    echo -e "${RED}❌ No es un WordPress válido${NC} (no hay wp-config.php en $WP_PATH)"
    exit 1
  fi

  if grep -qF "^$SITE_NAME:" "$SITES_FILE" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  El sitio '$SITE_NAME' ya está registrado${NC}"
    echo -e "   Usa ${CYAN}wpb remove $SITE_NAME${NC} primero si quieres reconfigurarlo"
    exit 1
  fi

  echo -e "🔧 Configurando ${BOLD}$SITE_NAME${NC}..."

  DB_NAME=$(grep "DB_NAME" "$WP_PATH/wp-config.php" | grep "define" | tr '"' "'" | cut -d"'" -f4)
  DB_USER=$(grep "DB_USER" "$WP_PATH/wp-config.php" | grep "define" | grep -v "DB_USERNAME" | tr '"' "'" | cut -d"'" -f4)
  DB_PASS=$(grep "DB_PASSWORD" "$WP_PATH/wp-config.php" | grep "define" | tr '"' "'" | cut -d"'" -f4)

  if [ -z "$DB_NAME" ]; then
    echo -e "${RED}❌ No se pudo leer wp-config.php${NC}"
    exit 1
  fi

  echo -e "   📋 Base de datos: ${CYAN}$DB_NAME${NC}"
  echo -e "   👤 Usuario:       ${CYAN}$DB_USER${NC}"

  echo -e "   🔐 Configurando permisos MySQL..."
  mariadb -u root -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null \
    || mysql -u root -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null \
    && echo -e "   ✅ Permisos MySQL configurados" \
    || echo -e "   ${YELLOW}⚠️  Configura permisos MySQL manualmente${NC}"

  save_site_credentials "$SITE_NAME" "$DB_PASS"
  generate_backup_script "$SITE_NAME" "$WP_PATH" "$S3_BUCKET" "$DB_NAME" "$DB_USER"
  echo "$SITE_NAME:$WP_PATH:$S3_BUCKET" >> "$SITES_FILE"

  # Guardar sites.conf en S3 para recuperación de emergencia
  aws s3 cp "$SITES_FILE" "s3://$S3_BUCKET/_config/sites.conf" --quiet \
    && echo -e "   ✅ Configuración guardada en S3" \
    || echo -e "   ${YELLOW}⚠️  No se pudo guardar configuración en S3${NC}"

  (crontab -l 2>/dev/null; echo "0 2 * * * $SCRIPTS_DIR/wp-backup-$SITE_NAME.sh") | crontab -

  echo ""
  echo -e "   ✅ Script:    ${CYAN}$SCRIPTS_DIR/wp-backup-$SITE_NAME.sh${NC}"
  echo -e "   ✅ Cron:      ${CYAN}todos los días a las 2 AM${NC}"
  echo -e "   ✅ Bucket:    ${CYAN}s3://$S3_BUCKET/$SITE_NAME/${NC}"
  echo -e "   ✅ Retención: ${CYAN}últimas $MAX_BACKUPS copias de BD${NC}"
  echo ""
  echo -e "${GREEN}${BOLD}✅ '$SITE_NAME' agregado correctamente${NC}"
  echo ""
  echo -e "Corre el primer backup con: ${YELLOW}wpb run $SITE_NAME${NC}"
  echo ""
}

# ══════════════════════════════════════
# RECOVER — para instancia nueva
# ══════════════════════════════════════
cmd_recover() {
  S3_BUCKET=$1

  if [ -z "$S3_BUCKET" ]; then
    echo ""
    echo -e "${RED}❌ Especifica el bucket S3${NC}"
    echo -e "   Uso: ${YELLOW}wpb recover <bucket>${NC}"
    echo -e "   Ej:  ${GREEN}wpb recover backups-produ${NC}"
    echo ""
    exit 1
  fi

  header
  echo -e "🔄 Recuperando configuración desde ${CYAN}s3://$S3_BUCKET${NC}..."
  echo ""

  # Verificar acceso a S3
  if ! aws s3 ls "s3://$S3_BUCKET" &>/dev/null; then
    echo -e "${RED}❌ No se puede acceder al bucket '$S3_BUCKET'${NC}"
    echo -e "   Verifica que esta instancia tiene el IAM Role correcto"
    exit 1
  fi

  # Buscar sites.conf en S3
  if aws s3 ls "s3://$S3_BUCKET/_config/sites.conf" &>/dev/null; then
    echo -e "   ✅ Configuración encontrada en S3"
    aws s3 cp "s3://$S3_BUCKET/_config/sites.conf" "$SITES_FILE" --quiet
    echo -e "   ✅ Lista de sitios recuperada"
  else
    # Si no hay sites.conf, detectar sitios por carpetas en S3
    echo -e "   ${YELLOW}⚠️  No hay archivo de configuración guardado${NC}"
    echo -e "   🔍 Detectando sitios desde las carpetas de S3..."
    echo "# Recuperado automáticamente desde S3" > "$SITES_FILE"
    aws s3 ls "s3://$S3_BUCKET/" | grep "PRE" | awk '{print $2}' | sed 's/\///' | while read -r SITE; do
      [ "$SITE" = "_config" ] && continue
      echo "$SITE:RUTA_DESCONOCIDA:$S3_BUCKET" >> "$SITES_FILE"
    done
    echo -e "   ${YELLOW}⚠️  Rutas desconocidas — deberás correr wpb add para cada sitio${NC}"
  fi

  echo ""
  echo -e "${BOLD}Sitios encontrados en S3:${NC}"
  echo ""

  COUNT=0
  while IFS=: read -r name path bucket; do
    [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
    COUNT=$((COUNT + 1))
    LAST_DB=$(aws s3 ls "s3://$S3_BUCKET/$name/db/" 2>/dev/null | sort | tail -1 | awk '{print $4}')
    echo -e "  ${CYAN}${BOLD}$name${NC}"
    echo -e "    Ruta:          $path"
    echo -e "    Último backup: ${LAST_DB:-No encontrado}"
    echo ""
  done < "$SITES_FILE"

  echo -e "Total: ${BOLD}$COUNT sitios${NC}"
  echo ""
  echo -e "${BOLD}¿Qué hacer ahora?${NC}"
  echo ""
  echo -e "  Si las rutas son correctas, restaura con:"
  echo -e "  ${YELLOW}wpb restore <nombre-sitio>${NC}"
  echo ""
  echo -e "  Si las rutas dicen RUTA_DESCONOCIDA, primero corre:"
  echo -e "  ${CYAN}find /home/*/web/*/public_html -name \"wp-config.php\" 2>/dev/null${NC}"
  echo -e "  Y luego agrega cada sitio con:"
  echo -e "  ${YELLOW}wpb add <nombre> <ruta> $S3_BUCKET${NC}"
  echo ""
}

# ══════════════════════════════════════
# RESTORE
# ══════════════════════════════════════
cmd_restore() {
  SITE_NAME=$1

  if [ -z "$SITE_NAME" ]; then
    echo ""
    echo -e "${RED}❌ Especifica el sitio a restaurar${NC}"
    echo -e "   Uso: ${YELLOW}wpb restore <sitio>${NC}"
    echo -e "   Ver sitios: ${CYAN}wpb list${NC}"
    echo ""
    exit 1
  fi

  trap "rm -f /tmp/restore-${SITE_NAME}.sql /tmp/restore-${SITE_NAME}.sql.gz" EXIT

  header
  echo -e "🔄 Restaurando ${BOLD}$SITE_NAME${NC}..."
  echo ""

  # ── Verificar HestiaCP
  echo -e "🔍 Verificando HestiaCP..."
  if [ ! -d "/usr/local/hestia" ]; then
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ❌ HestiaCP no está instalado en este servidor      ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  La restauración requiere HestiaCP instalado."
    echo ""
    echo -e "${BOLD}Para instalar HestiaCP:${NC}"
    echo -e "  ${CYAN}wget https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh${NC}"
    echo -e "  ${CYAN}bash hst-install.sh${NC}"
    echo ""
    echo -e "  Documentación: ${BLUE}https://docs.hestiacp.com${NC}"
    echo ""
    exit 1
  fi
  echo -e "   ✅ HestiaCP detectado"

  # ── Verificar que el sitio está registrado
  if ! grep -qF "^$SITE_NAME:" "$SITES_FILE" 2>/dev/null; then
    echo -e "${RED}❌ El sitio '$SITE_NAME' no está en la lista${NC}"
    echo -e "   Corre ${YELLOW}wpb list${NC} o ${YELLOW}wpb recover <bucket>${NC} primero"
    exit 1
  fi

  WP_PATH=$(grep -F "^$SITE_NAME:" "$SITES_FILE" | cut -d: -f2)
  S3_BUCKET=$(grep -F "^$SITE_NAME:" "$SITES_FILE" | cut -d: -f3)

  # Verificar si la ruta es desconocida
  if [ "$WP_PATH" = "RUTA_DESCONOCIDA" ]; then
    echo ""
    echo -e "${YELLOW}⚠️  La ruta de '$SITE_NAME' es desconocida.${NC}"
    echo -e "   Primero registra el sitio con:"
    echo -e "   ${CYAN}wpb add $SITE_NAME <ruta> $S3_BUCKET${NC}"
    echo ""
    echo -e "   Para ver las rutas disponibles:"
    echo -e "   ${CYAN}find /home/*/web/*/public_html -name \"wp-config.php\" 2>/dev/null${NC}"
    echo ""
    exit 1
  fi

  # ── Verificar backups en S3
  echo -e "🔍 Buscando backups en S3..."
  LATEST_DB=$(aws s3 ls "s3://$S3_BUCKET/$SITE_NAME/db/" 2>/dev/null \
    | sort | tail -1 | awk '{print $4}')

  if [ -z "$LATEST_DB" ]; then
    echo -e "${RED}❌ No hay backups de '$SITE_NAME' en S3${NC}"
    exit 1
  fi
  echo -e "   ✅ Backup encontrado: ${CYAN}$LATEST_DB${NC}"

  # ── Verificar si el sitio ya existe en el servidor
  echo ""
  if [ -d "$WP_PATH" ] && [ -f "$WP_PATH/wp-config.php" ]; then
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠️  Ya existe un WordPress en esta ruta             ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Ruta: ${CYAN}$WP_PATH${NC}"
    echo ""
    echo -e "  ${BOLD}¿Qué quieres hacer?${NC}"
    echo -e "  ${YELLOW}1)${NC} Sobrescribir — reemplaza todo con el backup de S3"
    echo -e "  ${YELLOW}2)${NC} Cancelar     — no hace nada"
    echo ""
    echo -ne "  Elige una opción (1 o 2): "
    read -r OPTION
    if [ "$OPTION" != "1" ]; then
      echo ""
      echo -e "${YELLOW}Restauración cancelada.${NC}"
      echo ""
      exit 0
    fi
  else
    # Sitio no existe — confirmar igualmente
    echo -e "${YELLOW}⚠️  Se va a restaurar '$SITE_NAME' en:${NC} $WP_PATH"
    echo -ne "   ¿Confirmas? Escribe ${BOLD}si${NC} para continuar: "
    read -r CONFIRM
    if [ "$CONFIRM" != "si" ]; then
      echo -e "${YELLOW}Restauración cancelada.${NC}"
      exit 0
    fi
  fi

  echo ""
  echo -e "🚀 Iniciando restauración..."
  echo ""

  # ── Paso 1: Crear directorio si no existe
  mkdir -p "$WP_PATH"

  # ── Paso 2: Restaurar archivos
  echo -e "📁 Restaurando archivos WordPress..."
  aws s3 sync "s3://$S3_BUCKET/$SITE_NAME/files/" "$WP_PATH/" \
    --delete --quiet
  echo -e "   ✅ Archivos restaurados"

  # ── Paso 3: Leer credenciales
  DB_NAME=$(grep "DB_NAME" "$WP_PATH/wp-config.php" | grep "define" | tr '"' "'" | cut -d"'" -f4)
  DB_USER=$(grep "DB_USER" "$WP_PATH/wp-config.php" | grep "define" | grep -v "DB_USERNAME" | tr '"' "'" | cut -d"'" -f4)
  DB_PASS=$(grep "DB_PASSWORD" "$WP_PATH/wp-config.php" | grep "define" | tr '"' "'" | cut -d"'" -f4)

  # ── Paso 4: Crear usuario MySQL si no existe
  echo -e "🔐 Verificando usuario MySQL..."
  USER_EXISTS=$(mariadb -u root -se "SELECT COUNT(*) FROM mysql.user WHERE User='$DB_USER';" 2>/dev/null \
    || mysql -u root -se "SELECT COUNT(*) FROM mysql.user WHERE User='$DB_USER';" 2>/dev/null)

  if [ "$USER_EXISTS" = "0" ] || [ -z "$USER_EXISTS" ]; then
    echo -e "   ⚠️  Usuario '$DB_USER' no existe — creándolo..."
    mariadb -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS'; GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null \
      || mysql -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS'; GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null
    echo -e "   ✅ Usuario MySQL creado: ${CYAN}$DB_USER${NC}"
  else
    echo -e "   ✅ Usuario MySQL existe: ${CYAN}$DB_USER${NC}"
    mariadb -u root -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null || true
  fi

  # ── Paso 5: Restaurar base de datos
  echo -e "🗄️  Restaurando base de datos..."
  aws s3 cp "s3://$S3_BUCKET/$SITE_NAME/db/$LATEST_DB" /tmp/restore-$SITE_NAME.sql.gz --quiet
  gunzip -f /tmp/restore-$SITE_NAME.sql.gz

  mariadb -u root -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\`;" 2>/dev/null \
    || mysql -u root -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\`;" 2>/dev/null

  mariadb -u root "$DB_NAME" < /tmp/restore-$SITE_NAME.sql 2>/dev/null \
    || mysql -u root "$DB_NAME" < /tmp/restore-$SITE_NAME.sql 2>/dev/null

  echo -e "   ✅ Base de datos restaurada: ${CYAN}$DB_NAME${NC}"

  # ── Paso 6: Corregir permisos
  echo -e "🔐 Corrigiendo permisos..."
  OWNER=$(stat -c '%U' "$(dirname $WP_PATH)" 2>/dev/null || echo "www-data")
  chown -R "$OWNER":www-data "$WP_PATH"
  chmod -R 755 "$WP_PATH"
  find "$WP_PATH" -maxdepth 1 -name "wp-config.php" -exec chmod 640 {} \;
  echo -e "   ✅ Permisos corregidos"

  # ── Paso 7: Limpiar caché
  echo -e "🧹 Limpiando caché..."
  wp cache flush --path="$WP_PATH" --allow-root --quiet 2>/dev/null || true
  wp rewrite flush --path="$WP_PATH" --allow-root --quiet 2>/dev/null || true
  echo -e "   ✅ Caché limpiada"

  # ── Paso 8: Regenerar script de backup y cron
  echo -e "🔧 Regenerando script de backup..."
  save_site_credentials "$SITE_NAME" "$DB_PASS"
  generate_backup_script "$SITE_NAME" "$WP_PATH" "$S3_BUCKET" "$DB_NAME" "$DB_USER"
  if ! crontab -l 2>/dev/null | grep -qF "wp-backup-$SITE_NAME"; then
    (crontab -l 2>/dev/null; echo "0 2 * * * $SCRIPTS_DIR/wp-backup-$SITE_NAME.sh") | crontab -
  fi
  echo -e "   ✅ Script de backup y cron restaurados"

  echo ""
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║  ✅ '$SITE_NAME' restaurado con éxito    ║${NC}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  Backup usado: ${CYAN}$LATEST_DB${NC}"
  echo -e "  Ruta:         ${CYAN}$WP_PATH${NC}"
  echo -e "  Base de datos:${CYAN} $DB_NAME${NC}"
  echo ""
}

# ══════════════════════════════════════
# LIST
# ══════════════════════════════════════
cmd_list() {
  header
  if [ ! -f "$SITES_FILE" ] || ! grep -v "^#" "$SITES_FILE" | grep -q ":"; then
    echo -e "${YELLOW}No hay sitios registrados todavía.${NC}"
    echo -e "Agrega uno con: ${CYAN}wpb add${NC} (sin parámetros para ver la guía)"
    echo ""
    exit 0
  fi
  COUNT=0
  echo -e "${BOLD}Sitios registrados:${NC}"
  echo ""
  while IFS=: read -r name path bucket; do
    [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
    COUNT=$((COUNT + 1))
    [ -f "$SCRIPTS_DIR/wp-backup-$name.sh" ] \
      && STATUS="${GREEN}✅ activo${NC}" \
      || STATUS="${RED}❌ script no encontrado${NC}"
    echo -e "  ${CYAN}${BOLD}$name${NC}"
    echo -e "    Ruta:      $path"
    echo -e "    Bucket:    s3://$bucket/$name/"
    echo -e "    Estado:    $STATUS"
    echo ""
  done < "$SITES_FILE"
  echo -e "Total: ${BOLD}$COUNT sitios${NC}"
  echo ""
}

# ══════════════════════════════════════
# RUN
# ══════════════════════════════════════
cmd_run() {
  SITE_NAME=$1
  if [ -z "$SITE_NAME" ]; then
    echo -e "${RED}❌ Especifica el sitio${NC} — Uso: ${YELLOW}wpb run <sitio>${NC}"
    exit 1
  fi
  if [ ! -f "$SCRIPTS_DIR/wp-backup-$SITE_NAME.sh" ]; then
    echo -e "${RED}❌ No existe '$SITE_NAME'${NC} — Corre: ${YELLOW}wpb list${NC}"
    exit 1
  fi
  echo -e "🚀 Corriendo backup de ${BOLD}$SITE_NAME${NC}..."
  echo ""
  bash "$SCRIPTS_DIR/wp-backup-$SITE_NAME.sh"
  [ $? -eq 0 ] \
    && echo -e "${GREEN}${BOLD}✅ Backup completado${NC}" \
    || echo -e "${RED}${BOLD}❌ Backup falló — corre: wpb logs${NC}"
  echo ""
}

# ══════════════════════════════════════
# RUN-ALL
# ══════════════════════════════════════
cmd_run_all() {
  if [ ! -f "$SITES_FILE" ] || ! grep -v "^#" "$SITES_FILE" | grep -q ":"; then
    echo -e "${YELLOW}No hay sitios registrados.${NC}"; exit 0
  fi
  SUCCESS=0; FAILED=0; FAILED_SITES=""
  echo -e "🚀 Corriendo backup de ${BOLD}todos los sitios${NC}..."
  echo ""
  while IFS=: read -r name path bucket; do
    [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
    echo -ne "  ${CYAN}$name${NC}... "
    bash "$SCRIPTS_DIR/wp-backup-$name.sh" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✅${NC}"; SUCCESS=$((SUCCESS + 1))
    else
      echo -e "${RED}❌${NC}"; FAILED=$((FAILED + 1)); FAILED_SITES="$FAILED_SITES $name"
    fi
  done < "$SITES_FILE"
  echo ""
  echo -e "✅ Exitosos: ${GREEN}${BOLD}$SUCCESS${NC}  ❌ Fallidos: ${RED}${BOLD}$FAILED${NC}"
  [ -n "$FAILED_SITES" ] && echo -e "   Con error:${RED}$FAILED_SITES${NC}"
  echo ""
}

# ══════════════════════════════════════
# STATUS
# ══════════════════════════════════════
cmd_status() {
  header
  [ ! -s "$LOG_FILE" ] && echo -e "${YELLOW}No hay logs. Corre: wpb run <sitio>${NC}" && exit 0
  echo -e "${BOLD}Últimos backups:${NC}"; echo ""
  grep -E "✅ Backup completado|❌ ERROR" "$LOG_FILE" | tail -20 | while read -r line; do
    echo "$line" | grep -q "✅" && echo -e "  ${GREEN}$line${NC}" || echo -e "  ${RED}$line${NC}"
  done
  echo ""
}

# ══════════════════════════════════════
# MONITOR
# ══════════════════════════════════════
cmd_monitor() {
  header
  echo -e "${BOLD}🔍 Monitor de backups${NC}"; echo ""
  [ ! -f "$SITES_FILE" ] || ! grep -v "^#" "$SITES_FILE" | grep -q ":" \
    && echo -e "${YELLOW}No hay sitios registrados.${NC}" && exit 0
  TODAY=$(date +%Y-%m-%d)
  YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null)
  while IFS=: read -r name path bucket; do
    [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
    echo -e "  ${CYAN}${BOLD}$name${NC}"
    LAST=$(aws s3 ls "s3://$bucket/$name/db/" 2>/dev/null | sort | tail -1 | awk '{print $4}')
    if [ -z "$LAST" ]; then
      echo -e "    BD en S3:  ${RED}❌ No hay backups${NC}"
    else
      BDATE=$(echo "$LAST" | cut -c1-10)
      [ "$BDATE" = "$TODAY" ]     && echo -e "    BD en S3:  ${GREEN}✅ Hoy ($LAST)${NC}"
      [ "$BDATE" = "$YESTERDAY" ] && echo -e "    BD en S3:  ${YELLOW}⚠️  Ayer ($LAST)${NC}"
      [ "$BDATE" != "$TODAY" ] && [ "$BDATE" != "$YESTERDAY" ] \
        && echo -e "    BD en S3:  ${RED}❌ Hace más de 1 día ($LAST)${NC}"
      TOTAL=$(aws s3 ls "s3://$bucket/$name/db/" 2>/dev/null | grep -c ".sql.gz" || echo 0)
      echo -e "    Copias:    ${CYAN}$TOTAL / $MAX_BACKUPS${NC}"
    fi
    [ -f "$SCRIPTS_DIR/wp-backup-$name.sh" ] \
      && echo -e "    Script:    ${GREEN}✅${NC}" || echo -e "    Script:    ${RED}❌${NC}"
    crontab -l 2>/dev/null | grep -q "wp-backup-$name" \
      && echo -e "    Cron 2AM:  ${GREEN}✅${NC}" || echo -e "    Cron 2AM:  ${RED}❌${NC}"
    echo ""
  done < "$SITES_FILE"
}

# ══════════════════════════════════════
# LOGS
# ══════════════════════════════════════
cmd_logs() {
  [ ! -f "$LOG_FILE" ] && echo -e "${YELLOW}No hay logs todavía.${NC}" && exit 0
  echo -e "${BOLD}Últimas 50 líneas:${NC}"; echo ""
  tail -50 "$LOG_FILE"
}

# ══════════════════════════════════════
# REMOVE
# ══════════════════════════════════════
cmd_remove() {
  SITE_NAME=$1
  [ -z "$SITE_NAME" ] && echo -e "${RED}❌ Uso: ${YELLOW}wpb remove <sitio>${NC}" && exit 1
  if [[ ! "$SITE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}❌ Nombre inválido: '$SITE_NAME'${NC}"
    exit 1
  fi
  ESCAPED=$(printf '%s' "$SITE_NAME" | sed 's/[[\.*^$()+?{|]/\\&/g')
  sed -i "/^${ESCAPED}:/d" "$SITES_FILE"
  rm -f "$SCRIPTS_DIR/wp-backup-$SITE_NAME.sh"
  rm -f "$CONFIG_DIR/$SITE_NAME.env"
  crontab -l 2>/dev/null | grep -v "wp-backup-$SITE_NAME" | crontab -
  echo -e "${GREEN}✅ '$SITE_NAME' eliminado${NC}"; echo ""
}

# ══════════════════════════════════════
# ROUTER
# ══════════════════════════════════════
case "$CMD" in
  add)      cmd_add "$2" "$3" "$4" ;;
  restore)  cmd_restore "$2" ;;
  recover)  cmd_recover "$2" ;;
  list)     cmd_list ;;
  run)      cmd_run "$2" ;;
  run-all)  cmd_run_all ;;
  status)   cmd_status ;;
  monitor)  cmd_monitor ;;
  logs)     cmd_logs ;;
  remove)   cmd_remove "$2" ;;
  help|"")  usage ;;
  *)
    echo -e "${RED}❌ Comando desconocido: '$CMD'${NC}"
    echo -e "   Corre ${YELLOW}wpb help${NC} para ver los comandos"
    exit 1
    ;;
esac
