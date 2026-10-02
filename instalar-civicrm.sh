#!/bin/bash
#
# instalar-civicrm.sh - Instalación de CiviCRM Standalone en Ubuntu 24.04
# IN-344 Etapa 1 - Entorno de aprendizaje
#
# Uso:  ./instalar-civicrm.sh      (NO ejecutar con sudo; el script lo pide donde hace falta)
#
# Idea general: este script fu diseñado buscando automatizar el proceso de instalacion de civicrm en una maquina virtual 
#este incluye todos los pasos recabados en el diario.txt, donde se data el paso a paso de una instalacion manual

# TODO (tuyo): explica qué hace cada una de las tres letras de "set -euo" y qué
#-e: para el script en cuanto un comando falle.
#-u: falla si usas una variable que no existe.
#-o pipefail: en una tubería (a | b), si falla cualquiera de las partes, falla el conjunto
#si el apt install fallara y el script siguiera adelante, llegaría a configurar nginx y a lanzar cv core:install sobre un sistema sin PHP. 
#El resultado sería un montón de errores confusos, lejos del problema real. Con -e para en el primer fallo y sabes exactamente dónde..
set -euo pipefail

# ---------------------------------------------------------------------------
# BLOQUE 1 - Comprobaciones previas
# ---------------------------------------------------------------------------
# Comprobamos que el script no se ejecute como root porque queremos que el
# usuario ejecute el script normalmente y que sudo se utilice únicamente en
# los comandos que necesitan privilegios de administrador.
      
if [ "$EUID" -eq 0 ]; then
    echo "ERROR: no ejecutes este script con sudo."
    echo "       Ejecútalo como tu usuario normal: ./instalar-civicrm.sh"
    exit 1
fi

# "sudo -v" solicita/autentica las credenciales de sudo al principio del script.
# Así evitamos que el script se detenga posteriormente esperando la contraseña.

sudo -v

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${DIR_SCRIPT}/.env"
ENV_EJEMPLO="${DIR_SCRIPT}/.env.example"

# TODO (tuyo): explica por qué el script crea el .env si no existe, en vez de
#              limitarse a avisar, y por qué las contraseñas se piden con
#              "read -s" (pista: lo que se teclea no se ve ni queda en pantalla).
if [ ! -f "$ENV_FILE" ]; then
    if [ ! -f "$ENV_EJEMPLO" ]; then
        echo "ERROR: no hay .env ni .env.example en ${DIR_SCRIPT}"
        exit 1
    fi
    echo ">>> No hay .env. Se va a crear a partir de .env.example."
    cp "$ENV_EJEMPLO" "$ENV_FILE"

    read -r -p "    Contraseña para el usuario de MariaDB (solo letras y números): " -s NUEVA_DB_PASS; echo
    read -r -p "    Contraseña para el administrador de CiviCRM (solo letras y números): " -s NUEVA_ADMIN_PASS; echo
    read -r -p "    Correo del administrador: " NUEVO_ADMIN_EMAIL

    sed -i \
        -e "s|^DB_PASS=.*|DB_PASS=${NUEVA_DB_PASS}|" \
        -e "s|^ADMIN_PASS=.*|ADMIN_PASS=${NUEVA_ADMIN_PASS}|" \
        -e "s|^ADMIN_EMAIL=.*|ADMIN_EMAIL=${NUEVO_ADMIN_EMAIL}|" \
        "$ENV_FILE"
    unset NUEVA_DB_PASS NUEVA_ADMIN_PASS NUEVO_ADMIN_EMAIL
    echo ">>> .env creado. Guarda esas contraseñas en el gestor de contraseñas."
fi

# TODO (tuyo): explica por qué el .env sólo debe poder leerlo su propietario.
chmod 600 "$ENV_FILE"

