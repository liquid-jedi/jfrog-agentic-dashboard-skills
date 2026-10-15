# JFrog CISO Report skill — Windows (WSL2) setup guide

Customer-facing prerequisites and install steps for running **jfrog-ciso-report v4.3.0** on Windows through **WSL2**.

This guide assumes GitHub access may be restricted. The skill is installed from the **offline zip bundle** you receive (or download from a machine that can reach GitHub, then transfer).

For native Linux (including how PDF export works), see [Linux customer setup](LINUX-CUSTOMER-SETUP.md).

---

## 1. What this skill needs

| Area | Requirement |
|------|-------------|
| Host OS | Windows 10 (build 19041+) or Windows 11 |
| Runtime | **WSL2** with a Linux distribution |
| JFrog Platform | SaaS or self-hosted |
| JFrog products | **Xray** and **Curation** (both required) |
| Skill package | `jfrog-ciso-report` **v4.3.0** offline zip |

**Not supported**

- Windows native CMD or PowerShell
- Running the runner from Git Bash (untested; use WSL2)
- Relying on Windows-installed tools (`jf`, `node`, Chrome) from inside WSL

Everything below is installed and run **inside the WSL Linux distribution**, not on the Windows host.

---

## 2. Recommended versions

These are the versions we recommend for a reliable install. Newer patch releases in the same major line are fine.

| Component | Recommended | Minimum | Notes |
|-----------|-------------|---------|--------|
| **Windows** | Windows 11, or Windows 10 22H2+ | Windows 10 build 19041 | WSL2 must be available |
| **WSL** | WSL **2** | WSL 2 | WSL 1 is not supported |
| **Linux distro** | **Ubuntu 22.04 LTS** or **24.04 LTS** | Ubuntu 22.04 | Primary tested Linux path for WSL |
| **JFrog CLI (`jf`)** | Latest **2.x** | Any current 2.x that supports your platform | Install from JFrog’s official installer |
| **Python** | **3.11** or **3.12** | **3.10** | Used for collection, transform, and HTML render |
| **Node.js** | **20 LTS** (or **22 LTS**) | **18 LTS** | Used only for PDF export |
| **jq** | **1.6** or **1.7** | 1.6 | JSON helper used by readiness / tooling |
| **PDF browser** | Chromium or Google Chrome (**stable**) inside WSL | Any Chrome/Chromium/Edge Linux build the renderer can launch | Or skip PDFs — see §5 |
| **APM** (optional) | Latest stable | — | Preferred installer when available on the machine |
| **Skill bundle** | **jfrog-ciso-report v4.3.0** | v4.3.0 | File name: `jfrog-ciso-report-v4.3.0.zip` |

### Version checks (run inside WSL)

```bash
wsl.exe -l -v                    # from Windows PowerShell: VERSION column must be 2
uname -a
jf --version
python3 --version                # expect Python 3.10+
node --version                   # expect v18+ (v20 recommended)
jq --version
command -v chromium-browser || command -v chromium || command -v google-chrome
```

---

## 3. One-time Windows / WSL prep

From **PowerShell (Admin)** on Windows:

```powershell
wsl --install
# If Ubuntu is already installed, ensure it is WSL2:
wsl --set-version Ubuntu 2
wsl -l -v
```

Then open **Ubuntu** (or your chosen distro) and continue all remaining steps in that Linux shell.

---

## 4. Install runtime tools inside WSL

### 4.1 System packages

```bash
sudo apt-get update
sudo apt-get install -y \
  ca-certificates curl unzip \
  python3 python3-venv \
  jq \
  nodejs npm
```

If `nodejs` from apt is older than **v18**, install Node 20 LTS from NodeSource or your approved internal mirror, for example:

```bash
# Example only — use your organisation’s approved Node 20 install method when air-gapped
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
node --version   # should report v20.x
```

### 4.2 JFrog CLI

```bash
curl -fL https://install-cli.jfrog.io | sh
# ensure ~/.local/bin (or the installer’s bin dir) is on PATH
jf --version
jf config add
jf config show
```

On an air-gapped host, transfer the Linux JFrog CLI binary from an approved internal source and place it on `PATH`.

### 4.3 Confirm JFrog access

The configured user/token must be able to read:

- Artifactory repository metadata
- Xray watches, policies, indexed repos, violations
- Curation policies and package-gate audit events

---

## 5. PDF export on WSL (important)

PDF rendering runs as **Linux Node** and opens a `file:///home/...` path.

### Do not use Windows Chrome

Do **not** set:

```bash
export CISO_CHROME_BIN="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
```

A Windows browser may launch but will not correctly resolve Linux paths or write the PDF back into the WSL filesystem.

### Option A — Linux browser in WSL (full HTML + PDF)

```bash
sudo apt-get install -y chromium-browser
# On some Ubuntu releases the package name is:
# sudo apt-get install -y chromium

command -v chromium-browser || command -v chromium
# optional explicit pin:
# export CISO_CHROME_BIN="$(command -v chromium-browser || command -v chromium)"
```

Headless PDF generation does **not** require a desktop or X server.

### Option B — HTML only (no browser)

Supported in **v4.3.0**:

```bash
export CISO_PDF_MODE=none
```

The run still produces `report.html`, the active-user CSV, snapshot, and run metadata. No `node`/browser preflight is required in this mode.

