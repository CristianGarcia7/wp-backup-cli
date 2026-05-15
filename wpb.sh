#!/bin/bash
# ═══════════════════════════════════════════════════════
# WP-BACKUP-CLI — Comando wpb v2.0
# ═══════════════════════════════════════════════════════

CONFIG_DIR="/etc/wp-backup"
SITES_FILE="$CONFIG_DIR/sites.conf"
SCRIPTS_DIR="/usr/local/bin"
LOG_FILE="/var/log/wp-backup.log"
MAX_BACKUPS=2   # Máximo de copias de BD por sitio
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
  echo -e "${CYAN}${BOLD}║       WP-BACKUP-CLI  v2.0            ║${NC}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════╝${NC}"
  echo ""
}

usage() {
  header
  echo -e "${BOLD}Uso:${NC} wpb <comando> [opciones]"
  echo ""
  echo -e "${BOLD}Comandos:${NC}"
  echo -e "  ${GREEN}add${NC} <sitio> <ruta> <bucket>   Agregar un sitio WordPress"
  echo -e "  ${GREEN}list${NC}                          Ver todos los sitios"
  echo -e "  ${GREEN}run${NC} <sitio>                   Correr backup de un sitio ahora"
  echo -e "  ${GREEN}run-all${NC}                       Correr backup de todos"
  echo -e "  ${GREEN}status${NC}                        Ver estado de los últimos backups"
  echo -e "  ${GREEN}monitor${NC}                       Ver alertas y salud de S3"
  echo -e "  ${GREEN}logs${NC}                          Ver logs"
  echo -e "  ${GREEN}remove${NC} <sitio>                Eliminar un sitio"
  echo -e "  ${GREEN}help${NC}                          Mostrar esta ayuda"
  echo ""
  echo -e "${BOLD}Ejemplo:${NC}"
  echo -e "  wpb add postobon /home/postobon/web/postobon.quadi.io/public_html backups-produ"
  echo -e "  wpb run postobon"
  echo -e "  wpb list"
  echo ""
}

