#!/bin/bash

# LiquorPro Production Server Initial Setup Script
# Server: 72.60.96.174
# This script must be run as root on a fresh Ubuntu 22.04 LTS server

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

log_info "========================================="
log_info "LiquorPro Production Server Setup"
log_info "========================================="
echo ""

# ========================================
# Step 1: Update System
# ========================================
log_step "Step 1: Updating system packages..."
apt-get update -y
apt-get upgrade -y
apt-get dist-upgrade -y
apt-get autoremove -y
log_info "System updated successfully"
echo ""

# ========================================
# Step 2: Install Essential Tools
# ========================================
log_step "Step 2: Installing essential tools..."
apt-get install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    ufw \
    fail2ban \
    certbot \
    python3-certbot-nginx \
    net-tools \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release
log_info "Essential tools installed"
echo ""

# ========================================
# Step 3: Install Docker
# ========================================
log_step "Step 3: Installing Docker..."

# Remove old Docker installations
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker's official GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Verify Docker installation
docker --version
log_info "Docker installed: $(docker --version)"
echo ""

# ========================================
# Step 4: Install Docker Compose
# ========================================
log_step "Step 4: Installing Docker Compose..."
DOCKER_COMPOSE_VERSION="2.24.0"
curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify Docker Compose installation
docker-compose --version
log_info "Docker Compose installed: $(docker-compose --version)"
echo ""

# ========================================
# Step 5: Install Nginx
# ========================================
log_step "Step 5: Installing Nginx..."
apt-get install -y nginx
systemctl start nginx
systemctl enable nginx

# Verify Nginx installation
nginx -v
log_info "Nginx installed: $(nginx -v 2>&1)"
echo ""

# ========================================
# Step 6: Create Non-Root Deploy User
# ========================================
log_step "Step 6: Creating deploy user..."
if id "deploy" &>/dev/null; then
    log_warn "User 'deploy' already exists, skipping..."
else
    useradd -m -s /bin/bash deploy
    usermod -aG sudo deploy
    usermod -aG docker deploy

    # Set up SSH for deploy user
    mkdir -p /home/deploy/.ssh
    chmod 700 /home/deploy/.ssh
    touch /home/deploy/.ssh/authorized_keys
    chmod 600 /home/deploy/.ssh/authorized_keys
    chown -R deploy:deploy /home/deploy/.ssh

    log_info "User 'deploy' created successfully"
    log_warn "IMPORTANT: Add your SSH public key to /home/deploy/.ssh/authorized_keys"
fi
echo ""

# ========================================
# Step 7: Configure SSH Security
# ========================================
log_step "Step 7: Configuring SSH security..."

# Backup original SSH config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Configure SSH
sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Add security settings
echo "AllowUsers deploy" >> /etc/ssh/sshd_config
echo "MaxAuthTries 3" >> /etc/ssh/sshd_config
echo "MaxSessions 2" >> /etc/ssh/sshd_config
echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
echo "ClientAliveCountMax 2" >> /etc/ssh/sshd_config

log_info "SSH configured (Port: 2222, Root login disabled)"
log_warn "SSH will restart at the end of this script"
echo ""

# ========================================
# Step 8: Configure Firewall (UFW)
# ========================================
log_step "Step 8: Configuring firewall..."

# Reset UFW
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH on custom port
ufw allow 2222/tcp comment 'SSH'

# Allow HTTP and HTTPS
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Enable UFW
ufw --force enable

ufw status verbose
log_info "Firewall configured and enabled"
echo ""

# ========================================
# Step 9: Configure Fail2ban
# ========================================
log_step "Step 9: Configuring Fail2ban..."

# Create custom jail for SSH
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = admin@yourdomain.com
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = 2222
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
findtime = 60
bantime = 3600
EOF

systemctl restart fail2ban
systemctl enable fail2ban

log_info "Fail2ban configured and enabled"
echo ""

# ========================================
# Step 10: Create Directory Structure
# ========================================
log_step "Step 10: Creating directory structure..."

