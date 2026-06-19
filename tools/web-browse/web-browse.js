#!/usr/bin/env node

/**
 * 🌐 Dynamic Browser Automation via Puppeteer (web_browse.js)
 * 
 * Version 0.0.0
 * 
 * This script accepts a JSON payload describing a list of actions to perform on a page,
 * executes them in a headless/headful browser, captures logs/errors, and outputs a structured
 * JSON result containing execution telemetry.
 * 
 * By default, Tor HTTP proxy routing on 127.0.0.1:9080 is enabled.
 * Use --no-tor option or pass "noTor": true / "tor": false in the JSON config to disable proxy routing.
 * 
 * Usage:
 *   ./web_browse.js '<JSON_PAYLOAD_STRING>'
 *   ./web_browse.js --no-tor '<JSON_PAYLOAD_STRING>'
 *   ./web_browse.js config.json
 *   ./web_browse.js --no-tor config.json
 *   cat config.json | ./web_browse.js
 *   cat config.json | ./web_browse.js --no-tor
 */

import puppeteer from 'puppeteer';
import fs from 'fs';
import path from 'path';

// Helper for waiting
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// Retrieve input JSON
async function getInputPayload(arg) {
  if (arg) {
    // Check if it's a file path
    try {
      if (fs.existsSync(arg)) {
        return JSON.parse(fs.readFileSync(arg, 'utf-8'));
      }
    } catch (e) {
      // Not a file, or error reading file. Fall through to string parse.
    }

    // Try parsing as a raw JSON string
    try {
      return JSON.parse(arg);
    } catch (e) {
      throw new Error(`Failed to parse CLI argument as JSON: ${e.message}`);
    }
  }

  // Fall back to reading from stdin
  return new Promise((resolve, reject) => {
    let data = '';
    process.stdin.setEncoding('utf-8');
    
    // Set a timeout of 1 second for stdin to avoid hanging if no stdin is piped
    const timer = setTimeout(() => {
      if (data.trim() === '') {
        reject(new Error("No JSON input provided. Pass a JSON string, a JSON file path, or pipe to stdin."));
      }
    }, 1000);

    process.stdin.on('readable', () => {
      let chunk;
      while ((chunk = process.stdin.read()) !== null) {
        data += chunk;
      }
    });

    process.stdin.on('end', () => {
      clearTimeout(timer);
      try {
        if (data.trim() === '') {
          reject(new Error("Empty input from stdin."));
          return;
        }
        resolve(JSON.parse(data));
      } catch (e) {
        reject(new Error(`Failed to parse stdin as JSON: ${e.message}`));
      }
    });
  });
}

// Automatically detect environments and return optimal launch flags
function getBrowserLaunchConfig(payload, useTor) {
  const isTermux = fs.existsSync('/data/data/com.termux');
  const config = {
    headless: payload.headless !== undefined ? payload.headless : 'shell',
    args: [],
    dumpio: payload.dumpio !== undefined ? payload.dumpio : true,
  };

  // Bind to system Chromium in Termux
  if (isTermux) {
    config.executablePath = '/data/data/com.termux/files/usr/bin/chromium';
    config.args.push(
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-gpu',
      '--disable-dev-shm-usage'
    );
  }

  // Handle custom user agent
  if (payload.userAgent) {
    config.args.push(`--user-agent=${payload.userAgent}`);
  }

  // Handle Tor / Proxy routing (127.0.0.1:9080 HTTP proxy by default)
  if (useTor) {
    const proxyAddress = payload.proxy || '127.0.0.1:9080';
    config.args.push(`--proxy-server=${proxyAddress}`);
    // Bypass local loopbacks if requested or by default for local debugging
    config.args.push('--proxy-bypass-list=<-loopback>');
  } else if (payload.proxy) {
    // If manual proxy is explicitly provided but Tor default is disabled
    config.args.push(`--proxy-server=${payload.proxy}`);
    config.args.push('--proxy-bypass-list=<-loopback>');
  }

  // Handle slowMo for human-in-the-loop debugging
  if (payload.slowMo !== undefined) {
    config.slowMo = payload.slowMo;
  }

  return config;
}

