# JFrog CISO Report skill — Linux setup guide

Customer-facing prerequisites and install steps for running **jfrog-ciso-report v4.3.0** on a **native Linux** workstation or VM.

This guide assumes GitHub access may be restricted. The skill is installed from the **offline zip bundle** you receive (or download from a machine that can reach GitHub, then transfer).

For Windows through WSL2, see [WSL2 Windows customer setup](WSL2-WINDOWS-CUSTOMER-SETUP.md). PDF behaviour is the same on both platforms; this guide explains it in §5–§7.

**UI-less / headless Linux:** you do **not** need a desktop, X server, or a window. If the customer wants **PDF**, install **Chromium (or Puppeteer)** on that same host — it runs headless. Opening the finished PDF still happens on a laptop (copy the file). See §6.

---

## 1. What this skill needs

| Area | Requirement |
|------|-------------|
| Host OS | Linux (x86_64). Primary path: **Ubuntu 22.04 / 24.04 LTS**. RHEL 8/9 family also works with equivalent packages |
| JFrog Platform | SaaS or self-hosted |
| JFrog products | **Xray** and **Curation** (both required) |
| Skill package | `jfrog-ciso-report` **v4.3.0** offline zip |

Everything in this guide runs on the Linux host itself. No Windows / WSL layer is involved.

---

## 2. Recommended versions

| Component | Recommended | Minimum | Notes |
|-----------|-------------|---------|--------|
| **Linux distro** | **Ubuntu 22.04 LTS** or **24.04 LTS** | Ubuntu 22.04, or RHEL 8/9 equivalent | Bash + standard userland |
| **JFrog CLI (`jf`)** | Latest **2.x** | Current 2.x for your platform | Official JFrog installer or internal mirror |
| **Python** | **3.11** or **3.12** | **3.10** | Collection, transform, HTML render |
| **Node.js** | **20 LTS** (or **22 LTS**) | **18 LTS** | Required for PDF export |
| **jq** | **1.6** or **1.7** | 1.6 | Readiness / JSON helpers |
| **PDF engine** | **Chromium** (or Google Chrome) **stable**, *or* **Puppeteer** | Headless Linux build the renderer can launch | **Required if the customer wants PDF.** No desktop/GUI needed. See §6 |
| **APM** (optional) | Latest stable | — | Preferred installer when available |
| **Skill bundle** | **jfrog-ciso-report v4.3.0** | v4.3.0 | File: `jfrog-ciso-report-v4.3.0.zip` |

### Version checks

```bash
uname -a
jf --version
python3 --version        # expect Python 3.10+
node --version           # expect v18+ (v20 recommended)
jq --version
command -v chromium-browser || command -v chromium || command -v google-chrome || command -v google-chrome-stable
```

---

## 3. Install runtime tools

### 3.1 Ubuntu / Debian

```bash
sudo apt-get update
sudo apt-get install -y \
  ca-certificates curl unzip \
  python3 python3-venv \
  jq \
  nodejs npm
```

If apt’s `nodejs` is older than **v18**, install Node **20 LTS** from NodeSource or your approved internal mirror:

```bash
# Example only — use your organisation’s approved Node 20 method when air-gapped
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
node --version   # should report v20.x
```

### 3.2 RHEL / Rocky / Alma (outline)

```bash
sudo dnf install -y ca-certificates curl unzip python3 jq nodejs
# Install Chromium / Chrome from your approved repo when PDF export is required
```

### 3.3 JFrog CLI

```bash
curl -fL https://install-cli.jfrog.io | sh
# ensure the installer’s bin dir is on PATH (often ~/.local/bin)
jf --version
jf config add
jf config show
```

On an air-gapped host, transfer the Linux `jf` binary from an approved internal source and place it on `PATH`.

### 3.4 Confirm JFrog access

The configured user/token must be able to read:

- Artifactory repository metadata  
- Xray watches, policies, indexed repos, violations  
- Curation policies and package-gate audit events  

---

## 4. Install the skill from the offline zip

The installable artifact is:

```text
jfrog-ciso-report-v4.3.0.zip          (~650 KB)
```

**Use this file.** Do **not** use GitHub’s auto-generated “Source code (zip)” / “Source code (tar.gz)” archives — those contain the whole repository and will not install with the commands below.

### How the customer receives the zip

1. Your JFrog contact provides `jfrog-ciso-report-v4.3.0.zip`, **or**  
2. Someone with GitHub access downloads it from the release **Assets**, then transfers it by email, shared drive, USB, or internal artifact repository.

### Install

```bash
mkdir -p ~/ciso-reporting && cd ~/ciso-reporting

# place the zip here, then:
unzip jfrog-ciso-report-v4.3.0.zip
# expect folder: jfrog-ciso-report/

# Preferred: APM
curl -sSL https://aka.ms/apm-unix | sh          # skip if APM already installed / air-gapped
apm --version
apm init -y --target claude,codex,cursor
apm install ./jfrog-ciso-report --target claude,cursor,codex
```

If APM cannot be used, place the unpacked skill where your agent loads skills from, preserving:

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