# ══════════════════════════════════════
# ADD: agregar sitio
# ══════════════════════════════════════
cmd_add() {
  SITE_NAME=$1
  WP_PATH=$2
  S3_BUCKET=$3

  if [ -z "$SITE_NAME" ] || [ -z "$WP_PATH" ] || [ -z "$S3_BUCKET" ]; then
    echo -e "${RED}❌ Faltan parámetros${NC}"
    echo -e "   Uso: ${YELLOW}wpb add <sitio> <ruta> <bucket>${NC}"
    echo -e "   Ej:  wpb add postobon /home/postobon/web/postobon.quadi.io/public_html backups-produ"
    exit 1
  fi

  if [ ! -d "$WP_PATH" ]; then
    echo -e "${RED}❌ La ruta no existe:${NC} $WP_PATH"
    exit 1
  fi

  if [ ! -f "$WP_PATH/wp-config.php" ]; then
    echo -e "${RED}❌ No es un WordPress válido${NC} (no hay wp-config.php en $WP_PATH)"
    exit 1
  fi

  if grep -q "^$SITE_NAME:" "$SITES_FILE" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  El sitio '$SITE_NAME' ya está registrado${NC}"
    echo -e "   Usa ${CYAN}wpb remove $SITE_NAME${NC} primero si quieres reconfigurarlo"
    exit 1
  fi

  echo -e "🔧 Configurando ${BOLD}$SITE_NAME${NC}..."

  # Leer credenciales del wp-config.php
  DB_NAME=$(grep "DB_NAME" "$WP_PATH/wp-config.php" | grep "define" | cut -d"'" -f4)
  DB_USER=$(grep "DB_USER" "$WP_PATH/wp-config.php" | grep "define" | grep -v "DB_USERNAME" | cut -d"'" -f4)
  DB_PASS=$(grep "DB_PASSWORD" "$WP_PATH/wp-config.php" | grep "define" | cut -d"'" -f4)

  if [ -z "$DB_NAME" ]; then
    echo -e "${RED}❌ No se pudo leer wp-config.php${NC}"
    exit 1
  fi

  echo -e "   📋 Base de datos: ${CYAN}$DB_NAME${NC}"
  echo -e "   👤 Usuario:       ${CYAN}$DB_USER${NC}"

  # Dar permisos MySQL automáticamente
  echo -e "   🔐 Configurando permisos MySQL..."
  mariadb -u root -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null \
    || mysql -u root -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null \
    && echo -e "   ✅ Permisos MySQL configurados" \
    || echo -e "   ${YELLOW}⚠️  No se pudieron dar permisos automáticamente — configúralos manualmente${NC}"

  # Crear script de backup con rotación de 2 copias
  cat > "$SCRIPTS_DIR/wp-backup-$SITE_NAME.sh" << SCRIPT
#!/bin/bash
# Script de backup para: $SITE_NAME
# Generado por wp-backup-cli v2.0

WP_PATH="$WP_PATH"
S3_BUCKET="$S3_BUCKET"
SITE_NAME="$SITE_NAME"
DB_NAME="$DB_NAME"
DB_USER="$DB_USER"
DB_PASS='$DB_PASS'
DATE=\$(date +%Y-%m-%d_%H-%M-%S)
LOG="/var/log/wp-backup.log"
MAX_BACKUPS=$MAX_BACKUPS

echo "\$(date) - 🚀 Iniciando backup \$SITE_NAME" >> \$LOG

# ── 1. Exportar base de datos
mysqldump -u "\$DB_USER" -p"\$DB_PASS" "\$DB_NAME" 2>/dev/null \
  | gzip \
  | aws s3 cp - "s3://\$S3_BUCKET/\$SITE_NAME/db/\$DATE.sql.gz" --quiet

if [ \${PIPESTATUS[0]} -eq 0 ]; then
  echo "\$(date) - ✅ BD exportada: \$SITE_NAME" >> \$LOG

  # ── 2. Rotar backups — mantener solo los últimos MAX_BACKUPS
  BACKUPS=\$(aws s3 ls "s3://\$S3_BUCKET/\$SITE_NAME/db/" \
    | sort \
    | awk '{print \$4}')
  COUNT=\$(echo "\$BACKUPS" | grep -c ".sql.gz" || true)

  if [ "\$COUNT" -gt "\$MAX_BACKUPS" ]; then
    # Calcular cuántos borrar
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

# ── 3. Sincronizar archivos (incremental)
aws s3 sync "\$WP_PATH" "s3://\$S3_BUCKET/\$SITE_NAME/files/" \
  --exclude "wp-content/cache/*" \
  --exclude "wp-content/uploads/cache/*" \
  --quiet

echo "\$(date) - ✅ Backup completado: \$SITE_NAME" >> \$LOG
SCRIPT

  chmod +x "$SCRIPTS_DIR/wp-backup-$SITE_NAME.sh"

  # Registrar en sites.conf
  echo "$SITE_NAME:$WP_PATH:$S3_BUCKET" >> "$SITES_FILE"

  # Agregar al cron (2 AM todos los días)
  (crontab -l 2>/dev/null; echo "0 2 * * * $SCRIPTS_DIR/wp-backup-$SITE_NAME.sh") | crontab -

  echo ""
  echo -e "   ✅ Script:  ${CYAN}$SCRIPTS_DIR/wp-backup-$SITE_NAME.sh${NC}"
  echo -e "   ✅ Cron:    ${CYAN}todos los días a las 2 AM${NC}"
  echo -e "   ✅ Bucket:  ${CYAN}s3://$S3_BUCKET/$SITE_NAME/${NC}"
  echo -e "   ✅ Retención BD: ${CYAN}últimas $MAX_BACKUPS copias (se borra la más vieja automáticamente)${NC}"
  echo ""
  echo -e "${GREEN}${BOLD}✅ '$SITE_NAME' agregado correctamente${NC}"
  echo ""
  echo -e "Corre el primer backup con: ${YELLOW}wpb run $SITE_NAME${NC}"
  echo ""
}

