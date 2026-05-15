# wp-backup-cli 🛡️

Herramienta de línea de comandos para backups automáticos de WordPress hacia AWS S3.

## Características
- ✅ Detecta automáticamente ARM (aarch64) o x86_64
- ✅ Instala AWS CLI y WP-CLI automáticamente
- ✅ Solo guarda las **2 últimas copias** de BD — borra la más vieja automáticamente
- ✅ Archivos sincronizados de forma incremental (solo sube lo nuevo)
- ✅ Cron automático a las 2 AM
- ✅ Monitor de salud con `wpb monitor`

---

## Instalación (una vez por servidor)

```bash
curl -fsSL https://raw.githubusercontent.com/CristianGarcia7/wp-backup-cli/main/install.sh | bash
```

---

## Comandos

### Agregar un sitio
```bash
wpb add <nombre> <ruta> <bucket>
```
```bash
wpb add postobon /home/postobon/web/postobon.quadi.io/public_html backups-produ
```
Automáticamente: lee credenciales del wp-config.php, da permisos MySQL, crea el script y programa el cron.

### Ver sitios registrados
```bash
wpb list
```

### Correr backup manual
```bash
wpb run postobon
```

### Correr backup de todos
```bash
wpb run-all
```

### Ver estado de backups
```bash
wpb status
```

### Monitor completo (recomendado para revisar diario)
```bash
wpb monitor
```
Muestra para cada sitio: si el backup de hoy existe en S3, cuántas copias hay, si el cron está activo.

### Ver logs
```bash
wpb logs
```

### Eliminar un sitio
```bash
wpb remove postobon
```

---

## Retención automática

Cada sitio guarda solo las **2 últimas copias** de la base de datos. Cada vez que se crea un backup nuevo, el más viejo se borra automáticamente. Los archivos e imágenes son incrementales (no se borran, solo se agregan los nuevos).

---

## Estructura en S3

```
s3://backups-produ/
  postobon/
    db/
      2026-05-15_02-00-00.sql.gz   ← backup de hoy
      2026-05-14_02-00-00.sql.gz   ← backup de ayer
      (el más viejo se borra automáticamente)
    files/
      wp-admin/
      wp-content/
      wp-includes/
      wp-config.php
      ...   
```

---

## Requisitos
- Ubuntu / Debian (ARM o x86_64)
- Acceso root
- EC2 con IAM Role con permisos S3
- MariaDB / MySQL con acceso root

---

Omnicom Production LATAM — Cristian Garcia