**Opening the report:** `report.html` is a single self-contained file. Copy it (or zip the output folder) to a workstation that has a browser and open it there. There is nothing to view on a WSL/Linux host that has no browser. Same transfer path as native Linux — see [Linux customer setup §6](LINUX-CUSTOMER-SETUP.md#6-linux-machine-with-no-browser-locked-down--headless--jump-host).

---

## 6. Install the skill from the offline zip (recommended when GitHub is restricted)

The installable artifact is:

```text
jfrog-ciso-report-v4.3.0.zip          (~650 KB)
```

**Use this file.** Do **not** use GitHub’s auto-generated “Source code (zip)” / “Source code (tar.gz)” archives. Those contain the whole repository and will not install with the commands below.

### How the customer receives the zip

1. Your JFrog contact provides `jfrog-ciso-report-v4.3.0.zip`, **or**
2. Someone with GitHub access downloads it from the release **Assets**, then transfers it by email, shared drive, USB, or internal artifact repository.

### Install inside WSL

```bash
# 1. Copy the zip into WSL (example: from Windows Downloads)
mkdir -p ~/ciso-reporting && cd ~/ciso-reporting
cp /mnt/c/Users/<windows-user>/Downloads/jfrog-ciso-report-v4.3.0.zip .

# 2. Unpack
unzip jfrog-ciso-report-v4.3.0.zip
# expect a folder named: jfrog-ciso-report/

# 3. Install with APM (preferred when APM is available)
curl -sSL https://aka.ms/apm-unix | sh          # skip if APM already installed / air-gapped
apm --version
mkdir -p ~/ciso-reporting && cd ~/ciso-reporting
apm init -y --target claude,codex,cursor
apm install ./jfrog-ciso-report --target claude,cursor,codex
```

If APM cannot be used in your environment, place the unpacked skill where your agent loads skills from (Claude Code / Cursor / Codex skill directories), preserving this layout:

```text
jfrog-ciso-report/
├── apm.yml
├── README.md
├── .apm/skills/jfrog-ciso-report/
│   ├── SKILL.md
│   ├── bin/generate-ciso-report.sh
│   ├── bin/generate-ciso-pdf.js
│   └── references/...
└── extras/agent-support/          # optional guardrail hooks
```

The zip is self-contained for the skill (runner, HTML/PDF templates, schema). It does **not** include `jf`, Python, Node, jq, or a browser — those remain host prerequisites (§4–§5).

---

## 7. Output location

Write reports under the **Linux home**, for example:

```bash
mkdir -p ~/ciso-reports
```

Prefer `~/ciso-reports` over `/mnt/c/...` for performance and fewer path issues.

---

## 8. Readiness checklist

Run inside WSL before the first report:

```bash
echo "=== WSL / tools ==="
jf --version && jf config show
python3 --version
node --version
jq --version

echo "=== PDF path ==="
if [[ "${CISO_PDF_MODE:-executive}" == "none" ]]; then
  echo "HTML-only mode configured (CISO_PDF_MODE=none)"
else
  command -v chromium-browser || command -v chromium || command -v google-chrome || \
    echo "ERROR: no Linux browser found — install Chromium or set CISO_PDF_MODE=none"
  # If the skill is installed via Claude skills path:
  # node ~/.claude/skills/jfrog-ciso-report/bin/generate-ciso-pdf.js --check
fi

echo "=== Skill bundle ==="
test -f ~/ciso-reporting/jfrog-ciso-report/apm.yml && \
  echo "Unpacked skill found" || echo "Place/install jfrog-ciso-report-v4.3.0.zip first"
```

---

## 9. First run (example)

Ask your agent (from a session that can see the installed skill):

```text
Generate a weekly CISO report for server <server-id>.
Save under ~/ciso-reports.
Use executive PDF.
```

Or HTML only on a locked-down WSL image:

```text
Generate a weekly CISO report for server <server-id>.
Save under ~/ciso-reports.
HTML only (no PDF).
```

Equivalent environment for a direct runner invocation:

```bash
# Full run with PDF
CISO_PDF_MODE=executive \
  ~/.claude/skills/jfrog-ciso-report/bin/generate-ciso-report.sh \
  <server-id> ~/ciso-reports weekly

# HTML only
CISO_PDF_MODE=none \
  ~/.claude/skills/jfrog-ciso-report/bin/generate-ciso-report.sh \
  <server-id> ~/ciso-reports weekly
```

---

## 10. Common WSL issues

| Symptom | Cause | Fix |
|---------|--------|-----|
| `jf` / `node` / `python3` not found | Tools installed on Windows host only | Install them inside WSL |
| `No PDF browser found` | No Linux Chrome/Chromium, or Windows Chrome via `/mnt/c` | Install Chromium in WSL, or set `CISO_PDF_MODE=none` |
| PDF missing / tiny file | Browser cannot render the Linux `file://` input | Use a Linux browser path, not `chrome.exe` |
| Skill install fails on “Source code” zip | Wrong GitHub asset | Use `jfrog-ciso-report-v4.3.0.zip` only |
| Slow runs writing to `/mnt/c/...` | Cross-filesystem I/O | Save under `~/ciso-reports` |

---

## 11. What we need from you (customer checklist)

Please confirm before kickoff:

1. WSL2 + Ubuntu 22.04/24.04 available  
2. Access to your JFrog Platform with Xray + Curation  
3. Ability to install (or receive binaries for) `jf`, Python 3.10+, Node 18+/20, jq  
4. Either Linux Chromium **or** agreement to run with `CISO_PDF_MODE=none`  
5. Receipt of **`jfrog-ciso-report-v4.3.0.zip`** (~650 KB)

---

## Related references

- Skill version: **jfrog-ciso-report v4.3.0**
- Offline bundle name: **`jfrog-ciso-report-v4.3.0.zip`**
- Interpreting the finished report: `docs/INTERPRETING-THE-REPORT.md`
- General install options (including online APM): `docs/INSTALL.md`

---

*Document version: aligned with jfrog-ciso-report v4.3.0 · Audience: customer IT / platform engineering preparing a WSL2 workstation*