# ══════════════════════════════════════
# LIST
# ══════════════════════════════════════
cmd_list() {
  header
  if [ ! -f "$SITES_FILE" ] || ! grep -v "^#" "$SITES_FILE" | grep -q ":"; then
    echo -e "${YELLOW}No hay sitios registrados todavía.${NC}"
    echo -e "Agrega uno con: ${CYAN}wpb add <sitio> <ruta> <bucket>${NC}"
    echo ""
    exit 0
  fi

  COUNT=0
  echo -e "${BOLD}Sitios registrados:${NC}"
  echo ""
  while IFS=: read -r name path bucket; do
    [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
    COUNT=$((COUNT + 1))
    if [ -f "$SCRIPTS_DIR/wp-backup-$name.sh" ]; then
      STATUS="${GREEN}✅ activo${NC}"
    else
      STATUS="${RED}❌ script no encontrado${NC}"
    fi
    echo -e "  ${CYAN}${BOLD}$name${NC}"
    echo -e "    Ruta:     $path"
    echo -e "    Bucket:   s3://$bucket/$name/"
    echo -e "    Estado:   $STATUS"
    echo -e "    Retención: últimas $MAX_BACKUPS BDs"
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
    echo -e "${RED}❌ Especifica el sitio${NC}"
    echo -e "   Uso: ${YELLOW}wpb run <sitio>${NC}"
    exit 1
  fi

  SCRIPT="$SCRIPTS_DIR/wp-backup-$SITE_NAME.sh"

  if [ ! -f "$SCRIPT" ]; then
    echo -e "${RED}❌ No existe el sitio '$SITE_NAME'${NC}"
    echo -e "   Corre ${YELLOW}wpb list${NC} para ver los sitios disponibles"
    exit 1
  fi

  echo -e "🚀 Corriendo backup de ${BOLD}$SITE_NAME${NC}..."
  echo ""
  bash "$SCRIPT"

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✅ Backup de '$SITE_NAME' completado${NC}"
  else
    echo -e "${RED}${BOLD}❌ Backup de '$SITE_NAME' falló — corre: wpb logs${NC}"
  fi
  echo ""
}

# ══════════════════════════════════════
# RUN-ALL
# ══════════════════════════════════════
cmd_run_all() {
  if [ ! -f "$SITES_FILE" ] || ! grep -v "^#" "$SITES_FILE" | grep -q ":"; then
    echo -e "${YELLOW}No hay sitios registrados.${NC}"
    exit 0
  fi

  SUCCESS=0
  FAILED=0
  FAILED_SITES=""

  echo -e "🚀 Corriendo backup de ${BOLD}todos los sitios${NC}..."
  echo ""

  while IFS=: read -r name path bucket; do
    [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
    echo -ne "  ${CYAN}$name${NC}... "
    bash "$SCRIPTS_DIR/wp-backup-$name.sh" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✅${NC}"
      SUCCESS=$((SUCCESS + 1))
    else
      echo -e "${RED}❌ falló${NC}"
      FAILED=$((FAILED + 1))
      FAILED_SITES="$FAILED_SITES $name"
    fi
  done < "$SITES_FILE"

  echo ""
  echo -e "✅ Exitosos: ${GREEN}${BOLD}$SUCCESS${NC}  ❌ Fallidos: ${RED}${BOLD}$FAILED${NC}"
  if [ -n "$FAILED_SITES" ]; then
    echo -e "   Sitios con error:${RED}$FAILED_SITES${NC}"
  fi
  echo ""
}

# ══════════════════════════════════════
# STATUS
# ══════════════════════════════════════
cmd_status() {
  header
  if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
    echo -e "${YELLOW}No hay logs todavía. Corre: wpb run <sitio>${NC}"
    exit 0
  fi

  echo -e "${BOLD}Últimos backups:${NC}"
  echo ""
  grep -E "✅ Backup completado|❌ ERROR" "$LOG_FILE" | tail -20 | while read -r line; do
    if echo "$line" | grep -q "✅"; then
      echo -e "  ${GREEN}$line${NC}"
    else
      echo -e "  ${RED}$line${NC}"
    fi
  done
  echo ""
}

# ══════════════════════════════════════
# MONITOR — salud general del sistema
# ══════════════════════════════════════
cmd_monitor() {
  header
  echo -e "${BOLD}🔍 Monitor de backups${NC}"
  echo ""

  if [ ! -f "$SITES_FILE" ] || ! grep -v "^#" "$SITES_FILE" | grep -q ":"; then
    echo -e "${YELLOW}No hay sitios registrados.${NC}"
    exit 0
  fi

  TODAY=$(date +%Y-%m-%d)
  YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null)

  while IFS=: read -r name path bucket; do
    [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue

    echo -e "  ${CYAN}${BOLD}$name${NC}"

    # Verificar último backup en S3
    LAST_BACKUP=$(aws s3 ls "s3://$bucket/$name/db/" 2>/dev/null \
      | sort | tail -1 | awk '{print $4}')

    if [ -z "$LAST_BACKUP" ]; then
      echo -e "    BD en S3:    ${RED}❌ No hay backups${NC}"
    else
      BACKUP_DATE=$(echo "$LAST_BACKUP" | cut -c1-10)
      BACKUP_SIZE=$(aws s3 ls "s3://$bucket/$name/db/$LAST_BACKUP" 2>/dev/null | awk '{print $3}')
      BACKUP_SIZE_MB=$(echo "scale=1; ${BACKUP_SIZE:-0} / 1048576" | bc 2>/dev/null || echo "?")

      if [ "$BACKUP_DATE" = "$TODAY" ]; then
        echo -e "    BD en S3:    ${GREEN}✅ Hoy ($LAST_BACKUP — ${BACKUP_SIZE_MB}MB)${NC}"
      elif [ "$BACKUP_DATE" = "$YESTERDAY" ]; then
        echo -e "    BD en S3:    ${YELLOW}⚠️  Ayer ($LAST_BACKUP)${NC}"
      else
        echo -e "    BD en S3:    ${RED}❌ Hace más de 1 día ($LAST_BACKUP)${NC}"
      fi

      # Contar cuántas copias hay
      TOTAL=$(aws s3 ls "s3://$bucket/$name/db/" 2>/dev/null | grep -c ".sql.gz" || echo 0)
      echo -e "    Copias BD:   ${CYAN}$TOTAL / $MAX_BACKUPS máximo${NC}"
    fi

    # Verificar si el script existe
    if [ -f "$SCRIPTS_DIR/wp-backup-$name.sh" ]; then
      echo -e "    Script:      ${GREEN}✅ existe${NC}"
    else
      echo -e "    Script:      ${RED}❌ no encontrado${NC}"
    fi

    # Verificar si está en el cron
    if crontab -l 2>/dev/null | grep -q "wp-backup-$name"; then
      echo -e "    Cron 2 AM:   ${GREEN}✅ programado${NC}"
    else
      echo -e "    Cron 2 AM:   ${RED}❌ no está en cron${NC}"
    fi

    echo ""
  done < "$SITES_FILE"
}

# ══════════════════════════════════════
# LOGS
# ══════════════════════════════════════
cmd_logs() {
  if [ ! -f "$LOG_FILE" ]; then
    echo -e "${YELLOW}No hay logs todavía.${NC}"
    exit 0
  fi
  echo -e "${BOLD}Últimas 50 líneas del log:${NC}"
  echo ""
  tail -50 "$LOG_FILE"
}

# ══════════════════════════════════════
# REMOVE
# ══════════════════════════════════════
cmd_remove() {
  SITE_NAME=$1

  if [ -z "$SITE_NAME" ]; then
    echo -e "${RED}❌ Especifica el sitio${NC}"
    echo -e "   Uso: ${YELLOW}wpb remove <sitio>${NC}"
    exit 1
  fi

  sed -i "/^$SITE_NAME:/d" "$SITES_FILE"
  rm -f "$SCRIPTS_DIR/wp-backup-$SITE_NAME.sh"
  crontab -l 2>/dev/null | grep -v "wp-backup-$SITE_NAME" | crontab -

  echo -e "${GREEN}✅ Sitio '$SITE_NAME' eliminado${NC}"
  echo ""
}

# ══════════════════════════════════════
# ROUTER
# ══════════════════════════════════════
case "$CMD" in
  add)      cmd_add "$2" "$3" "$4" ;;
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