The zip is self-contained for the skill (runner, HTML/PDF templates, schema). It does **not** include `jf`, Python, Node, jq, or a browser.

---

## 5. How PDF generation works

The skill does **not** open a PDF viewer or print dialog. It **renders a PDF file headlessly** and writes it to disk next to the HTML report.

### Pipeline

```text
1. Collect live JFrog data (jf + python3)
2. Build structured JSON
3. Inject JSON into HTML templates
       ├── report.html              ← interactive dashboard (always)
       └── print HTML under /tmp    ← print-optimised template(s)
4. If CISO_PDF_MODE != none:
       node bin/generate-ciso-pdf.js  <print.html>  <output.pdf>
5. Verify the PDF starts with %PDF- and is a sensible size
```

### What `generate-ciso-pdf.js` does

1. Looks for a renderer, in order:  
   - **Puppeteer** (if `require('puppeteer')` works), else  
   - A local browser via `CISO_CHROME_BIN`, or PATH names:  
     `google-chrome`, `google-chrome-stable`, `chromium`, `chromium-browser`, `microsoft-edge`
2. Opens the print HTML as a local `file:///...` URL  
3. Runs the browser **headless** (no window, no desktop required)  
4. Prints to PDF (A4, backgrounds on)  
5. Writes one of:  
   - `executive-report.pdf` — concise, shareable  
   - `full-report.pdf` — detailed internal  
   - both, when `CISO_PDF_MODE=both`

**Chromium path (no Puppeteer)** effectively runs:

```bash
chromium \
  --headless=new \
  --disable-gpu \
  --allow-file-access-from-files \
  --print-to-pdf=/path/to/executive-report.pdf \
  file:///tmp/ciso-report-print-....html
```

**Puppeteer path** launches its bundled Chromium, loads the same HTML, then calls `page.pdf(...)`.

### Modes

| `CISO_PDF_MODE` | Result |
|-----------------|--------|
| unset / `executive` | `executive-report.pdf` |
| `full` | `full-report.pdf` |
| `both` | both PDFs |
| `none` | HTML (+ CSV/snapshot) only — **no browser / Node PDF check** |

### Preflight

Before collection (when PDF mode is not `none`), the runner runs:

```bash
node .../generate-ciso-pdf.js --check
```

That only confirms a browser or Puppeteer is available. It does not generate a file yet.

### After the run — how you *open* the PDF

The skill **writes** the PDF on the Linux host. It never opens a viewer there.

On a headless VM, copy `executive-report.pdf` to a laptop and open it (Preview, Adobe, Chrome, Edge). A GUI on the Linux box is not required for generation.

---

## 6. Headless / UI-less Linux **with PDF** (recommended for this customer)

A server with no desktop can still produce `executive-report.pdf`. Chromium and Puppeteer both run **headless** (`--headless=new`). There is no browser window and no X11/Wayland requirement.

**If they want PDF, they must install one of:** Chromium / Google Chrome **or** Puppeteer, **plus Node.js 18+**.  
`CISO_PDF_MODE=none` is only for sites that cannot install either.

### Option A — Chromium on Ubuntu/Debian (preferred)

```bash
sudo apt-get update
sudo apt-get install -y nodejs   # v18+; prefer Node 20 LTS if apt is too old
sudo apt-get install -y chromium-browser
# Ubuntu 24.04 sometimes packages this as:
# sudo apt-get install -y chromium

command -v chromium-browser || command -v chromium
export CISO_CHROME_BIN="$(command -v chromium-browser || command -v chromium)"
```

Prefer a **.deb** Chromium or Google Chrome over the Ubuntu **snap** build. Some snap Chromium installs cannot read `file:///tmp/...` print HTML.

**Google Chrome** is equivalent: install the official `.deb` and ensure `google-chrome` or `google-chrome-stable` is on `PATH`.

RHEL / Rocky / Alma: install `chromium` or `google-chrome-stable` from your approved repo, plus `nodejs` ≥ 18.

### Option B — Puppeteer (when apt Chromium is blocked or snap-broken)

Puppeteer downloads a known Chromium and does not need a system browser.

Install it where the skill’s Node process can `require('puppeteer')` — typically next to the unpacked skill:

```bash
# after unzip / apm install, from the skill folder that contains bin/generate-ciso-pdf.js
cd ~/.claude/skills/jfrog-ciso-report        # or ~/ciso-reporting/jfrog-ciso-report/.apm/skills/jfrog-ciso-report
npm install puppeteer
node bin/generate-ciso-pdf.js --check
# expect: PDF renderer available: Puppeteer
```

Air-gapped hosts: seed `npm` from an internal registry, or vendor `node_modules/puppeteer` (and Puppeteer’s Chromium cache) with the zip.

### Prove PDF works before the first long run

```bash
node ~/.claude/skills/jfrog-ciso-report/bin/generate-ciso-pdf.js --check
# expect: PDF renderer available: /usr/bin/chromium-browser   (or Puppeteer)
```

Then generate with:

```bash
export CISO_PDF_MODE=executive   # default; produces executive-report.pdf
```

### How they open the PDF (still no GUI on Linux)

