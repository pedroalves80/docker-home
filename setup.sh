#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

print_header() {
    echo -e "\n${BLUE}=====================================${NC}"
    echo -e "${BLUE}  Docker Home Setup${NC}"
    echo -e "${BLUE}=====================================${NC}\n"
}

print_step() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[x]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

# Check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is not installed. Please install it first."
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."

    check_command docker

    # Check for docker compose (v2) or docker-compose (v1)
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        print_error "Docker Compose is not installed. Please install it first."
        exit 1
    fi

    print_success "Prerequisites satisfied (using: $DOCKER_COMPOSE)"
}

# Create data directories
create_directories() {
    print_step "Creating data directories..."

    directories=(
        "data/adguard/work"
        "data/adguard/conf"
        "data/grafana"
        "data/homeassistant"
        "data/model3/postgres"
        "data/modely/postgres"
        "data/portainer"
        "data/pricebuddy/mysql"
        "data/pricebuddy/storage"
        "data/prometheus"
        "data/tailscale"
        "data/traefik"
        "data/uptime-kuma"
        "data/vaultwarden"
        "data/apprise/config"
        "data/apprise/attach"
        "configs/traefik"
        "configs/prometheus"
        "configs/homepage"
        "configs/mosquitto"
    )

    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
    done

    print_success "Data directories created"
}

# Setup environment file
setup_env() {
    print_step "Setting up environment file..."

    if [ -f ".env" ]; then
        print_warning ".env file already exists. Skipping..."
    else
        if [ -f ".env.example" ]; then
            cp .env.example .env
            print_success "Created .env from .env.example"
            print_warning "Please edit .env and set your passwords and API keys!"
        else
            print_error ".env.example not found!"
            exit 1
        fi
    fi
}

# Generate self-signed certificates
generate_certificates() {
    print_step "Checking TLS certificates..."

    CERT_DIR="configs/traefik"
    CERT_FILE="$CERT_DIR/cert.pem"
    KEY_FILE="$CERT_DIR/key.pem"

    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ] && [ "$1" != "--regenerate-certs" ]; then
        print_warning "Certificates already exist. Use --regenerate-certs to regenerate."
        return
    fi

    print_step "Generating self-signed certificates for *.home.lan..."

    # Generate certificate with SAN for wildcard domain
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/CN=*.home.lan/O=Docker Home/C=US" \
        -addext "subjectAltName=DNS:*.home.lan,DNS:home.lan" \
        2>/dev/null

    print_success "Certificates generated:"
    print_success "  - $CERT_FILE"
    print_success "  - $KEY_FILE"
}

# Set proper permissions
set_permissions() {
    print_step "Setting permissions..."

    # Grafana needs specific UID
    if [ -d "data/grafana" ]; then
        # Grafana runs as user 472
        sudo chown -R 472:472 data/grafana 2>/dev/null || chown -R 472:472 data/grafana 2>/dev/null || true
    fi

    # Prometheus data directory
    if [ -d "data/prometheus" ]; then
        chmod -R 777 data/prometheus 2>/dev/null || true
    fi

    # Certificate permissions
    if [ -f "configs/traefik/key.pem" ]; then
        chmod 600 configs/traefik/key.pem
    fi

    print_success "Permissions set"
}