async function main() {
  const telemetry = {
    success: false,
    title: '',
    url: '',
    consoleLogs: [],
    evaluateResults: [],
    error: null,
    screenshots: []
  };

  try {
    const args = process.argv.slice(2);
    let useTor = true;

    // Parse CLI options (check for --no-tor flag)
    const noTorIndex = args.indexOf('--no-tor');
    if (noTorIndex !== -1) {
      useTor = false;
      args.splice(noTorIndex, 1); // Remove option from arguments
    }

    // Retrieve JSON input payload
    const payload = await getInputPayload(args[0]);
    if (!payload || !payload.url) {
      throw new Error("Invalid payload: 'url' parameter is required.");
    }

    // Check JSON options for Tor override (both snake_case and camelCase)
    if (payload.noTor === true || payload.no_tor === true || payload.tor === false) {
      useTor = false;
    }

    // Support tools-light.json simplified parameters (screenshot_path mapping)
    if (!payload.actions) {
      payload.actions = [];
    }
    if (payload.screenshot_path) {
      payload.actions.push({
        type: 'screenshot',
        path: payload.screenshot_path,
        fullPage: true
      });
    }


    const launchConfig = getBrowserLaunchConfig(payload, useTor);
    const browser = await puppeteer.launch(launchConfig);
    const page = await browser.newPage();

    // Set viewport
    if (payload.viewport) {
      await page.setViewport({
        width: payload.viewport.width || 1280,
        height: payload.viewport.height || 800,
        deviceScaleFactor: payload.viewport.deviceScaleFactor || 1,
        isMobile: payload.viewport.isMobile || false,
        hasTouch: payload.viewport.hasTouch || false
      });
    } else {
      await page.setViewport({ width: 1280, height: 800 });
    }

    // Attach Console log captures
    page.on('console', msg => {
      telemetry.consoleLogs.push({
        type: msg.type(),
        text: msg.text(),
        location: msg.location()
      });
    });

    page.on('pageerror', err => {
      telemetry.consoleLogs.push({
        type: 'error',
        text: err.toString()
      });
    });

    // Navigate to URL
    const waitOption = payload.waitUntil || 'networkidle2';
    await page.goto(payload.url, { waitUntil: waitOption });
    telemetry.url = page.url();
    telemetry.title = await page.title();

    // Process Actions
    if (payload.actions && Array.isArray(payload.actions)) {
      for (let i = 0; i < payload.actions.length; i++) {
        const action = payload.actions[i];
        
        switch (action.type) {
          case 'wait':
            if (action.selector) {
              const timeout = action.timeout || 30000;
              await page.waitForSelector(action.selector, { timeout });
            } else if (action.timeout || action.delay) {
              await delay(action.timeout || action.delay);
            } else {
              await delay(1000); // Default 1s pause
            }
            break;

          case 'click':
            if (!action.selector) throw new Error(`Action 'click' at index ${i} requires a selector.`);
            await page.click(action.selector);
            break;

          case 'type':
            if (!action.selector) throw new Error(`Action 'type' at index ${i} requires a selector.`);
            if (action.text === undefined) throw new Error(`Action 'type' at index ${i} requires 'text'.`);
            await page.type(action.selector, action.text);
            break;

          case 'press':
            const key = action.key || action.text;
            if (!key) throw new Error(`Action 'press' at index ${i} requires a 'key' or 'text' key code.`);
            await page.keyboard.press(key);
            break;

          case 'screenshot':
            const snapPath = action.path || `data/screenshot_${Date.now()}.png`;
            const fullPage = action.fullPage !== undefined ? action.fullPage : false;
            // Ensure directory exists
            const dir = path.dirname(snapPath);
            if (!fs.existsSync(dir)){
              fs.mkdirSync(dir, { recursive: true });
            }
            await page.screenshot({ path: snapPath, fullPage });
            telemetry.screenshots.push({ index: i, path: snapPath });
            break;

          case 'pdf':
            const pdfPath = action.path || `data/document_${Date.now()}.pdf`;
            const pdfDir = path.dirname(pdfPath);
            if (!fs.existsSync(pdfDir)){
              fs.mkdirSync(pdfDir, { recursive: true });
            }
            await page.pdf({ path: pdfPath, format: action.format || 'A4' });
            break;

          case 'evaluate':
            if (!action.expression) throw new Error(`Action 'evaluate' at index ${i} requires an 'expression'.`);
            const evalRes = await page.evaluate(action.expression);
            telemetry.evaluateResults.push({ index: i, result: evalRes });
            break;

          case 'scroll':
            const scrollExpr = action.direction === 'bottom' 
              ? 'window.scrollTo(0, document.body.scrollHeight)' 
              : 'window.scrollBy(0, window.innerHeight)';
            await page.evaluate(scrollExpr);
            break;

          default:
            throw new Error(`Unknown action type: '${action.type}' at index ${i}`);
        }
      }
    }

    // Capture final state
    telemetry.url = page.url();
    telemetry.title = await page.title();
    telemetry.success = true;

    await browser.close();
  } catch (error) {
    telemetry.success = false;
    telemetry.error = error.message;
  }

  // Print results to stdout as pure JSON
  console.log(JSON.stringify(telemetry, null, 2));

  // Exit with clean code, let telemetry convey success/failure
  process.exit(0);
}

main();
