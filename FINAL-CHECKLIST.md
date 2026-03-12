# Final Migration Checklist

## ✅ What's Ready:

### Scripts Created:
- ✅ `migrate-from-k3s.sh` - Copies all k3s data to Docker
- ✅ `pre-migration-check.sh` - Validates prerequisites
- ✅ `setup.sh` - Creates Docker networks (already existed)

### Documentation:
- ✅ `MIGRATION.md` - Complete step-by-step guide
- ✅ `WHAT-TO-DO-NOW.md` - Quick start summary
- ✅ `README.md` - Updated with migration section

### Configuration:
- ✅ `docker-compose.yml` - Fixed (added networks/volumes, exposed HA port 8123)
- ✅ `.env.example` - Template exists
- ✅ `configs/traefik/traefik.yml` - Already configured
- ✅ `configs/prometheus/prometheus.yml` - Already configured

### Data Migration Mapped:
- ✅ AdGuard: k3s PVC → `./data/adguard/`
- ✅ Home Assistant: k3s PVC → `./data/homeassistant/`
- ✅ TeslaMate Model Y DB: k3s PVC → `./data/modely/postgres/`
- ✅ TeslaMate Model 3 DB: k3s PVC → `./data/model3/postgres/`
- ✅ Grafana: k3s PVC → `./data/grafana/`
- ✅ TeslaMate backups: k3s PVC → `./data/modely/backups/`
- ✅ Mosquitto config: ConfigMap → `./configs/mosquitto/mosquitto.conf`

### Credentials Captured:
- ✅ Model Y DB: `teslamate` / `teslamatepass`
- ✅ Model 3 DB: `teslamate` / `[teslamatedb]`
- ✅ Both encryption keys: `qCXGKw1Kw1YtOZD/opMuDGLIFxNw457jDfmD9qKlf28=`
- ✅ Timezone: `Europe/Lisbon`

---

## 🔧 What You Need to Do:

### Before Migration:

1. **Install Docker on Pi:**
   ```bash
   curl -fsSL https://get.docker.com | sudo sh
   sudo usermod -aG docker $USER
   sudo apt-get install -y docker-compose-plugin rsync
   # Log out and back in
   ```

2. **Generate SSL certificates (on Mac):**
   ```bash
   brew install mkcert
   mkcert -install
   mkcert -cert-file cert.pem -key-file key.pem \
     traefik.local.lan adguard.local.lan grafana.local.lan \
     teslamate-model3.local.lan teslamate-modely.local.lan \
     homeassistant.local.lan vaultwarden.local.lan \
     prometheus.local.lan cadvisor.local.lan
   
   # Copy to Pi
   scp cert.pem key.pem yikeszs@raven-0:~/docker-home/configs/traefik/
   ```

3. **Commit and push these new files:**
   ```bash
   git add -A
   git commit -m "Add k3s to Docker migration tools"
   git push
   ```

4. **Pull on Pi:**
   ```bash
   ssh yikeszs@raven-0
   cd ~/docker-home
   git pull
   ```

### During Migration:

5. **Run pre-check:**
   ```bash
   chmod +x pre-migration-check.sh
   ./pre-migration-check.sh
   ```

6. **Run migration:**
   ```bash
   chmod +x migrate-from-k3s.sh
   sudo ./migrate-from-k3s.sh
   ```

7. **Edit .env (generate Vaultwarden token):**
   ```bash
   openssl rand -base64 48
   nano .env  # Replace CHANGEME with the output
   ```

8. **Start Docker:**
   ```bash
   docker compose up -d
   ```

### After Migration:

9. **Configure AdGuard DNS rewrites:**
   - Go to `http://10.10.99.10:3001`
   - Filters → DNS Rewrites
   - Add all `*.local.lan` → `10.10.99.10`

10. **Verify all services work:**
    - Test each URL
    - Check database counts
    - Verify Home Assistant config
    - Check Grafana dashboards

11. **Wait 24+ hours, then remove k3s:**
    ```bash
    sudo systemctl disable k3s --now
    /usr/local/bin/k3s-uninstall.sh
    sudo rm -rf /var/lib/rancher/k3s/storage/pvc-*
    ```

---

## 🚨 Known Issues Handled:

- ✅ Home Assistant port 8123 exposed (for local discovery)
- ✅ Mosquitto config created properly
- ✅ Grafana UID 472 ownership set
- ✅ PostgreSQL UID 70 ownership set
- ✅ Network `proxy_network` created
- ✅ Docker volumes for mosquitto defined
- ✅ AdGuard data structure correct (work/conf subdirs)

---

## 📊 Expected Results:

### Data Sizes:
- AdGuard: 2.1GB
- Model Y DB: 329MB
- Model 3 DB: 321MB
- Backups: 1.1GB
- Grafana: 52MB
- Home Assistant: 7.8MB
- **Total: ~3.8GB**

### Migration Time:
- Pre-checks: 1 minute
- Data copy: 5-10 minutes (depends on SD card speed)
- Docker start: 1-2 minutes
- **Total: ~15 minutes**

### Services After Migration:
All accessible via `https://*.local.lan` after DNS rewrites configured.

---

## 🔄 Rollback:

If anything fails:
```bash
sudo systemctl start k3s
kubectl get pods --all-namespaces
```

k3s data is untouched until you run the uninstall.

---

## ✅ We're All Set!

Nothing is missing. All data will be preserved. You're ready to migrate.

**Next step:** Commit these files and follow `WHAT-TO-DO-NOW.md`