# Create default config files if they don't exist
create_default_configs() {
    print_step "Creating default configuration files..."

    # Prometheus config
    if [ ! -f "configs/prometheus/prometheus.yml" ]; then
        cat > configs/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
EOF
        print_success "Created prometheus.yml"
    fi

    # Mosquitto config
    if [ ! -f "configs/mosquitto/mosquitto.conf" ]; then
        cat > configs/mosquitto/mosquitto.conf << 'EOF'
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest stdout
EOF
        print_success "Created mosquitto.conf"
    fi

    # Homepage configs
    if [ ! -f "configs/homepage/settings.yaml" ]; then
        cat > configs/homepage/settings.yaml << 'EOF'
title: Home
background:
  image: ""
  opacity: 50
cardBlur: md
theme: dark
color: slate
headerStyle: clean
layout:
  - Infrastructure:
      style: row
      columns: 4
  - Monitoring:
      style: row
      columns: 4
  - Services:
      style: row
      columns: 4
EOF
        print_success "Created homepage settings.yaml"
    fi

    if [ ! -f "configs/homepage/services.yaml" ]; then
        cat > configs/homepage/services.yaml << 'EOF'
- Infrastructure:
    - Traefik:
        icon: traefik.png
        href: https://traefik.home.lan
        description: Reverse Proxy
    - AdGuard:
        icon: adguard-home.png
        href: https://adguard.home.lan
        description: DNS & Ad Blocking
    - Portainer:
        icon: portainer.png
        href: https://portainer.home.lan
        description: Container Management
    - Home Assistant:
        icon: home-assistant.png
        href: https://homeassistant.home.lan
        description: Home Automation

- Monitoring:
    - Grafana:
        icon: grafana.png
        href: https://grafana.home.lan
        description: Dashboards
    - Prometheus:
        icon: prometheus.png
        href: https://prometheus.home.lan
        description: Metrics
    - Uptime Kuma:
        icon: uptime-kuma.png
        href: https://uptime.home.lan
        description: Uptime Monitoring
    - cAdvisor:
        icon: cadvisor.png
        href: https://cadvisor.home.lan
        description: Container Metrics

- Services:
    - Vaultwarden:
        icon: bitwarden.png
        href: https://vaultwarden.home.lan
        description: Password Manager
    - TeslaMate Model 3:
        icon: tesla.png
        href: https://teslamate-model3.home.lan
        description: Model 3 Tracking
    - TeslaMate Model Y:
        icon: tesla.png
        href: https://teslamate-modely.home.lan
        description: Model Y Tracking
    - PriceBuddy:
        icon: mdi-cash-multiple
        href: https://pricebuddy.home.lan
        description: Price Tracking
EOF
        print_success "Created homepage services.yaml"
    fi

    if [ ! -f "configs/homepage/widgets.yaml" ]; then
        cat > configs/homepage/widgets.yaml << 'EOF'
- resources:
    cpu: true
    memory: true
    disk: /

- datetime:
    text_size: xl
    format:
      dateStyle: long
      timeStyle: short
EOF
        print_success "Created homepage widgets.yaml"
    fi

    if [ ! -f "configs/homepage/bookmarks.yaml" ]; then
        cat > configs/homepage/bookmarks.yaml << 'EOF'
- Developer:
    - GitHub:
        - icon: github.png
          href: https://github.com
EOF
        print_success "Created homepage bookmarks.yaml"
    fi

    if [ ! -f "configs/homepage/docker.yaml" ]; then
        cat > configs/homepage/docker.yaml << 'EOF'
local:
  socket: /var/run/docker.sock
EOF
        print_success "Created homepage docker.yaml"
    fi

    # Traefik config
    if [ ! -f "configs/traefik/traefik.yml" ]; then
        cat > configs/traefik/traefik.yml << 'EOF'
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false
    network: proxy_network

tls:
  certificates:
    - certFile: "/cert.pem"
      keyFile: "/key.pem"

api:
  dashboard: true
  insecure: true
EOF
        print_success "Created traefik.yml"
    fi
}

# Print post-setup instructions
print_instructions() {
    echo -e "\n${GREEN}=====================================${NC}"
    echo -e "${GREEN}  Setup Complete!${NC}"
    echo -e "${GREEN}=====================================${NC}\n"

    echo -e "${YELLOW}Next steps:${NC}\n"
    echo "1. Edit .env file with your passwords and API keys:"
    echo "   ${BLUE}nano .env${NC}"
    echo ""
    echo "2. Configure DNS to point *.home.lan to this server"
    echo ""
    echo "3. Start all services:"
    echo "   ${BLUE}$DOCKER_COMPOSE up -d${NC}"
    echo ""
    echo "4. Access the dashboard at:"
    echo "   ${BLUE}https://home.home.lan${NC}"
    echo ""
    echo -e "${YELLOW}Useful commands:${NC}"
    echo "   View logs:     $DOCKER_COMPOSE logs -f"
    echo "   Stop all:      $DOCKER_COMPOSE down"
    echo "   Update:        $DOCKER_COMPOSE pull && $DOCKER_COMPOSE up -d"
    echo ""
}

# Main execution
main() {
    print_header

    check_prerequisites
    create_directories
    setup_env
    create_default_configs
    generate_certificates "$1"
    set_permissions

    print_instructions
}

# Run main function with all arguments
main "$@"