Generation finishes on the server. Viewing is on any PC:

```bash
# from a laptop
scp user@linux-host:~/ciso-reports/<server-id>/weekly/<date>/executive-report.pdf .
# double-click the PDF, or open in Chrome / Edge / Preview
```

Same for `report.html` if they also want the interactive dashboard.

### If they cannot install Chromium or Puppeteer

Only then use HTML-only (`CISO_PDF_MODE=none`). There will be **no** official PDF from the skill. Copy `report.html` to a laptop; browser **Print → Save as PDF** is a fallback, not the executive template.

---

## 7. Output location

```bash
mkdir -p ~/ciso-reports
```

Typical tree after a weekly executive run:

```text
~/ciso-reports/<server-id>/weekly/<YYYY-MM-DD>/
├── report.html
├── executive-report.pdf          ← when PDF mode is executive/both
├── curation-user-package-activity.csv
├── snapshot.json
└── run-meta.json
```

---

## 8. Readiness checklist

```bash
echo "=== tools ==="
jf --version && jf config show
python3 --version
jq --version
# node is required only when producing PDFs
[[ "${CISO_PDF_MODE:-executive}" == "none" ]] || node --version

echo "=== PDF path ==="
if [[ "${CISO_PDF_MODE:-executive}" == "none" ]]; then
  echo "HTML-only mode (CISO_PDF_MODE=none)"
else
  command -v chromium-browser || command -v chromium || \
    command -v google-chrome || command -v google-chrome-stable || \
    echo "ERROR: no Linux browser — install Chromium/Chrome or set CISO_PDF_MODE=none"
fi

echo "=== skill bundle ==="
test -f ~/ciso-reporting/jfrog-ciso-report/apm.yml && \
  echo "Unpacked skill found" || echo "Place/install jfrog-ciso-report-v4.3.0.zip first"
```

---

## 9. First run

Ask your agent:

```text
Generate a weekly CISO report for server <server-id>.
Save under ~/ciso-reports.
Use executive PDF.
```

HTML only:

```text
Generate a weekly CISO report for server <server-id>.
Save under ~/ciso-reports.
HTML only (no PDF).
```

Direct runner examples:

```bash
# With PDF
CISO_PDF_MODE=executive \
  ~/.claude/skills/jfrog-ciso-report/bin/generate-ciso-report.sh \
  <server-id> ~/ciso-reports weekly

# HTML only
CISO_PDF_MODE=none \
  ~/.claude/skills/jfrog-ciso-report/bin/generate-ciso-report.sh \
  <server-id> ~/ciso-reports weekly
```

Then open outputs **on a machine with a browser or PDF viewer** (this can be a laptop after `scp`):

```bash
xdg-open ~/ciso-reports/<server-id>/weekly/<date>/report.html
xdg-open ~/ciso-reports/<server-id>/weekly/<date>/executive-report.pdf   # only if PDF mode was used
```

---

## 10. Common Linux issues

| Symptom | Cause | Fix |
|---------|--------|-----|
| `No PDF browser found` | Chromium/Chrome not installed, or not on PATH | Install browser, set `CISO_CHROME_BIN`, use Puppeteer, or `CISO_PDF_MODE=none` |
| PDF missing / tiny | Headless print failed | Run `generate-ciso-pdf.js --check`; try `chromium --headless=new --print-to-pdf=/tmp/t.pdf about:blank` |
| Snap Chromium quirks | Some Ubuntu snap builds restrict file access | Prefer `.deb` Chromium/Chrome, Puppeteer, or HTML-only |
| Skill install fails on “Source code” zip | Wrong archive | Use **`jfrog-ciso-report-v4.3.0.zip`** only |
| `node: command not found` with PDF mode | Node not installed | Install Node 18+/20, or use `CISO_PDF_MODE=none` |
| Cannot “open” the report on the server | Host has no browser / no GUI | Copy `report.html` (self-contained) to a laptop and open it there — see §6 |

---

## 11. What we need from you (customer checklist)

1. Linux host (Ubuntu 22.04/24.04 preferred), GUI **not** required  
2. Access to JFrog Platform with Xray + Curation  
3. Ability to install (or receive binaries for) `jf`, Python 3.10+, **Node 18+/20**, **jq**  
4. **Chromium / Google Chrome or Puppeteer** on that host (required for PDF)  
5. Receipt of **`jfrog-ciso-report-v4.3.0.zip`** (~650 KB)

---

## Related references

- Skill version: **jfrog-ciso-report v4.3.0**  
- Offline bundle: **`jfrog-ciso-report-v4.3.0.zip`**  
- Windows / WSL2: [WSL2-WINDOWS-CUSTOMER-SETUP.md](WSL2-WINDOWS-CUSTOMER-SETUP.md)  
- Interpreting the report: [INTERPRETING-THE-REPORT.md](INTERPRETING-THE-REPORT.md)  
- General install options: [INSTALL.md](INSTALL.md)

---

*Document version: aligned with jfrog-ciso-report v4.3.0 · Audience: customer IT / platform engineering preparing a Linux workstation or VM*
