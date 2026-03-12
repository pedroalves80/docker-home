# What to Do Now - Quick Summary

## Files Created for You

I've created these files in your repo:

1. **`migrate-from-k3s.sh`** - Main migration script
2. **`pre-migration-check.sh`** - Validates prerequisites before migrating
3. **`MIGRATION.md`** - Complete step-by-step migration guide
4. **Updated `README.md`** - Now includes migration section
5. **Fixed `docker-compose.yml`** - Added missing network/volume definitions

---

## Next Steps on Your Raspberry Pi

### 1. Push the new files to your repo (from your Mac):

```bash
cd ~/Projects/personal/docker-home
git add .
git commit -m "Add k3s to Docker migration scripts"
git push
```

### 2. Pull the changes on your Pi:

```bash
ssh yikeszs@raven-0  # or your Pi's hostname/IP
cd ~/docker-home
git pull
```

**OR if the repo isn't cloned yet:**

```bash
ssh yikeszs@raven-0
cd ~
git clone <your-repo-url> docker-home
cd docker-home
```

---

### 3. Install Docker (if not already installed):

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
sudo apt-get install -y docker-compose-plugin rsync

# Log out and back in for group changes
exit
ssh yikeszs@raven-0
```

---

### 4. Generate SSL certificates (on your Mac, not Pi):

```bash
# Install mkcert
brew install mkcert
mkcert -install

# Generate certs
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

# Copy to Pi
scp cert.pem key.pem yikeszs@raven-0:~/docker-home/configs/traefik/
```

---

### 5. Run pre-migration checks on Pi:

```bash
cd ~/docker-home
chmod +x pre-migration-check.sh
./pre-migration-check.sh
```

**Fix any issues it reports**, then continue.

---

### 6. Run the migration:

```bash
cd ~/docker-home
chmod +x migrate-from-k3s.sh
sudo ./migrate-from-k3s.sh
```

This will:
- Stop k3s
- Copy ~3.8GB of data (takes ~5-10 minutes)
- Create `.env` with your k3s passwords
- Set proper permissions

---

### 7. Edit `.env` file:

```bash
nano .env
```

**Generate a Vaultwarden admin token:**

```bash
openssl rand -base64 48
```

Replace `CHANGEME_GENERATE_WITH_openssl_rand_base64_48` with the output.

---

### 8. Create Docker network and start the stack:

```bash
docker network create proxy_network
docker compose up -d
```

---

### 9. Verify everything works:

```bash
# Check all containers are running
docker compose ps

# Should show all services "Up"
```

**Test URLs** (from any device using AdGuard DNS):
- https://traefik.local.lan
- https://adguard.local.lan
- https://grafana.local.lan
- https://teslamate-modely.local.lan
- https://teslamate-model3.local.lan
- https://homeassistant.local.lan
- https://vaultwarden.local.lan

---

### 10. Verify databases migrated correctly:

```bash
# Check TeslaMate Model Y
docker exec teslamate_modely_db psql -U teslamate -d teslamate_modely -c "SELECT COUNT(*) FROM drives;"

# Check TeslaMate Model 3
docker exec teslamate_model3_db psql -U teslamate -d teslamate_model3 -c "SELECT COUNT(*) FROM drives;"
```

Should show your drive counts from k3s.

---

### 11. ONLY AFTER 24+ hours of verified operation - Remove k3s:

```bash
sudo systemctl disable k3s --now
/usr/local/bin/k3s-uninstall.sh

# (Optional) Clean up old data
sudo rm -rf /var/lib/rancher/k3s/storage/pvc-*
```

---

## Rollback Plan

If something goes wrong, you can restart k3s:

```bash
sudo systemctl start k3s
kubectl get pods --all-namespaces
```

Your k3s data is untouched until you run the uninstall in step 11.

---

## Your k3s Credentials (Captured)

These are already in the migration script:

- **Model Y DB:** User: `teslamate`, Pass: `teslamatepass`
- **Model 3 DB:** User: `teslamate`, Pass: `[teslamatedb]`
- **Both TeslaMate encryption keys:** `qCXGKw1Kw1YtOZD/opMuDGLIFxNw457jDfmD9qKlf28=`
- **Timezone:** `Europe/Lisbon`

---

## Data Migration Map

| k3s PVC | Size | Docker Location |
|---------|------|-----------------|
| adguard-storage | 2.1GB | `./data/adguard/` |
| home-assistant-config | 7.8MB | `./data/homeassistant/` |
| teslamate-db (Model Y) | 329MB | `./data/modely/postgres/` |
| m3-postgres-db (Model 3) | 321MB | `./data/model3/postgres/` |
| grafana-storage | 52MB | `./data/grafana/` |
| teslamate-backup | 1.1GB | `./data/modely/backups/` |

---

## Support

If you hit issues:
- Check `MIGRATION.md` for troubleshooting section
- Review Docker logs: `docker compose logs <service>`
- Verify permissions: `sudo chown -R 472:472 data/grafana`

Ready to migrate? Start with step 1 above!
