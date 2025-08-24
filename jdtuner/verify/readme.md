New bundle:

```
/home/divyamohan1993/instance-20250731-114417.us-east1-b.c.dmjone.internal_oneclick_20250824_084804.tgz
```

has:

* correct `APP_DIR` (`/home/divyamohan1993/...`) ✔
* offline wheelhouse captured ✔
* nginx, letsencrypt, systemd, crons, firewall, home snapshot ✔
* no “file changed as we read it” warning ✔

## Before you delete the VM (2-minute checklist)

1. **Hash + copy off-box**

```bash
B=~/instance-*_oneclick_20250824_084804.tgz
sha256sum "$B" | tee "$B.sha256"
# copy both files anywhere safe
```

2. **(Optional but smart) Encrypt at rest**

```bash
gpg --symmetric --cipher-algo AES256 "$B"
# produces ...tgz.gpg (use a strong passphrase)
```

3. **Sanity peek inside**

```bash
T=$(mktemp -d); tar -xzf "$B" -C "$T"
ls -1 "$T/payload" | sed -n '1,50p'
```

---

## One-click **restore dress rehearsal** (fresh throwaway VM)

> Use the **same username** (`divyamohan1993`) for zero friction. If not, pass `APP_DIR` and the service will run as the invoking user.

```bash
# copy bundle + oneclick.sh to new VM
sudo SERVICE=airesume \
     DOMAIN=jdtuning.dmj.one \
     APP_PORT=8000 \
     APP_DIR=/home/divyamohan1993/AI-Resume-Optimizer/AI_Resume_Optimizer \
     bash oneclick.sh restore /path/to/instance-..._084804.tgz
```

### Quick smoke tests

```bash
systemctl is-active airesume                      # active
ss -ltnp | grep :8000                             # listening
curl -I http://127.0.0.1:8000                     # 200/301
sudo nginx -t                                     # syntax OK
curl -I -H "Host: jdtuning.dmj.one" http://127.0.0.1
sudo ufw status
journalctl -u airesume -n 100 --no-pager          # no errors
```

### TLS note

* If `/etc/letsencrypt` restored: you’re good.
* If not (or domain isn’t pointing yet): cert issuance will be skipped/failed harmlessly; point DNS → rerun:

```bash
sudo certbot --nginx -d jdtuning.dmj.one --redirect -m contact@dmj.one --agree-tos -n
```

---

## If the new VM user is different

Either create the same user:

```bash
sudo adduser --disabled-password --gecos "" divyamohan1993
sudo usermod -aG sudo divyamohan1993
su - divyamohan1993
```

…or just override:

```bash
sudo APP_DIR=/home/<newuser>/AI-Resume-Optimizer/AI_Resume_Optimizer \
     SERVICE=airesume APP_PORT=8000 \
     bash oneclick.sh restore /path/to/bundle.tgz
```

---

## Green-light to nuke 💣

Once the dress rehearsal passes, you can safely delete the old VM.
(If you ever rotate secrets later, just drop the new `.env`/key in place and `sudo systemctl restart airesume`.)
