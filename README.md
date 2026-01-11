# docker-home

A reproducible home server stack for Raspberry Pi or Linux/ARM computers using Docker Compose, Traefik (as reverse proxy), AdGuard Home (for local DNS rewrites), and HTTPS via self-signed certificates.  
This repo is structured for easy setup, management, and backup of multiple home services.

---

## Table of Contents

- [Directory Structure](#directory-structure)
- [Quickstart Checklist](#quickstart-checklist)
- [Step-by-Step Setup](#step-by-step-setup)
  - [1. Prerequisites](#1-prerequisites)
  - [2. Create Local DNS rewrites (AdGuard Home)](#2-create-local-dns-rewrites-adguard-home)
  - [3. Generate HTTPS Certificates with mkcert](#3-generate-https-certificates-with-mkcert)
  - [4. Secrets and Environment Variables](#4-secrets-and-environment-variables)
  - [5. Start the Stack](#5-start-the-stack)
  - [6. Service Access URLs](#6-service-access-urls)
- [Backup Recommendations](#backup-recommendations)
- [Troubleshooting](#troubleshooting)
- [Extend/Customize](#extendcustomize)

---

## Directory Structure

```
docker-home/
├── docker-compose.yml
├── .env                  # Secrets (DB passwords, keys) - DO NOT COMMIT
├── .env.example          # Template for your environment variables
├── .gitignore
├── configs/
│   ├── traefik/
│   │   ├── traefik.yml   # Traefik static configuration
│   │   ├── cert.pem      # HTTPS certificate (mkcert)
│   │   └── key.pem       # HTTPS key (mkcert)
│   ├── mosquitto/
│   │   └── mosquitto.conf # MQTT config (v2.0+ auth settings)
│   └── prometheus/
│       └── prometheus.yml # Scraping targets (cAdvisor, TeslaMate)
├── data/                 # Persistent storage (auto-generated on start)
│   ├── adguard/
│   ├── grafana/
│   ├── homeassistant/
│   ├── model3/           # Postgres & Import for Model 3
│   ├── modely/           # Postgres & Import for Model Y
│   ├── vaultwarden/
│   └── prometheus/
```

---

## Quickstart Checklist

1. **Docker & Compose**: Ensure they are installed on your Pi.
2. **Network**: Create the proxy network: `docker network create proxy_network`.
3. **Certs**: Generate `cert.pem` and `key.pem` using **mkcert** and place them in `configs/traefik/`.
4. **Environment**: Copy `.env.example` to `.env` and fill in your keys/passwords.
5. **Deploy**: Run `docker compose up -d`.
6. **DNS**: Set DNS rewrites in AdGuard Home (See Step 5).

---

## Step-by-Step Setup

### 1. Prerequisites

- Raspberry Pi (or Linux/ARMv8)
- [Docker + Compose](https://docs.docker.com/engine/install/)
- [mkcert](https://github.com/FiloSottile/mkcert) for easy self-signed certs (install via `brew install mkcert` on macOS, Chocolatey, or download for Linux)
- Git

---

### 2. Prepare the Environment

Run the setup script to initialize folders, set permissions for Grafana/Postgres, and create the internal Docker network:

```sh
chmod +x setup.sh
./setup.sh
```

---

### 3. Generate HTTPS Certificates with mkcert

**On your desktop or Pi (anywhere with mkcert installed):**

```sh
mkcert -install
mkcert -cert-file cert.pem -key-file key.pem \
  traefik.local.lan \
  adguard.local.lan \
  grafana.local.lan \
  teslamate-model3.local.lan \
  teslamate-modely.local.lan \
  homeassistant.local.lan \
  vaultwarden.local.lan \
  prometheus.local.lan \
  cadvisor.local.lan
```

- Copy `cert.pem` and `key.pem` to `configs/traefik/`.
- To avoid browser warnings, [install the mkcert CA](https://github.com/FiloSottile/mkcert#installing-the-root-certificate) on browsers/devices.

---

### 4. Configure & Launch

1. Edit the `.env` file created by the script with your real passwords and encryption keys.
2. Launch the stack: 

```sh
docker compose up -d
```

- All containers will initialize, with data persisted under `data/`.

---

### 5. Create Local DNS rewrites (AdGuard Home)

**In AdGuard Home:**
1. Go to **Filters** → **DNS Rewrites**
2. Add entries:
    ```
    grafana.local.lan           → your Pi/server IP
    adguard.local.lan           → your Pi/server IP
    teslamate-model3.local.lan  → your Pi/server IP
    teslamate-modely.local.lan  → your Pi/server IP
    homeassistant.local.lan     → your Pi/server IP
    vaultwarden.local.lan       → your Pi/server IP 
    traefik.local.lan           → your Pi/server IP
    ```
3. Make sure your LAN devices use AdGuard Home as their DNS server (router DHCP or device settings).

---

### 6. Service Access URLs

On any device using AdGuard Home DNS, browse to:

- **Traefik dashboard:**    `https://traefik.local.lan`
- **AdGuard Home:**         `https://adguard.local.lan`
- **Grafana:**              `https://grafana.local.lan`
- **Home Assistant**        `https://homeassistant.local.lan`
- **Model 3 TeslaMate:**    `https://teslamate-model3.local.lan`
- **Model Y TeslaMate:**    `https://teslamate-modely.local.lan`
- **Vaultwarden**           `https://vaultwarden.local.lan`
- **System Monitor:**       `https://cadvisor.local.lan`

*Note: You may need to accept the certificate as "trusted" on first use if mkcert root isn’t installed.*

---

### 7. Setup Tailscale VPN

1. Run `docker exec -it tailscale tailscale up` to get your login link and Authenticate with that link.
2. Go to Tailscale Admin Console, click on `Add Nameserver` -> `Custom`, enter the Tailscale IP of your device running docker-home.
3. Enable MagicDNS.

---

## Backup Recommendations

- Regularly back up your entire `data/` directory for all databases, Home Assistant configuration, etc.
- Your `configs/`, `.env`, and Compose files are your infrastructure "code base"—safe to back up (suggest a private git repo).

---

## Troubleshooting

- **Can’t access a service?**  
  - Check DNS rewrites in AdGuard Home.
  - Ensure your device is using AdGuard as its DNS.
  - Check Traefik logs: `docker compose logs traefik`
- **Certificate errors?**  
  - Make sure you installed mkcert’s CA on your device.
  - Re-generate certs if you add new subdomains.
- **Data loss after upgrade?**  
  - Make sure volume mounts in Compose match your folders under `/data`.
- **Home Assistant Proxy Blocked?**
  - Add Docker network range to trusted_proxies in HA's configuration.yaml
- **Teslamate shows `Connection Refused,`?**
  - Ensure mosquitto.conf is correctly mapped and allows anonymous connections
- **Port 53 Conflict in Adguard?**
  - Disable systemd-resolved on the Pi or edt its config to stop the stub listener on port 53

---

## Extend/Customize

- Add more services/compose blocks as needed.
- For real domain/Let’s Encrypt, switch acme config in `traefik.yml` (not recommended for local-only use).
- Use `configs/` for version-controlled custom configurations (especially for service config files).

---

## Credits / References

- [TeslaMate](https://github.com/adriankumpf/teslamate)
- [Grafana](https://grafana.com/)
- [AdGuard Home](https://adguard.com/en/adguard-home/overview.html)
- [Home Assistant](https://www.home-assistant.io/)
- [Traefik](https://doc.traefik.io/traefik/)
- [mkcert](https://github.com/FiloSottile/mkcert)

---

## Author
- Built by: **pedroalves80**
