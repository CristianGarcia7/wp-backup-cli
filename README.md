# wp-backup-cli 🛡️

Herramienta de línea de comandos para backups automáticos de WordPress hacia AWS S3.

## Características
- Detecta automáticamente ARM (aarch64) o x86_64
- Instala AWS CLI y WP-CLI automáticamente
- Solo guarda las **2 últimas copias** de BD — borra la más vieja automáticamente
- Archivos sincronizados de forma incremental (sin duplicados)
- Cron automático a las 2 AM
- Guía integrada al correr `wpb add` sin parámetros
- Restauración completa con `wpb restore` (archivos + BD + permisos + caché)
- Recuperación de emergencia con `wpb recover` en instancia nueva
- Credenciales de BD almacenadas en archivo protegido (`chmod 600`), nunca en texto plano
- Validación de nombres de sitio y cleanup automático de temporales

---

## Instalación (una vez por servidor)

```bash
curl -fsSL https://raw.githubusercontent.com/CristianGarcia7/wp-backup-cli/main/install.sh | bash
```

---

## Comandos

### `wpb add` — Agregar un sitio
```bash
wpb add <nombre> <ruta> <bucket>
```
```bash
wpb add postobon /home/postobon/web/postobon.quadi.io/public_html backups-produ
```
Si corres `wpb add` sin parámetros muestra la guía completa con ejemplos.

En HestiaCP la ruta siempre es:
```
/home/<usuario>/web/<dominio>/public_html
```

Para ver todas las rutas disponibles:
```bash
find /home/*/web/*/public_html -name "wp-config.php" 2>/dev/null
```

El nombre del sitio solo puede contener letras, números, guiones (`-`) y guiones bajos (`_`).

---

### `wpb list` — Ver sitios registrados
```bash
wpb list
```

---

### `wpb run` — Correr backup manual
```bash
wpb run postobon
```

### `wpb run-all` — Correr todos los backups
```bash
wpb run-all
```

---

### `wpb status` — Ver estado
```bash
wpb status
```

### `wpb monitor` — Salud general
```bash
wpb monitor
```
Muestra para cada sitio: si el backup de hoy existe en S3, cuántas copias hay, si el cron está activo.

---

### `wpb logs` — Ver logs
```bash
wpb logs
```

---

### `wpb remove` — Eliminar sitio
```bash
wpb remove postobon
```
Elimina el script de backup, el cron, el archivo de credenciales y la entrada en la lista.

---

## En caso de emergencia (instancia nueva)

Si el servidor se cayó y tienes una EC2 nueva:

```bash
# 1. Instalar la herramienta
curl -fsSL https://raw.githubusercontent.com/CristianGarcia7/wp-backup-cli/main/install.sh | bash

# 2. Recuperar la lista de sitios desde S3
wpb recover backups-produ

# 3. Restaurar el sitio que necesitas
wpb restore postobon
```

### `wpb recover` — Recuperar lista de sitios
```bash
wpb recover <bucket>
```
- Descarga el `sites.conf` guardado en S3
- Si no existe, detecta los sitios por las carpetas del bucket
- Muestra el último backup disponible de cada sitio
- Te indica qué hacer a continuación

### `wpb restore` — Restaurar un sitio
```bash
wpb restore postobon
```
- Verifica que HestiaCP esté instalado
- Si ya existe un WordPress en esa ruta, pregunta si sobrescribir
- Crea el usuario MySQL si no existe
- Restaura archivos + base de datos + permisos + caché automáticamente
- Regenera el script de backup y el cron para que los backups continúen

---

## Estructura en S3

```
s3://backups-produ/
  _config/
    sites.conf              <- lista de sitios (para recuperación de emergencia)
  postobon/
    db/
      2026-05-15_02-00-00.sql.gz   <- backup de hoy
      2026-05-14_02-00-00.sql.gz   <- backup de ayer
    files/
      wp-admin/
      wp-content/
      wp-includes/
      wp-config.php
      ...
```

---

## Estructura local

```
/etc/wp-backup/
  sites.conf          <- lista de sitios registrados
  postobon.env        <- credenciales de BD (chmod 600, solo root)
  natumalta.env
/usr/local/bin/
  wpb                 <- comando principal
  wp-backup-postobon.sh
  wp-backup-natumalta.sh
/var/log/
  wp-backup.log       <- log de todos los backups
```

---

## Requisitos
- Ubuntu / Debian (ARM o x86_64)
- Acceso root
- EC2 con IAM Role con permisos S3
- HestiaCP instalado (requerido para `wpb restore`)
- MariaDB / MySQL con acceso root

---

Omnicom Production LATAM — Cristian Garcia
