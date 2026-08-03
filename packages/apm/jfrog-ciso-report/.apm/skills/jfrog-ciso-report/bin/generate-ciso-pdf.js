#!/usr/bin/env node
/**
 * Render an injected CISO print template to an A4 PDF.
 *
 * Usage: node generate-ciso-pdf.js <input.html> <output.pdf>
 *
 * Uses Puppeteer when installed. Otherwise it drives a locally installed
 * Chrome/Chromium without downloading dependencies during a report run.
 */

const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const { spawnSync } = require('child_process');

const IS_WINDOWS = process.platform === 'win32';

// Standard per-user and machine-wide install locations. Resolved from the
// environment rather than hardcoded so localised or relocated Program Files
// directories still match.
function windowsBrowserCandidates() {
  const roots = [
    process.env.ProgramFiles,
    process.env['ProgramFiles(x86)'],
    process.env.LOCALAPPDATA,
  ].filter(Boolean);
  const suffixes = [
    ['Google', 'Chrome', 'Application', 'chrome.exe'],
    ['Chromium', 'Application', 'chrome.exe'],
    ['Microsoft', 'Edge', 'Application', 'msedge.exe'],
  ];
  const out = [];
  for (const root of roots) {
    // Explicitly win32 so the joined paths are backslash-separated even when
    // this is exercised from a POSIX host.
    for (const suffix of suffixes) out.push(path.win32.join(root, ...suffix));
  }
  return out;
}

// A bare command name is looked up on PATH; anything else is treated as a
// filesystem path. Windows accepts both separators plus drive-letter prefixes.
function looksLikePath(candidate) {
  if (candidate.includes('/')) return true;
  return IS_WINDOWS && (candidate.includes('\\') || /^[A-Za-z]:/.test(candidate));
}

function resolveOnPath(candidate) {
  const probe = IS_WINDOWS
    ? spawnSync('where', [candidate], { encoding: 'utf8' })
    : spawnSync('sh', ['-c', `command -v "${candidate}"`], { encoding: 'utf8' });
  if (probe.status !== 0) return null;
  const first = (probe.stdout || '').split(/\r?\n/).find((line) => line.trim());
  return first ? first.trim() : null;
}

// file:// + a Windows path yields file://C:\... which Chrome rejects. Going
// through pathToFileURL also percent-encodes spaces on every platform.
function fileUrlFor(inputPath) {
  return pathToFileURL(path.resolve(inputPath)).href;
}

function findBrowser() {
  const candidates = [
    process.env.CISO_CHROME_BIN,
    process.platform === 'darwin'
      ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
      : null,
    process.platform === 'darwin'
      ? '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'
      : null,
    ...(IS_WINDOWS ? windowsBrowserCandidates() : []),
    'google-chrome',
    'google-chrome-stable',
    'chromium',
    'chromium-browser',
    'microsoft-edge',
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (looksLikePath(candidate)) {
      if (fs.existsSync(candidate)) return candidate;
      continue;
    }
    const resolved = resolveOnPath(candidate);
    if (resolved) return resolved;
  }
  return null;
}

function verifyPDF(outputPath) {
  if (!fs.existsSync(outputPath)) {
    throw new Error(`browser did not create ${outputPath}`);
  }
  const stat = fs.statSync(outputPath);
  const signature = fs.readFileSync(outputPath).subarray(0, 5).toString();
  if (signature !== '%PDF-' || stat.size < 10_000) {
    throw new Error(`invalid or unexpectedly small PDF (${stat.size} bytes)`);
  }
  console.log(`PDF generated: ${outputPath}`);
  console.log(`Size: ${(stat.size / 1024).toFixed(0)} KB`);
}

async function renderWithPuppeteer(puppeteer, inputPath, outputPath) {
  const browser = await puppeteer.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--font-render-hinting=none',
    ],
  });
  try {
    const page = await browser.newPage();
    await page.goto(fileUrlFor(inputPath), {
      waitUntil: 'networkidle0',
      timeout: 20000,
    });
    await page.waitForFunction(
      () => document.getElementById('report')?.innerText.length > 100,
      { timeout: 10000 }
    );
    await page.pdf({
      path: outputPath,
      format: 'A4',
      printBackground: true,
      displayHeaderFooter: false,
      preferCSSPageSize: true,
    });
  } finally {
    await browser.close();
  }
}

function renderWithBrowser(browserPath, inputPath, outputPath) {
  const result = spawnSync(browserPath, [
    '--headless=new',
    '--disable-gpu',
    '--disable-dev-shm-usage',
    '--allow-file-access-from-files',
    '--run-all-compositor-stages-before-draw',
    '--virtual-time-budget=3000',
    '--no-pdf-header-footer',
    `--print-to-pdf=${path.resolve(outputPath)}`,
    fileUrlFor(inputPath),
  ], {
    encoding: 'utf8',
    timeout: 45000,
  });
  if (result.status !== 0) {
    throw new Error(
      `Chrome PDF render failed (${result.status}): ` +
      `${(result.stderr || result.stdout || '').trim()}`
    );
  }
}

async function main() {
  const [inputArg, outputArg] = process.argv.slice(2);
  if (inputArg === '--check') {
    let puppeteer;
    try {
      puppeteer = require('puppeteer');
    } catch {
      puppeteer = null;
    }
    const browserPath = puppeteer ? 'Puppeteer' : findBrowser();
    if (!browserPath) {
      throw new Error(
        'No PDF browser found. Install Google Chrome/Chromium, install ' +
        'Puppeteer, or set CISO_CHROME_BIN.'
      );
    }
    console.log(`PDF renderer available: ${browserPath}`);
    return;
  }
  if (!inputArg) {
    console.error('Usage: node generate-ciso-pdf.js <input.html> <output.pdf>');
    process.exit(2);
  }

  const inputPath = path.resolve(inputArg);
  const outputPath = path.resolve(
    outputArg || inputPath.replace(/\.html?$/i, '.pdf')
  );
  if (!fs.existsSync(inputPath)) {
    throw new Error(`input file not found: ${inputPath}`);
  }

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.rmSync(outputPath, { force: true });
  console.log(`PDF input: ${inputPath}`);
  console.log(`PDF output: ${outputPath}`);

  let puppeteer;
  try {
    puppeteer = require('puppeteer');
  } catch {
    puppeteer = null;
  }

  if (puppeteer) {
    await renderWithPuppeteer(puppeteer, inputPath, outputPath);
  } else {
    const browserPath = findBrowser();
    if (!browserPath) {
      throw new Error(
        'No PDF browser found. Install Google Chrome/Chromium, install ' +
        'Puppeteer, or set CISO_CHROME_BIN.'
      );
    }
    renderWithBrowser(browserPath, inputPath, outputPath);
  }
  verifyPDF(outputPath);
}

main().catch((error) => {
  console.error(`PDF generation failed: ${error.message}`);
  process.exit(1);
});
