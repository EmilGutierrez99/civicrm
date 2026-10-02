# instalar-civicrm.sh — CiviCRM Standalone (IN-344, Etapa 1)

Script de instalación de CiviCRM Standalone en un entorno local de aprendizaje.

> Este entorno es **solo para aprender**. No guarda datos reales de socios ni envía
> correos. Si se rompe, se borra y se vuelve a crear.

## Qué instala

- nginx, MariaDB y PHP-FPM con las extensiones que necesita CiviCRM
- CiviCRM Standalone 6.18.1, en `/var/www/civicrm`
- `cv`, la herramienta de línea de comandos de CiviCRM

## Qué NO hace el script

El script **no parte de una máquina vacía**. Da por hecho que ya existe:

- Ubuntu 24.04 instalada y con conexión a internet
- Un usuario con permisos de `sudo`

La instalación del sistema operativo, las `open-vm-tools` y la configuración de la
máquina virtual quedan fuera.

## Requisitos

- Ubuntu 24.04 (noble)
- PHP 8.3 disponible en los repositorios de la distribución
- Acceso `sudo`

## Uso

```bash
chmod +x instalar-civicrm.sh
./instalar-civicrm.sh
```

La primera vez, si no existe el `.env`, el script lo crea a partir de
`.env.example` y pide por teclado las dos contraseñas y el correo del
administrador. Las contraseñas no se muestran al teclearlas (`read -s`) y no
quedan en el historial de la terminal. Después les pone permisos `600`.

Si prefieres rellenarlo tú, copia `.env.example` a `.env` antes de ejecutar.

**No lo ejecutes con `sudo`.** El script pide la autorización al principio con
`sudo -v` y la usa solo en las órdenes que la necesitan. Si se ejecutara entero
como root, los ficheros creados pertenecerían a root y PHP-FPM no podría
escribir en ellos.

Al terminar, el sitio queda en http://localhost:8080/civicrm/

### Si los ficheros han pasado por Windows

Un fichero editado o descargado en Windows termina cada línea con `\r\n`, y bash
no entiende ese `\r`. El síntoma es un error del tipo `$'\r': orden no encontrada`.

El script tolera un `.env` en formato Windows, pero **no puede arreglarse a sí
mismo**: si `instalar-civicrm.sh` llega con esos finales de línea, bash falla
antes de ejecutar nada. Si ocurre:

```bash
sed -i 's/\r$//' instalar-civicrm.sh .env.example .gitignore README.md
```

Lo más sencillo es clonar el repositorio directamente en la máquina Linux en
lugar de copiar los ficheros desde Windows.

## Contraseñas

No hay ninguna contraseña dentro del script. Se leen del fichero `.env`, que está
en `.gitignore` y nunca se sube al repositorio. Las contraseñas reales viven en el
gestor de contraseñas de la asociación.

`DB_PASS` y `ADMIN_PASS` solo pueden contener **letras y números**. Los símbolos
rompen la cadena de conexión `mysql://usuario:clave@host:puerto/base` (donde `@`,
`:` y `/` son separadores) y algunos los interpreta la propia shell. El script lo
valida y falla si no se cumple.

Son dos contraseñas distintas y para cosas distintas:

| Variable | Usuario | Para qué |
|---|---|---|
| `DB_PASS` | `civicrm_user` (MariaDB) | La usa el código de CiviCRM para conectarse a la base de datos |
| `ADMIN_PASS` | `admin` (CiviCRM) | La escribes tú en la pantalla de login del navegador |

## Se puede ejecutar dos veces

El script es idempotente: ejecutarlo de nuevo sobre un sistema ya instalado no
rompe nada. Los puntos que lo consiguen:

| Paso | Cómo |
|---|---|
| Base de datos | `CREATE DATABASE IF NOT EXISTS` |
| Usuario de la BD | `CREATE OR REPLACE USER` |
| Ajustes de PHP | `sed` sustituye la línea entera, no añade |
| Enlace de nginx | `ln -sf` (la `f` fuerza si ya existe) |
| Descarga de CiviCRM | Se omite si ya existe `SITE_ROOT/core` |
| `cv core:install` | Se omite si ya existe `private/civicrm.settings.php` |

## Comprobaciones finales

Antes de terminar, el script verifica que:

- nginx, php-fpm y mariadb están activos
- `/civicrm/` responde
- `/private/civicrm.settings.php` devuelve **403**, es decir, que el fichero con
  las credenciales de la base de datos no es accesible por web

Si cualquiera de estas falla, el script termina con error.

## Desviaciones respecto al ticket IN-344

| Ticket | Aquí | Motivo |
|---|---|---|
| Debian sobre WSL2 | Ubuntu 24.04 en VMware | Decisión tomada en el Paso 1 |
| PHP 8.4 | PHP 8.3 | Es la versión que trae Ubuntu 24.04 |
| `private/` por encima de la raíz pública | `private/` dentro de la raíz pública | La estructura de Standalone 6.18.1 pone `index.php` y `private/` en la misma carpeta. nginx no lee el `.htaccess` del paquete, así que la protección depende del bloque `location ^~ /private/` |

## Estructura del repositorio

```
.
├── instalar-civicrm.sh   # el script
├── .env.example          # plantilla de variables (sin secretos)
├── .env                  # contraseñas reales — NO está en el repositorio
├── .gitignore
└── README.md
```
