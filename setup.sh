#!/bin/bash
# =============================================================
#  SETUP SCRIPT — TreTrauNetwork
#  Chạy với quyền root: sudo bash setup.sh
# =============================================================

set -e

# ─── MÀU SẮC ────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${NC}"; \
            echo -e "${BOLD}${CYAN}  $1${NC}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════${NC}"; }

# ─── KIỂM TRA ROOT ──────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Script cần chạy với quyền root. Dùng: sudo bash $0"

# =============================================================
#  CẤU HÌNH — Chỉnh sửa trước khi chạy
# =============================================================
DOMAIN="yourdomain.com"               # ← ĐỔI THÀNH DOMAIN CỦA BẠN
WEBROOT="/var/www/tretrau"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ZIP="${SCRIPT_DIR}/tretrau.zip"

DB_HOST="127.0.0.1"
DB_NAME="marketplace_db"
DB_USER="tretrau_user"
DB_PASS="TreTrau@$(date +%s | sha256sum | head -c 8)"

ADMIN_USER="admin"
ADMIN_EMAIL="admin@${DOMAIN}"
ADMIN_PASS="Admin@$(date +%s | sha256sum | head -c 10)"

TELEGRAM_BOT_TOKEN="8336938728:AAH9QDiLrpb-OLtTj9zWB9ouWKnRV4-UHx4"
TELEGRAM_ADMIN_CHAT_ID="7567975053"

PHP_VERSION="8.2"
# =============================================================

