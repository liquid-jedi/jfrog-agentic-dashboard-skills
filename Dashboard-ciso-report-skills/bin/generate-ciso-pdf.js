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
const { spawnSync } = require('child_process');

function findBrowser() {
  const candidates = [
    process.env.CISO_CHROME_BIN,
    process.platform === 'darwin'
      ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
      : null,
    process.platform === 'darwin'
      ? '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'
      : null,
    'google-chrome',
    'google-chrome-stable',
    'chromium',
    'chromium-browser',
    'microsoft-edge',
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (candidate.includes('/') && fs.existsSync(candidate)) return candidate;
    if (!candidate.includes('/')) {
      const check = spawnSync('sh', ['-c', `command -v "${candidate}"`], {
        encoding: 'utf8',
      });
      if (check.status === 0 && check.stdout.trim()) return check.stdout.trim();
    }
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
    await page.goto(`file://${inputPath}`, {
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
    `--print-to-pdf=${outputPath}`,
    `file://${inputPath}`,
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