mkdir -p /opt/liquorpro/{backend,nginx,logs,backups,scripts,monitoring,data}
mkdir -p /opt/liquorpro/nginx/{sites-available,conf.d,ssl}
mkdir -p /opt/liquorpro/logs/{nginx,gateway,auth,sales,inventory,finance,saas,postgres,redis}
mkdir -p /opt/liquorpro/backups/{postgres,redis}
mkdir -p /opt/liquorpro/data/{postgres,redis}

# Set permissions
chown -R deploy:deploy /opt/liquorpro
chmod -R 755 /opt/liquorpro
chmod -R 700 /opt/liquorpro/data  # Secure data directory

log_info "Directory structure created at /opt/liquorpro"
echo ""

# ========================================
# Step 11: Configure System Limits
# ========================================
log_step "Step 11: Configuring system limits..."

cat >> /etc/security/limits.conf <<EOF

# LiquorPro Production Limits
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
root soft nofile 65536
root hard nofile 65536
deploy soft nofile 65536
deploy hard nofile 65536
EOF

# Sysctl tuning
cat >> /etc/sysctl.conf <<EOF

# LiquorPro Network Tuning
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10000 65000
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
vm.swappiness = 10
fs.file-max = 2097152
EOF

sysctl -p

log_info "System limits configured"
echo ""

# ========================================
# Step 12: Generate DH Parameters for Nginx
# ========================================
log_step "Step 12: Generating DH parameters (this may take several minutes)..."
if [ ! -f /etc/nginx/dhparam.pem ]; then
    openssl dhparam -out /etc/nginx/dhparam.pem 4096
    log_info "DH parameters generated"
else
    log_warn "DH parameters already exist, skipping..."
fi
echo ""

# ========================================
# Step 13: Configure Log Rotation
# ========================================
log_step "Step 13: Configuring log rotation..."

cat > /etc/logrotate.d/liquorpro <<EOF
/opt/liquorpro/logs/*/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 deploy deploy
    sharedscripts
    postrotate
        docker-compose -f /opt/liquorpro/backend/docker-compose.production.yml restart > /dev/null 2>&1 || true
    endscript
}

/opt/liquorpro/logs/nginx/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 www-data www-data
    sharedscripts
    postrotate
        systemctl reload nginx > /dev/null 2>&1
    endscript
}
EOF

log_info "Log rotation configured"
echo ""

# ========================================
# Step 14: Set Timezone
# ========================================
log_step "Step 14: Setting timezone to UTC..."
timedatectl set-timezone UTC
log_info "Timezone set to $(timedatectl | grep 'Time zone')"
echo ""

# ========================================
# Step 15: Install Monitoring Tools
# ========================================
log_step "Step 15: Installing monitoring tools..."
apt-get install -y prometheus-node-exporter
systemctl start prometheus-node-exporter
systemctl enable prometheus-node-exporter
log_info "Node Exporter installed for Prometheus monitoring"
echo ""

# ========================================
# Final Steps
# ========================================
log_info "========================================="
log_info "✅ Initial setup completed successfully!"
log_info "========================================="
echo ""

log_warn "IMPORTANT NEXT STEPS:"
echo ""
echo "1. Add your SSH public key to /home/deploy/.ssh/authorized_keys"
echo "2. Test SSH connection on port 2222 BEFORE logging out:"
echo "   ssh -p 2222 deploy@72.60.96.174"
echo ""
echo "3. Configure your domain DNS:"
echo "   A record: yourdomain.com → 72.60.96.174"
echo ""
echo "4. Generate SSL certificate:"
echo "   certbot --nginx -d yourdomain.com -d www.yourdomain.com"
echo ""
echo "5. Clone your backend repository:"
echo "   cd /opt/liquorpro/backend"
echo "   git clone https://github.com/your-org/liquorpro.git ."
echo ""
echo "6. Copy deployment files:"
echo "   cp deployment/nginx/* /opt/liquorpro/nginx/"
echo "   cp .env.production.example .env.production"
echo "   Edit .env.production with your actual values"
echo ""
echo "7. Deploy services:"
echo "   cd /opt/liquorpro/backend"
echo "   ./deployment/scripts/deploy-production.sh"
echo ""

log_warn "Restarting SSH service in 5 seconds..."
sleep 5
systemctl restart sshd

log_info "SSH restarted on port 2222"
log_info "You can now connect with: ssh -p 2222 deploy@72.60.96.174"