LOG_FILE="/tmp/tretrau_setup_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${BOLD}"
cat << 'BANNER'
  _____          _____                   _   _      _
 |_   _| __ ___|_   _| __ __ _ _   _  | \ | | ___| |___      _____  _ __| | __
   | || '__/ _ \ | || '__/ _` | | | | |  \| |/ _ \ __\ \ /\ / / _ \| '__| |/ /
   | || | |  __/ | || | | (_| | |_| | | |\  |  __/ |_ \ V  V / (_) | |  |   <
   |_||_|  \___| |_||_|  \__,_|\__,_| |_| \_|\___|\__| \_/\_/ \___/|_|  |_|\_\
BANNER
echo -e "${NC}"
echo -e "  Setup Script — TreTrauNetwork Marketplace"
echo -e "  Log: $LOG_FILE\n"

# =============================================================
header "1. Cập nhật hệ thống"
# =============================================================
info "apt update & upgrade..."
apt-get update -qq
apt-get upgrade -y -qq
success "Hệ thống đã cập nhật."

# =============================================================
header "2. Thêm PHP PPA & cài đặt các gói"
# =============================================================
info "Thêm ondrej/php PPA..."
apt-get install -y -qq software-properties-common
add-apt-repository ppa:ondrej/php -y
apt-get update -qq

info "Cài đặt nginx, PHP ${PHP_VERSION}, MariaDB, unzip, curl, python3..."
apt-get install -y -qq \
    nginx \
    mariadb-server mariadb-client \
    php${PHP_VERSION}-fpm \
    php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-intl \
    php${PHP_VERSION}-bcmath \
    php${PHP_VERSION}-opcache \
    python3 python3-pip \
    unzip curl git openssl ufw

pip3 install requests --break-system-packages -q

success "Tất cả gói đã được cài đặt."

# =============================================================
header "3. Giải nén source code"
# =============================================================
[[ ! -f "$SOURCE_ZIP" ]] && error "Không tìm thấy file: $SOURCE_ZIP"

info "Giải nén vào ${WEBROOT}..."
mkdir -p "$WEBROOT"
rm -rf /tmp/tretrau_extract
unzip -oq "$SOURCE_ZIP" -d /tmp/tretrau_extract

# Tìm thư mục gốc trong zip
EXTRACTED_DIR=$(find /tmp/tretrau_extract -maxdepth 1 -mindepth 1 -type d | head -1)
if [[ -z "$EXTRACTED_DIR" ]]; then
    cp -r /tmp/tretrau_extract/. "$WEBROOT/"
else
    cp -r "${EXTRACTED_DIR}/." "$WEBROOT/"
fi
rm -rf /tmp/tretrau_extract
success "Source code đã giải nén vào ${WEBROOT}."

# =============================================================
header "4. Cấu hình PHP"
# =============================================================
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
PHP_POOL="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

info "Cấu hình php.ini..."
sed -i 's/^display_errors.*/display_errors = Off/' "$PHP_INI"
sed -i 's/^log_errors.*/log_errors = On/' "$PHP_INI"
sed -i 's/^output_buffering.*/output_buffering = On/' "$PHP_INI"
sed -i 's/^upload_max_filesize.*/upload_max_filesize = 10M/' "$PHP_INI"
sed -i 's/^post_max_size.*/post_max_size = 12M/' "$PHP_INI"
sed -i 's/^max_execution_time.*/max_execution_time = 60/' "$PHP_INI"
sed -i 's/^memory_limit.*/memory_limit = 256M/' "$PHP_INI"
sed -i 's/^;date.timezone.*/date.timezone = Asia\/Ho_Chi_Minh/' "$PHP_INI"
sed -i 's/^cgi.fix_pathinfo=.*/cgi.fix_pathinfo=0/' "$PHP_INI"
echo 'cgi.fix_pathinfo=0' >> "$PHP_INI"

# OPcache
cat >> "$PHP_INI" << 'OPCACHE'
; OPcache
opcache.enable=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.revalidate_freq=2
OPCACHE

# Fix open_basedir trong php-fpm pool — cho phép webroot
info "Fix open_basedir trong PHP-FPM pool..."
# Xóa dòng open_basedir cũ nếu có
sed -i '/open_basedir/d' "$PHP_POOL"
# Thêm đúng path
cat >> "$PHP_POOL" << POOL
php_admin_value[open_basedir] = ${WEBROOT}/:/tmp/:/var/tmp/
POOL

info "Khởi động lại PHP-FPM..."
systemctl restart php${PHP_VERSION}-fpm
systemctl enable php${PHP_VERSION}-fpm
success "PHP ${PHP_VERSION} đã cấu hình xong."

# =============================================================
header "5. Cấu hình MariaDB & tạo Database"
# =============================================================
info "Khởi động MariaDB..."
systemctl start mariadb
systemctl enable mariadb

info "Tạo database và user..."
mysql -u root << MYSQL_SCRIPT
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

DROP USER IF EXISTS '${DB_USER}'@'${DB_HOST}';
CREATE USER '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_HOST}';

FLUSH PRIVILEGES;
MYSQL_SCRIPT

success "Database '${DB_NAME}' và user '${DB_USER}' đã được tạo."

# =============================================================
header "6. Cập nhật config.php"
# =============================================================
CONFIG_FILE="${WEBROOT}/config.php"
[[ ! -f "$CONFIG_FILE" ]] && error "Không tìm thấy config.php tại ${CONFIG_FILE}"

info "Ghi cấu hình vào config.php..."
sed -i "s|define('DB_HOST'.*|define('DB_HOST', '${DB_HOST}');|" "$CONFIG_FILE"
sed -i "s|define('DB_NAME'.*|define('DB_NAME', '${DB_NAME}');|" "$CONFIG_FILE"
sed -i "s|define('DB_USER'.*|define('DB_USER', '${DB_USER}');|" "$CONFIG_FILE"
sed -i "s|define('DB_PASS'.*|define('DB_PASS', '${DB_PASS}');|" "$CONFIG_FILE"
sed -i "s|define('SITE_URL'.*|define('SITE_URL', 'https://${DOMAIN}');|" "$CONFIG_FILE"
sed -i "s|define('TELEGRAM_BOT_TOKEN'.*|define('TELEGRAM_BOT_TOKEN', '${TELEGRAM_BOT_TOKEN}');|" "$CONFIG_FILE"
sed -i "s|define('TELEGRAM_ADMIN_CHAT_ID'.*|define('TELEGRAM_ADMIN_CHAT_ID', '${TELEGRAM_ADMIN_CHAT_ID}');|" "$CONFIG_FILE"

success "config.php đã được cập nhật."

# =============================================================
header "7. Khởi tạo Database Schema"
# =============================================================
info "Chạy installDatabase() qua PHP CLI..."
php -r "
define('DB_HOST', '${DB_HOST}');
define('DB_NAME', '${DB_NAME}');
define('DB_USER', '${DB_USER}');
define('DB_PASS', '${DB_PASS}');
define('SITE_URL', 'https://${DOMAIN}');
define('SITE_NAME', 'TreTrauNetwork');
define('UPLOAD_DIR', '${WEBROOT}/uploads/');
define('MAX_FILE_SIZE', 5242880);
define('ALLOWED_MIME', ['image/jpeg','image/png','image/webp','image/gif']);
define('SESSION_LIFETIME', 604800);
define('NEW_ACC_DAILY_POST_LIMIT', 1);
define('PREMIUM_ACC_DAILY_POST_LIMIT', 10);
define('TELEGRAM_BOT_TOKEN', '${TELEGRAM_BOT_TOKEN}');
define('TELEGRAM_ADMIN_CHAT_ID', '${TELEGRAM_ADMIN_CHAT_ID}');
chdir('${WEBROOT}');
require '${WEBROOT}/config.php';
installDatabase();
echo 'Schema installed successfully.';
" 2>&1 || warn "Có thể schema đã tồn tại — kiểm tra log."

# Tạo admin user
info "Tạo tài khoản admin..."
ADMIN_HASH=$(php -r "echo password_hash('${ADMIN_PASS}', PASSWORD_DEFAULT);")
mysql -u root "${DB_NAME}" << ADMIN_SQL
INSERT IGNORE INTO users (username, email, password_hash, role)
VALUES ('${ADMIN_USER}', '${ADMIN_EMAIL}', '${ADMIN_HASH}', 'admin');
ADMIN_SQL
success "Admin account đã được tạo."

# =============================================================
header "8. Phân quyền thư mục"
# =============================================================
info "Đặt quyền cho ${WEBROOT}..."
chown -R www-data:www-data "$WEBROOT"
find "$WEBROOT" -type d -exec chmod 755 {} \;
find "$WEBROOT" -type f -exec chmod 644 {} \;
chmod -R 775 "${WEBROOT}/uploads"
chmod 600 "$CONFIG_FILE"
success "Phân quyền hoàn tất."

# =============================================================
header "9. Cấu hình Nginx (Cloudflare-ready)"
# =============================================================
NGINX_CONF="/etc/nginx/sites-available/tretrau"
info "Tạo virtual host Nginx..."
cat > "$NGINX_CONF" << NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};
    root ${WEBROOT};
    index index.php index.html;

    charset utf-8;
    client_max_body_size 12M;

    access_log /var/log/nginx/tretrau_access.log;
    error_log  /var/log/nginx/tretrau_error.log;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    server_tokens off;

    # Cloudflare real IP
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 131.0.72.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    real_ip_header CF-Connecting-IP;

    location ~ /\. {
        deny all;
        return 404;
    }

    location ~* \.(sql|log|env|sh|py|rb|bak|config|installed)$ {
        deny all;
        return 404;
    }

    location ~* ^/uploads/.*\.php$ {
        deny all;
        return 403;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$document_root;
        include fastcgi_params;
        fastcgi_read_timeout 60;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|webp|svg|woff|woff2)$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    gzip_min_length 256;
}
NGINX

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/tretrau
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl restart nginx && systemctl enable nginx
success "Nginx đã được cấu hình."

# =============================================================
header "10. Fix SERVER_URL trong start.py"
# =============================================================
START_PY="${WEBROOT}/start.py"
if [[ -f "$START_PY" ]]; then
    sed -i 's|SERVER_URL.*=.*"http://0\.0\.0\.0:[0-9]*"|SERVER_URL     = "http://127.0.0.1"|' "$START_PY"
    sed -i 's|SERVER_URL.*=.*"http://localhost:[0-9]*"|SERVER_URL     = "http://127.0.0.1"|' "$START_PY"
    success "start.py đã được fix SERVER_URL."
fi

# =============================================================
header "11. Cấu hình Firewall (UFW)"
# =============================================================
info "Mở port 22, 80, 443..."
ufw --force reset > /dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 'Nginx Full'
ufw --force enable
success "Firewall đã bật."

# =============================================================
header "12. Cài bot như systemd service"
# =============================================================
cat > /etc/systemd/system/tretrau-bot.service << SERVICE
[Unit]
Description=TreTrauNetwork Telegram Bot
After=network.target mariadb.service

[Service]
Type=simple
User=root
WorkingDirectory=${WEBROOT}
ExecStart=/usr/bin/python3 ${WEBROOT}/start.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable tretrau-bot
systemctl start tretrau-bot
success "Telegram bot đã chạy như systemd service."

# =============================================================
header "13. Xoá file nhạy cảm"
# =============================================================
rm -f "${WEBROOT}/setup.php" "${WEBROOT}/.installed" "${WEBROOT}/test.php"
success "Đã xóa các file nhạy cảm."

# =============================================================
header "14. Kiểm tra cuối"
# =============================================================
systemctl is-active php${PHP_VERSION}-fpm > /dev/null && success "PHP-FPM: RUNNING" || warn "PHP-FPM: NOT running"
systemctl is-active nginx > /dev/null && success "Nginx: RUNNING" || warn "Nginx: NOT running"
systemctl is-active mariadb > /dev/null && success "MariaDB: RUNNING" || warn "MariaDB: NOT running"
systemctl is-active tretrau-bot > /dev/null && success "Telegram Bot: RUNNING" || warn "Telegram Bot: NOT running"
curl -s -o /dev/null -w "%{http_code}" http://localhost/ | grep -q "200" && success "Website: OK (HTTP 200)" || warn "Website: kiểm tra thủ công"

# =============================================================
#  TỔNG KẾT
# =============================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║         SETUP HOÀN TẤT — TreTrauNetwork             ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Website:${NC}        https://${DOMAIN}"
echo -e "  ${BOLD}Admin panel:${NC}    https://${DOMAIN}/admin/admin.php"
echo -e "  ${BOLD}Webroot:${NC}        ${WEBROOT}"
echo ""
echo -e "  ${BOLD}${YELLOW}─── THÔNG TIN ĐĂNG NHẬP ────────────────────────────${NC}"
echo -e "  ${BOLD}Admin user:${NC}     ${ADMIN_USER}"
echo -e "  ${BOLD}Admin pass:${NC}     ${ADMIN_PASS}"
echo -e "  ${BOLD}Admin email:${NC}    ${ADMIN_EMAIL}"
echo ""
echo -e "  ${BOLD}${YELLOW}─── DATABASE ────────────────────────────────────────${NC}"
echo -e "  ${BOLD}DB Name:${NC}        ${DB_NAME}"
echo -e "  ${BOLD}DB User:${NC}        ${DB_USER}"
echo -e "  ${BOLD}DB Pass:${NC}        ${DB_PASS}"
echo ""
echo -e "  ${BOLD}${YELLOW}─── BOT ─────────────────────────────────────────────${NC}"
echo -e "  ${BOLD}Bot status:${NC}     systemctl status tretrau-bot"
echo -e "  ${BOLD}Bot logs:${NC}       journalctl -u tretrau-bot -f"
echo ""
echo -e "  ${BOLD}${RED}QUAN TRỌNG:${NC}"
echo -e "  • Cloudflare SSL mode: Full hoặc Full (Strict)"
echo -e "  • Đổi mật khẩu admin ngay sau khi đăng nhập"
echo -e "  • Log: ${LOG_FILE}"
echo ""
