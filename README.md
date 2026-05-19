# wp-backup-cli

Herramienta de línea de comandos para gestionar backups automáticos de sitios WordPress hacia AWS S3. Un solo servidor puede gestionar múltiples sitios con un comando por sitio.

---

## Contenido

- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Primer uso — flujo completo](#primer-uso--flujo-completo)
- [Referencia de comandos](#referencia-de-comandos)
  - [wpb help](#wpb-help)
  - [wpb add](#wpb-add--agregar-un-sitio)
  - [wpb list](#wpb-list--ver-sitios-registrados)
  - [wpb run](#wpb-run--correr-backup-manual)
  - [wpb run-all](#wpb-run-all--correr-todos-los-backups)
  - [wpb status](#wpb-status--resumen-desde-el-log)
  - [wpb monitor](#wpb-monitor--salud-en-tiempo-real)
  - [wpb logs](#wpb-logs--ver-log-completo)
  - [wpb remove](#wpb-remove--eliminar-un-sitio)
  - [wpb recover](#wpb-recover--recuperar-lista-desde-s3)
  - [wpb restore](#wpb-restore--restaurar-un-sitio-completo)
- [Recuperación de emergencia](#recuperación-de-emergencia-instancia-nueva)
- [Qué se respalda y qué no](#qué-se-respalda-y-qué-no)
- [Retención de copias](#retención-de-copias)
- [Seguridad](#seguridad)
- [Estructura de archivos](#estructura-de-archivos)
- [Permisos IAM necesarios](#permisos-iam-necesarios)
- [Diagnóstico de problemas](#diagnóstico-de-problemas)

---

## Requisitos

- Ubuntu / Debian (ARM aarch64 o x86_64)
- Acceso root al servidor
- Instancia EC2 con un **IAM Role** que tenga permisos sobre S3 (ver [Permisos IAM](#permisos-iam-necesarios))
- HestiaCP instalado en el servidor
- MariaDB o MySQL con acceso root sin contraseña (configuración estándar de HestiaCP)

> **Nota:** AWS CLI y WP-CLI se instalan automáticamente si no están presentes.

---

## Instalación

Ejecutar una sola vez por servidor:

```bash
curl -fsSL https://raw.githubusercontent.com/CristianGarcia7/wp-backup-cli/main/install.sh | bash
```

Esto instala:
- **AWS CLI v2** — para comunicarse con S3
- **WP-CLI** — para gestionar WordPress (limpiar caché al restaurar)
- El comando **`wpb`** en `/usr/local/bin/wpb`
- El directorio de configuración `/etc/wp-backup/`
- El archivo de log `/var/log/wp-backup.log`

---

## Primer uso — flujo completo

```bash
# 1. Agregar un sitio (detecta la BD automáticamente y programa el cron)
wpb add postobon /home/postobon/web/postobon.quadi.io/public_html backups-produ

# 2. Correr el primer backup de inmediato para verificar que funciona
wpb run postobon

# 3. Confirmar que el backup llegó a S3
wpb monitor

# 4. Ver el log si quieres más detalle
wpb logs
```

Para ver las rutas de todos los WordPress instalados en el servidor:

```bash
find /home/*/web/*/public_html -name "wp-config.php" 2>/dev/null
```

En HestiaCP la ruta siempre tiene esta estructura:
```
/home/<usuario>/web/<dominio>/public_html
```

---

## Referencia de comandos

### `wpb help`

Muestra la lista de comandos disponibles con una descripción breve de cada uno.

```bash
wpb help
```

También se activa corriendo `wpb` sin argumentos.

---

### `wpb add` — Agregar un sitio

```bash
wpb add <nombre> <ruta> <bucket>
```

**Parámetros:**

| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `<nombre>` | Nombre corto para identificar el sitio. Solo letras, números, `-` y `_`. | `postobon`, `natumalta-stg` |
| `<ruta>` | Ruta completa al directorio `public_html` del WordPress. | `/home/postobon/web/postobon.quadi.io/public_html` |
| `<bucket>` | Nombre del bucket S3 donde se guardarán los backups. | `backups-produ` |

**Ejemplos:**

```bash
wpb add postobon /home/postobon/web/postobon.quadi.io/public_html backups-produ
wpb add natumalta /home/natumalta/web/natumalta-stg.quadi.io/public_html backups-produ
wpb add bbdo /home/bbdo/web/bbdo.quadi.io/public_html backups-produ
```

Corriendo `wpb add` sin parámetros muestra una guía completa con ejemplos reales.

**Qué hace automáticamente:**

1. Verifica que la ruta exista y contenga un `wp-config.php` válido
2. Lee `DB_NAME`, `DB_USER` y `DB_PASSWORD` directamente desde `wp-config.php`
3. Configura los permisos MySQL necesarios (`GRANT ALL PRIVILEGES`)
4. Guarda las credenciales de BD en `/etc/wp-backup/<nombre>.env` con permisos `600` (solo root)
5. Genera el script de backup en `/usr/local/bin/wp-backup-<nombre>.sh`
6. Registra el sitio en `/etc/wp-backup/sites.conf`
7. Guarda una copia de `sites.conf` en `s3://<bucket>/_config/sites.conf` para recuperación de emergencia
8. Programa el cron para ejecutarse todos los días a las **2:00 AM**

---

### `wpb list` — Ver sitios registrados

```bash
wpb list
```

Muestra todos los sitios registrados localmente con su ruta, bucket S3 y si el script de backup existe.

---

### `wpb run` — Correr backup manual

```bash
wpb run <nombre>
```

Ejecuta el backup de un sitio específico ahora mismo, sin esperar las 2 AM. Útil para verificar que la configuración es correcta o para hacer un backup puntual antes de un cambio importante.

```bash
wpb run postobon
```

---

### `wpb run-all` — Correr todos los backups

```bash
wpb run-all
```

Ejecuta el backup de todos los sitios registrados en secuencia. Al finalizar muestra cuántos tuvieron éxito y cuáles fallaron.

---

### `wpb status` — Resumen desde el log

```bash
wpb status
```

Lee el archivo de log local y muestra las últimas **20 entradas** de backups completados o errores. Es una vista rápida del historial reciente sin consultar S3.

> **Diferencia con `wpb monitor`:** `status` lee el log del servidor (rápido, sin conexión a S3). `monitor` consulta S3 en tiempo real para verificar que las copias realmente están allí.

---

### `wpb monitor` — Salud en tiempo real

```bash
wpb monitor
```

Para cada sitio registrado consulta S3 y muestra:

- Si el último backup de BD es de **hoy** ✅, **ayer** ⚠️ o hace más de un día ❌
- Cuántas copias de BD hay en S3 vs el máximo configurado
- Si el script de backup existe en el servidor
- Si el cron de las 2 AM está activo

Ejemplo de salida:
```
  natumalta
    BD en S3:  ✅ Hoy (2026-05-19_02-00-00.sql.gz)
    Copias:    2 / 2
    Script:    ✅
    Cron 2AM:  ✅
```

---

### `wpb logs` — Ver log completo

```bash
wpb logs
```

Muestra las últimas **50 líneas** del log en `/var/log/wp-backup.log`. Cada entrada tiene fecha, hora y resultado de la operación.

Ejemplo de entradas en el log:
```
2026-05-19 02:00:01 - 🚀 Iniciando backup natumalta
2026-05-19 02:00:05 - ✅ BD exportada: natumalta
2026-05-19 02:00:18 - ✅ Backup completado: natumalta
```

---

### `wpb remove` — Eliminar un sitio

```bash
wpb remove <nombre>
```

Elimina completamente el sitio del sistema de backups:

- Borra el script `/usr/local/bin/wp-backup-<nombre>.sh`
- Borra el archivo de credenciales `/etc/wp-backup/<nombre>.env`
- Elimina la entrada del cron
- Elimina la línea del sitio en `sites.conf`

> **Nota:** `wpb remove` **no** borra los archivos ya guardados en S3. Las copias en el bucket quedan intactas.

```bash
wpb remove postobon
```

---

### `wpb recover` — Recuperar lista desde S3

```bash
wpb recover <bucket>
```

Comando de emergencia para usar en un servidor nuevo. Recupera la lista de sitios que estaban configurados.

**Comportamiento:**
1. Si existe `s3://<bucket>/_config/sites.conf` (guardado automáticamente por `wpb add`), lo descarga
2. Si no existe, detecta los sitios leyendo las carpetas del bucket y los registra con ruta `RUTA_DESCONOCIDA`
3. Muestra cada sitio encontrado con su último backup disponible
4. Indica qué hacer a continuación

```bash
wpb recover backups-produ
```

---

### `wpb restore` — Restaurar un sitio completo

```bash
wpb restore <nombre>
```

Restaura un sitio completo desde S3. Requiere que HestiaCP esté instalado.

**Qué hace paso a paso:**

1. Verifica que HestiaCP esté instalado
2. Verifica que el sitio esté en la lista (`sites.conf`)
3. Busca el backup más reciente disponible en S3
4. Pregunta confirmación antes de proceder (si ya existe un WordPress en esa ruta, advierte que va a sobrescribir)
5. Restaura todos los archivos del sitio desde `s3://<bucket>/<nombre>/files/`
6. Crea el usuario MySQL si no existe
7. Descarga el dump de BD, crea la base de datos y la importa
8. Corrige permisos del directorio (`755`) y protege `wp-config.php` (`640`)
9. Limpia la caché de WordPress
10. Regenera el script de backup y el cron para que los backups automáticos continúen

```bash
wpb restore natumalta
```

---

## Recuperación de emergencia (instancia nueva)

Si el servidor falla y se levanta una instancia nueva:

```bash
# 1. Instalar la herramienta en el servidor nuevo
curl -fsSL https://raw.githubusercontent.com/CristianGarcia7/wp-backup-cli/main/install.sh | bash

# 2. Recuperar la lista de sitios desde S3
wpb recover backups-produ

# 3. Restaurar cada sitio (repetir por cada sitio)
wpb restore postobon
wpb restore natumalta
wpb restore bbdo
```

> El servidor nuevo debe tener el mismo IAM Role con permisos S3 que el servidor original.

---

## Qué se respalda y qué no

**Se respalda:**
- Todos los archivos de WordPress (`wp-admin/`, `wp-includes/`, `wp-content/`, `wp-config.php`, etc.)
- La base de datos completa (dump SQL comprimido con gzip)

**Se excluye del backup de archivos:**
- `wp-content/cache/` — caché regenerable automáticamente
- `wp-content/uploads/cache/` — caché de imágenes regenerable

---

## Retención de copias

Se conservan las **2 copias más recientes** de la base de datos. Cuando se genera una nueva copia y ya hay 2, la más antigua se elimina automáticamente de S3.

Los archivos del sitio no tienen rotación — se sincronizan de forma incremental. Si se borra un archivo del servidor, en el próximo backup también se borra de S3.

---

## Seguridad

- Las contraseñas de base de datos se almacenan en `/etc/wp-backup/<nombre>.env` con permisos `600` (solo lectura para root). Nunca se escriben en texto plano en scripts accesibles.
- La conexión con S3 usa el **IAM Role de la instancia EC2** — no hay claves de acceso (`AWS_ACCESS_KEY_ID`) escritas en ningún archivo.
- Los nombres de sitio se validan: solo se permiten caracteres `[a-zA-Z0-9_-]`.
- El archivo de log tiene permisos `640` — solo root puede escribir.
- Los archivos temporales del proceso de restauración se eliminan automáticamente aunque ocurra un error.
- `wp-config.php` queda con permisos `640` después de cada restauración.

---

## Estructura de archivos

### En el servidor

```
/etc/wp-backup/
  sites.conf              ← lista de sitios registrados (nombre:ruta:bucket)
  postobon.env            ← credenciales de BD del sitio (chmod 600)
  natumalta.env

/usr/local/bin/
  wpb                     ← comando principal
  wp-backup-postobon.sh   ← script de backup generado por wpb add
  wp-backup-natumalta.sh

/var/log/
  wp-backup.log           ← log de todas las operaciones (chmod 640)
```

### En AWS S3

```
s3://backups-produ/
  _config/
    sites.conf                        ← copia de la lista de sitios (emergencia)
  postobon/
    db/
      2026-05-19_02-00-00.sql.gz      ← backup de hoy
      2026-05-18_02-00-00.sql.gz      ← backup de ayer (máximo 2 copias)
    files/
      wp-admin/
      wp-content/
      wp-includes/
      wp-config.php
      ...
  natumalta/
    db/  ...
    files/  ...
```

---

## Permisos IAM necesarios

El IAM Role adjunto a la instancia EC2 debe tener esta política sobre el bucket:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::backups-produ"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::backups-produ/*"
    }
  ]
}
```

Reemplazar `backups-produ` por el nombre real del bucket.

---

## Diagnóstico de problemas

**El backup falló — ¿cómo saber qué pasó?**

```bash
wpb logs
```

Buscar líneas con `❌ ERROR` para identificar en qué paso falló.

---

**`wpb monitor` muestra que el cron no está activo**

```bash
crontab -l | grep wp-backup
```

Si no aparece nada, volver a correr `wpb add` para el sitio afectado. Esto regenera el cron sin afectar las copias existentes en S3.

---

**El script de backup dice `❌ script no encontrado` en `wpb list`**

El archivo `/usr/local/bin/wp-backup-<nombre>.sh` fue eliminado o el sitio fue registrado en otra instancia. Correr `wpb add` de nuevo con los mismos parámetros lo regenera.

---

**Error de permisos en MySQL al hacer backup**

```bash
mariadb -u root -e "GRANT ALL PRIVILEGES ON \`nombre_bd\`.* TO 'usuario'@'localhost'; FLUSH PRIVILEGES;"
```

O correr `wpb add` de nuevo — el comando reconfigura los permisos MySQL automáticamente.

---

**No se puede acceder al bucket S3**

Verificar que la instancia tenga el IAM Role correcto:

```bash
aws s3 ls s3://backups-produ/
```

Si devuelve error, el IAM Role no tiene los permisos necesarios o no está adjunto a la instancia.

---

Omnicom Production LATAM — Cristian Garcia
