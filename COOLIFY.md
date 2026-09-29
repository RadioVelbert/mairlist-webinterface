# 🐳 Setup-Guide — Coolify (Docker)

Schritt-für-Schritt-Anleitung, um das Webinterface als Docker-Container unter [Coolify](https://coolify.io) zu betreiben. Für den klassischen Betrieb direkt auf dem Windows Server siehe [`DEPLOYMENT.md`](DEPLOYMENT.md).

## So hängt alles zusammen

```
Browser ──► Coolify (Traefik) ──► Container "mairlist-webinterface" (:8841)
                                        │  HTTPS, gepinntes Zertifikat
                                        ▼
                             mAirListDB Server (SSLPort, Standard 9840)
                                        │
                                        ▼
                             Datenbank (PostgreSQL, SQLite, ...)
```

- Das `Dockerfile` im Repo-Root baut Frontend und Server in ein Image.
- Der Container läuft im **api-Modus** (`DATA_SOURCE=api`): Er spricht nur per HTTPS mit dem mAirListDB Server, inklusive Audio-Streaming und Upload. Welche Datenbank dahinter liegt, spielt keine Rolle.
- Der sqlite-Modus ist für Coolify ungeeignet — er öffnet eine `.mldb`-Datei direkt und funktioniert weder mit einem PostgreSQL-Backend noch sicher über eine Netzwerkfreigabe.
- Benutzer und Einstellungen des Webinterfaces liegen in einem persistenten Volume unter `/data`.
- **Alles Installationsspezifische** — Adresse und Port des mAirListDB Servers, sein Zertifikat, Zugangsdaten — steht ausschließlich in den Umgebungsvariablen in Coolify, nicht im Repo.

## Kurzfassung

1. GitHub App in Coolify anlegen und für dieses Repo freigeben
2. Ressource anlegen: Build Pack `Dockerfile`, Ports Exposes `8841`
3. Erreichbarkeit festlegen: Domain **oder** Port-Mapping
4. Volume Mount nach `/data`
5. Umgebungsvariablen setzen, inklusive Zertifikat des mAirListDB Servers
6. Deployen und prüfen

---

## Voraussetzungen

Der Coolify-Host muss den mAirListDB Server erreichen. Test auf dem Coolify-Host:

```bash
curl -kI https://<MAIRLIST-IP>:<SSLPort>/
```

Jede HTTP-Antwort (auch 401/404) heißt: Die Verbindung steht. Ein Timeout heißt: Firewall oder Routing. `-k` prüft hier nur die Erreichbarkeit, um das Zertifikat kümmert sich das Webinterface selbst (siehe [TLS-Zertifikat](#-tls-zertifikat-des-mairlistdb-servers)). Der Port steht als `SSLPort` in der `dbserver.ini` des mAirListDB Servers (Standard 9840).

Falls die Windows-Firewall auf dem mAirListDB Server blockiert:

```powershell
New-NetFirewallRule -DisplayName "mAirListDB Server (Coolify)" -Direction Inbound -LocalPort <SSLPort> -Protocol TCP -RemoteAddress <COOLIFY-IP> -Action Allow
```

## 1. GitHub anbinden (einmalig)

1. In Coolify **Sources → + Add → GitHub App**, Namen vergeben, **Register now**.
2. Auf GitHub die App anlegen und auf der Organisation bzw. dem Account installieren, dem das Repo gehört (hier die Organisation `RadioVelbert`). Dafür sind Admin-Rechte dort nötig.
3. Als Zugriff nur das Repo `mairlist-webinterface` auswählen.

> **Auto-Deploy bei Push** funktioniert nur, wenn GitHub die Coolify-Instanz aus dem Internet erreicht (Webhook). Ist Coolify nur im LAN erreichbar, nach jedem Push in Coolify auf **Deploy** klicken. Für echtes Auto-Deploy entweder nur den Webhook-Pfad per Tunnel (z.B. Cloudflare Tunnel) freigeben oder einen self-hosted GitHub Actions Runner im LAN die Deploy-API von Coolify aufrufen lassen.

## 2. Ressource anlegen

1. Projekt öffnen, **+ New → Private Repository (with GitHub App)**
2. App, Repo `mairlist-webinterface` und Branch `main` wählen
3. **Build Pack:** `Dockerfile`
4. **Base Directory:** `/` (Dockerfile Location `/Dockerfile`)
5. **Ports Exposes:** `8841`

**Health Check** in Coolify ausgeschaltet lassen: Coolifys eigener Check ruft `curl`/`wget` im Container auf, die das schlanke Image nicht enthält. Das Dockerfile bringt einen eigenen `HEALTHCHECK` auf `/api/health` mit.

## 3. Erreichbarkeit festlegen

| | **A: über einen Namen** | **B: direkt über IP und Port** |
|---|---|---|
| Beispiel | `http://mairlist.intern.lan` | `http://<COOLIFY-IP>:8841` |
| Voraussetzung | interner DNS-Eintrag, der auf den Coolify-Host zeigt | keine |
| Feld **Domains** | `http://mairlist.intern.lan` | leer lassen |
| Feld **Ports Mappings** | leer | `8841:8841` |
| Zusätzliche Variable | – | `TRUST_PROXY=false` |

Ohne internen DNS ist **B** der schnellste Weg. Eine von Coolify vorgeschlagene `…sslip.io`-Domain funktioniert im LAN nur, wenn der Router DNS-Antworten mit privaten IPs nicht blockiert (FritzBoxen tun das standardmäßig) — im Zweifel löschen.

## 4. Persistenter Speicher

**Storages → + Add → Volume Mount**, Destination Path `/data`.

Dort liegen die Benutzerverwaltung (`webinterface-auth.db`) und die Panel-Einstellungen (`settings.json`). Ohne Volume sind beide nach jedem Deploy weg.

> Einen **Volume Mount** verwenden, keinen Directory Mount: Der Container läuft als Benutzer `node` (UID 1000) und kann in einen root-eigenen Host-Ordner nicht schreiben. Bei einem Directory Mount auf dem Host `chown 1000:1000 <ordner>` ausführen.

## 5. Umgebungsvariablen

Unter **Environment Variables** auf die Textansicht (Developer view) umschalten und einfügen:

```
API_DB_BASE_URL=https://<MAIRLIST-IP>:<SSLPort>
API_DB_USER=<mAirList-Benutzer>
API_DB_PASSWORD=<Passwort dieses Benutzers>
API_DB_STATION=1
ALLOWED_ORIGINS=<genau die Adresse aus Schritt 3>
COOKIE_SECURE=false
INITIAL_ADMIN_PASSWORD=<Startpasswort für den Webinterface-Admin>
```

Bei **Variante B** zusätzlich `TRUST_PROXY=false`.

Dazu kommt **`API_DB_TLS_CERT`** mit dem Zertifikat des mAirListDB Servers — siehe [TLS-Zertifikat](#-tls-zertifikat-des-mairlistdb-servers), am einfachsten als einzeilige Variable.

| Variable | Worauf achten |
|---|---|
| `API_DB_BASE_URL` | Adresse und TLS-Port (`SSLPort`) des mAirListDB Servers |
| `API_DB_TLS_CERT` | Zertifikat des mAirListDB Servers: Inhalt der `.cer` oder Pfad zu einer Datei im Container |
| `API_DB_USER`, `API_DB_PASSWORD` | Ein normales mAirList-Benutzerkonto, das Items und Playlists lesen und schreiben darf. Am besten ein eigenes Konto nur für das Webinterface |
| `API_DB_STATION` | Station-ID, meist `1` |
| `ALLOWED_ORIGINS` | Exakt die Adresse im Browser, inklusive `http://` und ggf. Port, **ohne** `/` am Ende. Passt sie nicht, schlägt jedes Speichern fehl |
| `COOKIE_SECURE` | `false`, solange das Webinterface über `http://` läuft. `true` nur bei HTTPS, sonst klappt der Login nicht |
| `INITIAL_ADMIN_PASSWORD` | Passwort für den Benutzer `admin`, wird nur beim allerersten Start gelesen |
| `API_DB_MAX_CONCURRENT` | optional, Default `3` — maximal parallele Anfragen an den mAirListDB Server |

**Passwörter nur zur Laufzeit:** Bei `API_DB_PASSWORD` und `INITIAL_ADMIN_PASSWORD` das Häkchen für Build-Zeit entfernen (je nach Coolify-Version „Build Variable?“ bzw. „Available at Buildtime“). Der Build braucht sie nicht.

**Bereits im Image gesetzt** — nicht eintragen, außer man will bewusst abweichen:

| Variable | Wert | Bedeutung |
|---|---|---|
| `PORT` | `8841` | Port im Container, muss zu **Ports Exposes** passen |
| `DATA_SOURCE` | `api` | über den mAirListDB Server statt direkt auf eine `.mldb` |
| `WEB_AUTH_DB_PATH` | `/data/webinterface-auth.db` | Benutzerverwaltung auf dem Volume |
| `SETTINGS_PATH` | `/data/settings.json` | Panel-Einstellungen auf dem Volume |
| `TRUST_PROXY` | `1` | genau ein Reverse Proxy (Coolifys Traefik) davor, damit die Login-Sperre die echte Client-IP sieht statt der des Proxys |

**Nicht setzen:**
- `DB_PATH`, `AUDIO_BASE_DIR`, `UPLOAD_BASE_DIR` — gehören zum sqlite-Modus des Windows-Betriebs
- `NODE_TLS_REJECT_UNAUTHORIZED` — schaltet die Zertifikatsprüfung für *alle* Verbindungen ab

## 6. Deployen und prüfen

1. **Deploy** klicken und das Build-Log verfolgen. Der erste Build dauert ein paar Minuten.
2. Unter **Logs** sollte beim Start stehen:
   ```
   mAirListDB Server TLS: gepinntes Zertifikat aus Inhalt von API_DB_TLS_CERT, gültig bis <Datum>
   Web Auth DB: /data/webinterface-auth.db
   Data source: api
   Trust proxy: 1        (bei Variante B: aus)
   ```
3. Im Browser `<Adresse>/api/health` aufrufen — erwartet: `{"status":"ok","dataSource":"api"}`. Das prüft nur den Container selbst.
4. Verbindung zu mAirList prüfen: im **Terminal** der Ressource
   ```bash
   node scripts/smoke-reads-api.js
   ```
   ausführen. Das Skript nutzt die gesetzten Umgebungsvariablen und liest nur. Einzelne 404 bei fest eingetragenen Test-IDs (z.B. `SMOKE_ITEM_ID=2605`) sind harmlos.
5. Mit `admin` und dem `INITIAL_ADMIN_PASSWORD` einloggen und unter **Administration → Benutzer** die Konten fürs Team anlegen. Danach kann `INITIAL_ADMIN_PASSWORD` aus Coolify gelöscht werden.

## Updates

Auf `main` pushen, dann in Coolify **Deploy** klicken (oder automatisch per Webhook, siehe [Schritt 1](#1-github-anbinden-einmalig)). Benutzer und Einstellungen bleiben dank des `/data`-Volumes erhalten.

---

## 🔒 TLS-Zertifikat des mAirListDB Servers

Der mAirListDB Server nutzt auf seinem TLS-Port üblicherweise ein **selbstsigniertes** Zertifikat, das die IP nur als CN trägt. Node akzeptiert IP-Adressen aber nur über einen `subjectAltName`-Eintrag — ein normales „Vertrauen“ per `NODE_EXTRA_CA_CERTS` scheitert deshalb mit `ERR_TLS_CERT_ALTNAME_INVALID`.

Stattdessen wird das Zertifikat **gepinnt** (`API_DB_TLS_CERT`, siehe [`server/data/apiClient.js`](server/data/apiClient.js)):

- Für Verbindungen zum mAirListDB Server wird **ausschließlich genau dieses Zertifikat** akzeptiert, jedes andere abgelehnt.
- Die Hostname-Prüfung entfällt dabei — sie brächte nichts zusätzlich, weil ohnehin nur der Server mit dem passenden Schlüssel durchkommt.
- Alle anderen Verbindungen (z.B. Hörerzahlen von laut.fm) behalten die normale Zertifikatsprüfung.

Stammt das Zertifikat stattdessen von einer öffentlichen CA (z.B. Let's Encrypt), `API_DB_TLS_CERT` einfach weglassen.

### Zertifikat hinterlegen

Das Zertifikat ist die Datei aus `SSLCertificateFile` in der `dbserver.ini` des mAirListDB Servers — **nur das Zertifikat, niemals die `SSLKeyFile`**. Es gehört nicht ins Repo (`server/certs/` ist in `.gitignore` ausgeschlossen), sondern in Coolify.

**Empfohlen: als einzeilige Umgebungsvariable.** Den Inhalt der `.cer` in eine Zeile bringen:

```powershell
# Windows (PowerShell), auf dem mAirListDB Server oder wo die .cer liegt
(Get-Content .\<Datei>.cer) -join ''
```

```bash
# Linux, z.B. auf dem Coolify-Host
tr -d '\r\n' < <Datei>.cer
```

Die Ausgabe (`-----BEGIN CERTIFICATE-----MIID…-----END CERTIFICATE-----`) in Coolify als Wert von `API_DB_TLS_CERT` eintragen. Zeilenumbrüche sind egal — auch ein mehrzeilig eingefügter Wert (in Coolify ggf. „Is Multiline?“ anhaken) oder einer mit wörtlichen `\n` funktioniert.

Beginnt die `.cer` nicht mit `-----BEGIN CERTIFICATE-----`, ist sie binär (DER). Dann vorher umwandeln: `openssl x509 -inform DER -in <Datei>.cer`.

**Alternative: als Datei.** Unter **Storages → + Add → File Mount** eine Datei z.B. nach `/certs/mairlist-db.cer` mit dem Inhalt der `.cer` anlegen und `API_DB_TLS_CERT=/certs/mairlist-db.cer` setzen. Als Datei funktionieren PEM und DER.

### Zertifikat erneuern

Selbstsignierte Zertifikate laufen ab — das Ablaufdatum steht beim Start im Log. Bekommt der mAirListDB Server ein neues Zertifikat, den Wert von `API_DB_TLS_CERT` in Coolify ersetzen und neu deployen. Ein Commit ist dafür nicht nötig.

Alternativ lässt sich das aktuelle Zertifikat vom Coolify-Host abrufen:

```bash
openssl s_client -connect <MAIRLIST-IP>:<SSLPort> </dev/null 2>/dev/null | openssl x509 | tr -d '\n'
```

Zum Abgleich mit der `.cer` auf dem Server den Fingerabdruck vergleichen (Windows: Doppelklick auf die `.cer` → **Details → Fingerabdruck**):

```bash
openssl x509 -in <Datei>.cer -noout -fingerprint -sha1
```

Zeigt `API_DB_TLS_CERT` auf einen Schlüssel oder enthält etwas anderes als ein Zertifikat, bricht der Server beim Start mit einer klaren Meldung ab.

---

## 🩺 Fehlerbehebung

| Symptom (Log oder Browser) | Ursache |
|---|---|
| `API_DB_TLS_CERT: kein lesbares Zertifikat (Inhalt von API_DB_TLS_CERT: …)` | Wert unvollständig kopiert, oder Coolify hat einen mehrzeiligen Wert abgeschnitten — als eine Zeile eintragen |
| `API_DB_TLS_CERT: kein lesbares Zertifikat (/…: ENOENT)` | Pfad zur Datei falsch (Groß-/Kleinschreibung!) oder File Mount fehlt |
| `DEPTH_ZERO_SELF_SIGNED_CERT` | `API_DB_TLS_CERT` fehlt, oder der Server hat inzwischen ein neues Zertifikat |
| `ERR_TLS_CERT_ALTNAME_INVALID` | `NODE_EXTRA_CA_CERTS` statt `API_DB_TLS_CERT` verwendet |
| `403 Access denied` / `401` | `API_DB_USER` oder `API_DB_PASSWORD` falsch |
| `mAirListDB Server nicht erreichbar` mit Timeout | Netzwerk/Firewall zwischen Container und mAirListDB Server |
| Speichern schlägt fehl, `CORS: Origin nicht erlaubt` | `ALLOWED_ORIGINS` passt nicht exakt zur Adresse im Browser |
| Login „springt zurück“ | `COOKIE_SECURE=true` bei `http://` |
| Benutzer nach Deploy weg | Volume `/data` fehlt |
| `Bad Gateway` / 404 von Coolify | **Ports Exposes** ist nicht `8841` |
| Nach 5 Fehlversuchen können sich alle nicht mehr einloggen | `TRUST_PROXY` fehlt hinter Traefik (Variante A) |
| `database is locked` im Log | mAirListDB Server überlastet, ggf. `API_DB_MAX_CONCURRENT` senken |