# TODO (tuyo): explica por qué no usamos "source" directamente y qué es el
#              carácter \r que se elimina aquí (pista: el error que dio el .env
#              la primera vez que se ejecutó el script en la máquina nueva).
while IFS= read -r linea || [ -n "$linea" ]; do
    linea="${linea%$'\r'}"
    case "$linea" in
        ''|'#'*) continue ;;
    esac
    clave="${linea%%=*}"
    valor="${linea#*=}"
    if [[ ! "$clave" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        continue
    fi
    valor="${valor%\"}"
    valor="${valor#\"}"
    export "${clave}=${valor}"
done < "$ENV_FILE"

for var in DB_NAME DB_USER DB_PASS DB_HOST DB_PORT \
           ADMIN_USER ADMIN_PASS ADMIN_EMAIL \
           SITE_URL SITE_PORT SITE_ROOT CIVI_VERSION PHP_VERSION; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: la variable $var está vacía en el .env"
        exit 1
    fi
done

# Verificamos que la contraseña no contenga simbolos, solo letras y numero
for var in DB_PASS ADMIN_PASS; do
    if [[ ! "${!var}" =~ ^[A-Za-z0-9]+$ ]]; then
        echo "ERROR: $var sólo puede contener letras y números (sin símbolos ni ñ)."
        exit 1
    fi
done

echo ">>> Comprobaciones previas superadas."

# ---------------------------------------------------------------------------
# BLOQUE 2 - Instalación de paquetes (Paso 2 del ticket)
# ---------------------------------------------------------------------------

# nginx actúa como servidor web, MariaDB como sistema de base de datos,
# PHP-FPM permite ejecutar PHP desde nginx, mientras que git, curl y unzip
# proporcionan herramientas necesarias para descargar y manejar CiviCRM.
#  instalamos intl para el idioma y region y bcmath para los calculos basicos como donaciones, moneda, etc.
echo ">>> Instalando paquetes del sistema..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    nginx mariadb-server git curl unzip \
    "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-cli" "php${PHP_VERSION}-mysql" \
    "php${PHP_VERSION}-curl" "php${PHP_VERSION}-gd" "php${PHP_VERSION}-mbstring" \
    "php${PHP_VERSION}-xml" "php${PHP_VERSION}-zip" "php${PHP_VERSION}-bcmath" \
    "php${PHP_VERSION}-intl"

PHP_REAL="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
if [ "$PHP_REAL" != "$PHP_VERSION" ]; then
    echo "ERROR: el .env dice PHP $PHP_VERSION pero el sistema tiene $PHP_REAL"
    exit 1
fi

# Revision de version de php, CiviCRM 6.x necesita PHP 8.1 o superior el ticket pide que sea asi.

PHP_MIN_MAJOR=8
PHP_MIN_MINOR=1
PHP_MAJOR="${PHP_REAL%%.*}"
PHP_MINOR="${PHP_REAL##*.}"
if [ "$PHP_MAJOR" -lt "$PHP_MIN_MAJOR" ] || \
   { [ "$PHP_MAJOR" -eq "$PHP_MIN_MAJOR" ] && [ "$PHP_MINOR" -lt "$PHP_MIN_MINOR" ]; }; then
    echo "ERROR: CiviCRM $CIVI_VERSION necesita PHP >= ${PHP_MIN_MAJOR}.${PHP_MIN_MINOR}"
    echo "       El sistema tiene PHP $PHP_REAL"
    exit 1
fi

echo ">>> Paquetes instalados. PHP $PHP_REAL compatible con CiviCRM $CIVI_VERSION."

# ---------------------------------------------------------------------------
# BLOQUE 3 - Configuración de MariaDB (Paso 3 del ticket)
# ---------------------------------------------------------------------------

# El fichero 99-civicrm.cnf contiene ajustes específicos de MariaDB para
# CiviCRM. Se coloca en mariadb.conf.d para que MariaDB lo cargue como parte
# de su configuración.

echo ">>> Configurando MariaDB..."
sudo tee /etc/mysql/mariadb.conf.d/99-civicrm.cnf > /dev/null <<'EOF'
[mysqld]
# Modo no estricto: CiviCRM genera consultas que el modo estricto rechaza
sql_mode = ""
# Memoria por hilo que necesita CiviCRM
thread_stack = 256K
# Permite crear funciones almacenadas sin privilegio SUPER
log_bin_trust_function_creators = 1
EOF

# Reiniciamos MariaDB para que los cambios realizados en su configuración
# entren en vigor.
sudo systemctl restart mariadb

# Cargamos la Zona horaria para Europa/Madrid
echo ">>> Cargando zonas horarias en MariaDB..."
sudo mysql_tzinfo_to_sql /usr/share/zoneinfo 2>/dev/null | sudo mysql -u root mysql

TZ_CHECK="$(sudo mysql -u root -N -B -e \
    "SELECT CONVERT_TZ('2026-01-01 12:00:00','UTC','Europe/Madrid');")"
if [ "$TZ_CHECK" = "NULL" ] || [ -z "$TZ_CHECK" ]; then
    echo "ERROR: las zonas horarias no se han cargado (CONVERT_TZ devuelve NULL)"
    exit 1
fi

# ---------------------------------------------------------------------------
# BLOQUE 4 - Base de datos y usuario (Paso 3 del ticket)
# ---------------------------------------------------------------------------
# CREATE DATABASE crea la base de datos donde CiviCRM almacenará su información.
# CREATE USER crea el usuario que utilizará CiviCRM para conectarse a MariaDB.
# GRANT concede a ese usuario permisos sobre la base de datos creada.
# utf8mb4 permite almacenar correctamente caracteres Unicode, incluyendo
# caracteres especiales y una mayor variedad de símbolos que otros juegos
# de caracteres.
echo ">>> Creando base de datos y usuario..."
sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE OR REPLACE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# Después de crear el usuario y concederle permisos comprobamos que realmente
# puede conectarse a la base de datos. Así detectamos inmediatamente problemas
# de usuario, contraseña, permisos o conexión.
if ! mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT 1;" > /dev/null 2>&1; then
    echo "ERROR: no se puede conectar a la base de datos con el usuario $DB_USER"
    exit 1
fi

echo ">>> Base de datos $DB_NAME lista."

# ---------------------------------------------------------------------------
# BLOQUE 5 - Ajustes de PHP (Paso 4 del ticket)
# ---------------------------------------------------------------------------
# Ajuste de php, utilizamos 2 cli/php.ini(Terminal) y fpm/php.ini(Navegador)
# Se modifican los php.ini de CLI y FPM porque PHP se utiliza de dos formas:
# desde la terminal mediante CLI y desde nginx mediante PHP-FPM.
# Si solo modificáramos uno, la configuración podría ser diferente dependiendo
# de si PHP se ejecuta desde la terminal o desde el servidor web.
# memory_limit establece la memoria máxima que puede utilizar PHP.
# max_execution_time limita cuánto tiempo puede ejecutarse un script.
# max_input_time limita el tiempo empleado en recibir datos de entrada.
# upload_max_filesize establece el tamaño máximo de un archivo subido.
# post_max_size establece el tamaño máximo de una petición POST.
# date.timezone establece la zona horaria que utilizará PHP para trabajar con
# fechas y horas.

# sed -i modifica directamente el fichero indicado. Las expresiones regulares
# permiten localizar las configuraciones existentes, estén comentadas o no,
# y reemplazarlas por los valores necesarios.
echo ">>> Ajustando PHP..."
ajustar_php() {
    local ini="$1"
    sudo sed -i \
        -e 's|^;\?\s*memory_limit\s*=.*|memory_limit = 256M|' \
        -e 's|^;\?\s*max_execution_time\s*=.*|max_execution_time = 240|' \
        -e 's|^;\?\s*max_input_time\s*=.*|max_input_time = 120|' \
        -e 's|^;\?\s*upload_max_filesize\s*=.*|upload_max_filesize = 50M|' \
        -e 's|^;\?\s*post_max_size\s*=.*|post_max_size = 50M|' \
        -e 's|^;\?\s*date.timezone\s*=.*|date.timezone = Europe/Madrid|' \
        "$ini"
}

ajustar_php "/etc/php/${PHP_VERSION}/fpm/php.ini"
ajustar_php "/etc/php/${PHP_VERSION}/cli/php.ini"

sudo systemctl restart "php${PHP_VERSION}-fpm"

# ---------------------------------------------------------------------------
# BLOQUE 6 - Descarga y despliegue de CiviCRM (Paso 5 del ticket)
# ---------------------------------------------------------------------------

# TARBALL contiene el nombre del archivo comprimido de CiviCRM y DOWNLOAD_URL
# contiene la dirección desde la que se descargará. Ambos se construyen usando
# CIVI_VERSION para descargar exactamente la versión indicada en el .env.

# Utilizamos un directorio temporal para descargar y descomprimir CiviCRM sin
# dejar archivos temporales en el sistema. Después de copiar la instalación,
# ese directorio se elimina.

# "cp -a" copia el contenido conservando atributos de los archivos. Se copia
# el contenido de civicrm-standalone dentro de SITE_ROOT, que es el directorio
# que nginx utilizará como raíz del sitio.

# Comprobamos primero si CiviCRM ya está desplegado para que el script pueda
# ejecutarse nuevamente sin descargar y copiar toda la instalación otra vez.

# Los archivos pertenecen a www-data porque PHP-FPM se ejecuta con ese usuario.
# De esta forma PHP puede leer y escribir los archivos que necesita CiviCRM.

TARBALL="civicrm-${CIVI_VERSION}-standalone.tar.gz"
DOWNLOAD_URL="https://download.civicrm.org/${TARBALL}"

if [ -d "${SITE_ROOT}/core" ]; then
    echo ">>> CiviCRM ya está desplegado en ${SITE_ROOT}, no se vuelve a descargar."
else
    echo ">>> Descargando CiviCRM ${CIVI_VERSION}..."
    TMPDIR="$(mktemp -d)"
    curl -LsS "$DOWNLOAD_URL" -o "${TMPDIR}/${TARBALL}"
    tar -xzf "${TMPDIR}/${TARBALL}" -C "$TMPDIR"

    sudo mkdir -p "$SITE_ROOT"
    sudo cp -a "${TMPDIR}/civicrm-standalone/." "$SITE_ROOT/"
    rm -rf "$TMPDIR"
fi

sudo chown -R www-data:www-data "$SITE_ROOT"

# ---------------------------------------------------------------------------
# BLOQUE 7 - Configuración de nginx (Paso 6 del ticket)
# ---------------------------------------------------------------------------
# El bloque server define cómo nginx atenderá las peticiones del sitio.
# listen indica el puerto, server_name el nombre del servidor, root la
# ubicación de los archivos y index el archivo utilizado como entrada.

# private/ contiene información sensible de CiviCRM, especialmente
# civicrm.settings.php, donde se encuentran las credenciales de la base de
# datos. Por eso no debe poder descargarse desde Internet.

# try_files comprueba si la petición corresponde a un archivo o directorio
# existente. Si no existe, la petición se envía a index.php para que CiviCRM
# pueda procesar sus rutas internas.

# fastcgi_pass indica que nginx debe enviar los archivos PHP al servicio
# PHP-FPM mediante su socket Unix para que sean ejecutados.

# sites-available contiene las configuraciones disponibles de nginx y
# sites-enabled contiene las configuraciones que nginx tiene habilitadas.
# El enlace simbólico permite habilitar la configuración sin duplicar el
# archivo.

echo ">>> Configurando nginx..."
sudo tee /etc/nginx/sites-available/civicrm > /dev/null <<EOF
server {
    listen ${SITE_PORT};
    server_name localhost;
    root ${SITE_ROOT};
    index index.php;

    # private/ contiene civicrm.settings.php con las credenciales de la BD.
    # El ^~ tiene prioridad sobre las expresiones regulares: sin él, una
    # petición a private/civicrm.settings.php la capturaría el bloque de PHP.
    location ^~ /private/ {
        deny all;
    }

    # Las rutas internas de CiviCRM (/civicrm/...) no existen en disco:
    # si no hay fichero ni directorio, se entregan a index.php.
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # nginx no sabe ejecutar PHP: se lo pasa a php-fpm por el socket unix.
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
    }
}
EOF

# "ln -sf" crea el enlace simbólico y, con "-f", reemplaza un enlace existente
# si ya lo hubiera. Esto permite ejecutar el script nuevamente sin que falle
# por existir previamente el enlace.
sudo ln -sf /etc/nginx/sites-available/civicrm /etc/nginx/sites-enabled/civicrm

# nginx -t comprueba la sintaxis y validez de la configuración antes de
# recargar nginx. Si recargáramos una configuración incorrecta, nginx podría
# rechazarla o el servidor podría quedar funcionando con problemas.
sudo nginx -t
sudo systemctl reload nginx

# ---------------------------------------------------------------------------
# BLOQUE 8 - Instalación de cv y de CiviCRM (Paso 7 del ticket)
# ---------------------------------------------------------------------------

# cv es la herramienta de línea de comandos de CiviCRM. Permite realizar tareas
# administrativas, entre ellas instalar y configurar CiviCRM desde la terminal.

# /usr/local/bin está destinado normalmente a programas instalados
# manualmente por el administrador y forma parte del PATH del sistema.
# chmod +x permite ejecutar cv como un programa.
if ! command -v cv > /dev/null 2>&1; then
    echo ">>> Instalando cv..."
    sudo curl -LsS https://download.civicrm.org/cv/cv.phar -o /usr/local/bin/cv
    sudo chmod +x /usr/local/bin/cv
fi

# cv se ejecuta como www-data porque ese es el usuario utilizado por PHP-FPM
# y el propietario de los archivos de CiviCRM. Así la instalación genera los
# archivos con los permisos adecuados para el funcionamiento del sitio.

if [ -f "${SITE_ROOT}/private/civicrm.settings.php" ]; then
    echo ">>> CiviCRM ya está instalado, se omite core:install."
else
    echo ">>> Instalando CiviCRM (esto tarda un par de minutos)..."
    cd "$SITE_ROOT"
    sudo -u www-data cv core:install \
        --url="${SITE_URL}" \
        --db="mysql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}" \
        -m "extras.adminUser=${ADMIN_USER}" \
        -m "extras.adminPass=${ADMIN_PASS}" \
        -m "extras.adminEmail=${ADMIN_EMAIL}"
fi

# ---------------------------------------------------------------------------
# BLOQUE 9 - Verificación final
# ---------------------------------------------------------------------------

# Comprobamos que nginx, PHP-FPM y MariaDB estén activos porque los tres
# servicios son necesarios para que CiviCRM pueda funcionar correctamente.

# private/ debe devolver 403 (Forbidden) porque contiene archivos de
# configuración sensibles que no deben ser accesibles desde el navegador.

# Si private/civicrm.settings.php devolviera 200, significaría que el servidor
# está permitiendo acceder directamente al fichero de configuración y podría
# exponer credenciales de la base de datos y otra información sensible.
echo ">>> Verificando instalación..."

for servicio in nginx "php${PHP_VERSION}-fpm" mariadb; do
    if [ "$(systemctl is-active "$servicio")" != "active" ]; then
        echo "ERROR: el servicio $servicio no está activo"
        exit 1
    fi
done

# CODIGO_HOME muestra el estado HTTP de CiviCRM, CODIGO_PRIV confirma que
# private/ está protegido y la consulta a information_schema permite comprobar
# cuántas tablas existen actualmente en la base de datos de CiviCRM.

CODIGO_HOME="$(curl -s -o /dev/null -w '%{http_code}' "${SITE_URL}/civicrm/")"
CODIGO_PRIV="$(curl -s -o /dev/null -w '%{http_code}' "${SITE_URL}/private/civicrm.settings.php")"

if [ "$CODIGO_PRIV" != "403" ]; then
    echo "ERROR: private/ es accesible por web (código $CODIGO_PRIV)"
    exit 1
fi

echo
echo "============================================================"
echo " Instalación completada"
echo "   Sitio:    ${SITE_URL}/civicrm/   (HTTP $CODIGO_HOME)"
echo "   Usuario:  ${ADMIN_USER}"
echo "   private/: protegido (HTTP $CODIGO_PRIV)"
echo "   Tablas:   $(sudo mysql -u root -N -B -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='${DB_NAME}';")"
echo "============================================================"
