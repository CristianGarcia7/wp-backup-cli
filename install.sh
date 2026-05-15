#!/bin/bash
# ═══════════════════════════════════════════════════════
# WP-BACKUP-CLI — Instalador v2.0
# Uso: curl -fsSL https://raw.githubusercontent.com/CristianGarcia7/wp-backup-cli/main/install.sh | bash
# ═══════════════════════════════════════════════════════

set -e

REPO="https://raw.githubusercontent.com/CristianGarcia7/wp-backup-cli/main"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/wp-backup"
LOG_FILE="/var/log/wp-backup.log"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     WP-BACKUP-CLI — Instalador v2    ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. Detectar arquitectura e instalar AWS CLI
if ! command -v aws &>/dev/null; then
  echo "📦 Instalando AWS CLI..."
  ARCH=$(uname -m)
  echo "   Arquitectura detectada: $ARCH"

  if [ "$ARCH" = "aarch64" ]; then
    AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
    echo "   → Descargando versión ARM64..."
  elif [ "$ARCH" = "x86_64" ]; then
    AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    echo "   → Descargando versión x86_64..."
  else
    echo "   ❌ Arquitectura no soportada: $ARCH"
    exit 1
  fi

  curl -s "$AWS_URL" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp/
  sudo /tmp/aws/install --update

  # Crear symlink si no quedó en PATH
  if ! command -v aws &>/dev/null; then
    sudo ln -sf /usr/local/aws-cli/v2/current/bin/aws /usr/local/bin/aws 2>/dev/null || true
    sudo ln -sf /usr/local/aws-cli/v2/dist/aws /usr/local/bin/aws 2>/dev/null || true
  fi

  rm -rf /tmp/aws /tmp/awscliv2.zip
  echo "   ✅ AWS CLI instalado: $(aws --version 2>&1 | cut -d' ' -f1)"
else
  echo "   ✅ AWS CLI ya instalado: $(aws --version 2>&1 | cut -d' ' -f1)"
fi

# ── 2. Instalar WP-CLI
if ! command -v wp &>/dev/null; then
  echo "📦 Instalando WP-CLI..."
  curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod +x wp-cli.phar
  sudo mv wp-cli.phar /usr/local/bin/wp
  echo "   ✅ WP-CLI instalado: $(wp --version)"
else
  echo "   ✅ WP-CLI ya instalado: $(wp --version)"
fi

# ── 3. Crear directorios y log
sudo mkdir -p "$CONFIG_DIR"
sudo touch "$LOG_FILE"
sudo chmod 666 "$LOG_FILE"

# ── 4. Descargar el comando wpb
echo "📥 Descargando comando wpb..."
sudo curl -fsSL "$REPO/wpb.sh" -o "$INSTALL_DIR/wpb"
sudo chmod +x "$INSTALL_DIR/wpb"

# ── 5. Inicializar archivo de sitios si no existe
if [ ! -f "$CONFIG_DIR/sites.conf" ]; then
  echo "# formato: nombre:ruta_wordpress:bucket_s3" | sudo tee "$CONFIG_DIR/sites.conf" > /dev/null
fi

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   ✅ WP-BACKUP-CLI v2 instalado      ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "Comandos disponibles:"
echo "  wpb add <sitio> <ruta> <bucket>   — Agregar sitio"
echo "  wpb list                          — Ver sitios registrados"
echo "  wpb run <sitio>                   — Correr backup ahora"
echo "  wpb run-all                       — Correr todos"
echo "  wpb status                        — Ver estado backups"
echo "  wpb monitor                       — Ver alertas y salud S3"
echo "  wpb logs                          — Ver logs"
echo "  wpb remove <sitio>                — Eliminar sitio"
echo ""
echo "Ejemplo:"
echo "  wpb add natumalta-stg /home/natumalta/web/natumalta-stg.quadi.io/public_html backups-produ"
echo ""