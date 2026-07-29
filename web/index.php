<?php
/**
 * ⚡ A.I.D.E. Web Portal
 *
 * Powered by Fat-Free Framework (F3) micro-engine.
 * Implements Option C: Unix Pipe Stream Bridge for real-time SSE streaming.
 * Provides live Cognitive Memory Explorer & system Telemetry HUD.
 * Fully Localized (i18n) Supporting dynamic English & French switching.
 *
 * Architect: Jiab77
 * AI Sorcerer: Jarvis (The Great Master Flash)
 * Version: 0.0.1
 */

// Load Fat-Free Framework Core
require_once __DIR__ . '/lib/fatfree-core/base.php';

define('PROJECT_ROOT', dirname(realpath(__DIR__)));
define('WEB_ROOT', PROJECT_ROOT . '/web');

// Init
$f3 = \Base::instance();

// Configure F3 parameters
$f3->set('DEBUG', 1); // Enable detailed errors during staging
$f3->set('UI', 'templates/');

// =============================================================================
// I18N / TRANSLATION INITIALIZATION
// =============================================================================

// Determine language to load
$lang = 'en'; // default fallback

if ($f3->exists('GET.lang')) {
    $requestedLang = strtolower($f3->get('GET.lang'));
    if (in_array($requestedLang, ['fr', 'en'])) {
        $lang = $requestedLang;
        // Persist language preference in a cookie for 30 days
        setcookie('aide_lang', $lang, time() + (86400 * 30), '/');
    }
} elseif (isset($_COOKIE['aide_lang']) && in_array($_COOKIE['aide_lang'], ['fr', 'en'])) {
    $lang = $_COOKIE['aide_lang'];
} else {
    // Auto-detect using Accept-Language header
    $acceptLang = $f3->get('HEADERS.Accept-Language');
    if (!empty($acceptLang)) {
        $primaryLang = substr(strtolower($acceptLang), 0, 2);
        if (in_array($primaryLang, ['fr', 'en'])) {
            $lang = $primaryLang;
        }
    }
}

$f3->set('ACTIVE_LANG', $lang);

// Load target JSON dictionary
$dictFile = __DIR__ . "/i18n/{$lang}.json";
if (file_exists($dictFile)) {
    $translations = json_decode(file_get_contents($dictFile), true);
} else {
    $translations = json_decode(file_get_contents(__DIR__ . '/i18n/en.json'), true);
}

// Bind dictionary into F3 container
$f3->set('DICT', $translations);

// Load version file
if (file_exists(WEB_ROOT . '/version.json')) {
    $f3->set('WEB_VERSION', json_decode(file_get_contents(WEB_ROOT . '/version.json'))->version);
}

// Load provider config file
if (file_exists(PROJECT_ROOT . '/config/providers.json')) {
    $f3->set('PROVIDERS', json_decode(file_get_contents(PROJECT_ROOT . '/config/providers.json')));
}

// Load state config file
if (file_exists(PROJECT_ROOT . '/config/state.json')) {
    $f3->set('CONFIG_STATE', json_decode(file_get_contents(PROJECT_ROOT . '/config/state.json')));
}

// Dynamic Translation Helper function
function __($key) {
    $f3 = \Base::instance();
    $dict = $f3->get('DICT');
    return $dict[$key] ?? $key;
}

// Helper: Detect CPU cores across Windows, MacOS, Linux, BSD
function detect_cpu_cores(): int {
    $cores = 4; // fallback
    if (DIRECTORY_SEPARATOR === '\\') {
        $envCores = getenv('NUMBER_OF_PROCESSORS');
        if ($envCores !== false && is_numeric($envCores)) {
            $cores = (int)$envCores;
        }
    } else {
        if (is_executable('/usr/bin/nproc')) {
            $nproc = trim((string)shell_exec('nproc 2>/dev/null'));
            if (is_numeric($nproc)) {
                $cores = (int)$nproc;
            }
        } elseif (is_executable('/usr/sbin/sysctl') || is_executable('/usr/bin/sysctl')) {
            $sysctl = trim((string)shell_exec('sysctl -n hw.ncpu 2>/dev/null'));
            if (is_numeric($sysctl)) {
                $cores = (int)$sysctl;
            }
        } else {
            if (@file_exists('/proc/cpuinfo')) {
                $cpuinfo = file_get_contents('/proc/cpuinfo');
                preg_match_all('/^processor/m', $cpuinfo, $matches);
                $count = count($matches[0]);
                if ($count > 0) {
                    $cores = $count;
                }
            }
        }
    }
    return max(1, $cores);
}

// =============================================================================
// API ROUTES
// =============================================================================

// 1. Telemetry HUD Endpoint
$f3->route('GET /api/telemetry', function($f3) {
    header('Content-Type: application/json');

    // CPU Load
    $load = [0, 0, 0];
    if (function_exists('sys_getloadavg')) {
        $load = sys_getloadavg() ?: [0, 0, 0];
    }

    // Memory
    $memTotal = 0;
    $memFree = 0;
    $memUsed = 0;
    if (file_exists('/proc/meminfo')) {
        $meminfo = file_get_contents('/proc/meminfo');
        if (preg_match('/MemTotal:\s+(\d+) kB/', $meminfo, $matches)) {
            $memTotal = (int)$matches[1] * 1024;
        }
        if (preg_match('/MemAvailable:\s+(\d+) kB/', $meminfo, $matches)) {
            $memFree = (int)$matches[1] * 1024;
        } else if (preg_match('/MemFree:\s+(\d+) kB/', $meminfo, $matches)) {
            $memFree = (int)$matches[1] * 1024;
        }
        $memUsed = $memTotal - $memFree;
    }

    // Battery for Termux
    $battery = null;
    if (is_executable('/data/data/com.termux/files/usr/bin/termux-battery-status')) {
        $batRaw = shell_exec('termux-battery-status 2>/dev/null');
        if ($batRaw) {
            $battery = json_decode($batRaw, true);
        }
    }
    elseif (file_exists('/sys/class/power_supply/BAT0/present')) {
        $rawPresent = file_get_contents('/sys/class/power_supply/BAT0/present');
        $rawCapacity = file_get_contents('/sys/class/power_supply/BAT0/capacity');
        $rawStatus = file_get_contents('/sys/class/power_supply/BAT0/status');
        $batPresent = trim($rawPresent) == '1' ? "true" : "false";
        // $batObj = new \StdClass();
        // $batObj->present = $batPresent;
        // $batObj->percentage = trim($rawCapacity);
        // $batObj->status = strtoupper(trim($rawStatus));
        // if (is_object($batObj)) {
        //     $battery = json_decode(json_encode($batObj));
        // }
        $batRaw  = '{';
        $batRaw .= '"present": ' . $batPresent . ', ';
        $batRaw .= '"percentage": ' . (int)trim($rawCapacity) . ', ';
        $batRaw .= '"status": "' . strtoupper(trim($rawStatus)) . '"';
        $batRaw .= '}';
        if (is_string($batRaw)) {
            $battery = json_decode($batRaw, true);
        }
    }

    // Active Models & Configs (read from config file, NO hardcoded fallback)
    $activeModel = null;
    $activeProvider = null;
    $activeBackend = null;
    $useTor = false;

    $confFile = PROJECT_ROOT . '/config/cli.conf';
    if (!file_exists($confFile)) {
        $confFile = PROJECT_ROOT . '/config/core.conf';
    }
    if (!file_exists($confFile)) {
        $confFile = PROJECT_ROOT . '/core.sh';
    }

    if (file_exists($confFile)) {
        $conf = file_get_contents($confFile);
        $activeBackend = !is_null($f3->get('CONFIG_STATE')) ? $f3->get('CONFIG_STATE')->backend : '';
        $activeProvider = !is_null($f3->get('CONFIG_STATE')) ? $f3->get('CONFIG_STATE')->provider : '';
        $activeModel = !is_null($f3->get('CONFIG_STATE')) ? $f3->get('CONFIG_STATE')->model : '';
        // $activeModel = $f3->get('PROVIDERS')->{$activeProvider}->default->model;
        if (preg_match('/USE_TOR=["\']?(true)["\']?/i', $conf)) {
            $useTor = true;
        }
    }

    // Tor detection: if backend is external, assume Tor-capable
    if ($activeBackend === 'external' && !$useTor) {
        $useTor = true;
    }

    // Get credit balance
    // FIXME: Disabled until I find a better way to handle this part
    $credits = null;
    // if ($activeProvider === 'vercel' && file_exists($confFile)) {
    //     $apiKey = '';
    //     $conf = file_get_contents($confFile);
    //     if (preg_match('/PROVIDER_API_KEY=["\']?([^"\']+)["\']?/', $conf, $matches)) {
    //         $apiKey = $matches[1];
    //     }
    //     if (!empty($apiKey)) {
    //         $ch = curl_init("https://ai-gateway.vercel.sh/v1/credits");
    //         curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    //         curl_setopt($ch, CURLOPT_HTTPHEADER, [
    //             "Content-Type: application/json",
    //             "Authorization: Bearer " . $apiKey,
    //             "User-Agent: AIDEWeb"
    //         ]);
    //         curl_setopt($ch, CURLOPT_TIMEOUT, 3);
    //         if ($useTor) {
    //             curl_setopt($ch, CURLOPT_PROXY, "socks5h://127.0.0.1:9050");
    //         }
    //         $res = curl_exec($ch);
    //         curl_close($ch);
    //         if ($res) {
    //             $json = json_decode($res, true);
    //             if (isset($json['balance'])) {
    //                 $credits = $json['balance'];
    //             }
    //         }
    //     }
    // }

    echo json_encode([
        'cpu' => [
            'load' => $load,
            'cores' => detect_cpu_cores()
        ],
        'memory' => [
            'total' => $memTotal,
            'used' => $memUsed,
            'free' => $memFree,
            'percentage' => $memTotal > 0 ? round(($memUsed / $memTotal) * 100, 1) : 0
        ],
        'battery' => $battery,
        'ai' => [
            'model' => $activeModel,
            'provider' => $activeProvider,
            'backend' => $activeBackend,
            'credits' => $credits,
            'tor' => $useTor
        ],
        'os' => [
            'name' => PHP_OS,
            'family' => PHP_OS_FAMILY,
            'version' => php_uname('r')
        ]
    ]);
    exit;
});

// 2. Memory Explorer Index
$f3->route('GET /api/memory', function($f3) {
    header('Content-Type: application/json');
    $files = [];

    $memDir = PROJECT_ROOT . '/data/memory';
    if (is_dir($memDir)) {
        foreach (scandir($memDir) as $file) {
            if ($file !== '.' && $file !== '..' && substr($file, -3) === '.md') {
                $files[] = [
                    'group' => 'Memory',
                    'name' => $file,
                    'path' => 'data/memory/' . $file,
                    'size' => filesize($memDir . '/' . $file),
                    'mtime' => filemtime($memDir . '/' . $file)
                ];
            }
        }
    }

    $skillsDir = PROJECT_ROOT . '/data/skills';
    if (is_dir($skillsDir)) {
        foreach (scandir($skillsDir) as $file) {
            if ($file !== '.' && $file !== '..' && substr($file, -3) === '.md') {
                $files[] = [
                    'group' => 'Skills',
                    'name' => $file,
                    'path' => 'data/skills/' . $file,
                    'size' => filesize($skillsDir . '/' . $file),
                    'mtime' => filemtime($skillsDir . '/' . $file)
                ];
            }
        }
    }

    echo json_encode(['files' => $files]);
    exit;
});

// 3. Memory Explorer Fetch Content
$f3->route('GET /api/memory/content', function($f3) {
    header('Content-Type: application/json');
    $path = $f3->get('GET.path');

    // STRICT SECURITY SANITIZATION (Prevent Directory Traversal RCE)
    if (empty($path) || (strpos($path, 'data/memory/') !== 0 && strpos($path, 'data/skills/') !== 0) || strpos($path, '..') !== false) {
        echo json_encode(['error' => 'Unauthorized or invalid file path.']);
        exit;
    }

    $fullPath = PROJECT_ROOT . '/' . $path;
    if (file_exists($fullPath)) {
        echo json_encode([
            'path' => $path,
            'content' => file_get_contents($fullPath)
        ]);
    } else {
        echo json_encode(['error' => 'File not found.']);
    }
    exit;
});

// 4. Memory Explorer Save Content
$f3->route('POST /api/memory/save', function($f3) {
    header('Content-Type: application/json');

    $data = json_decode($f3->get('BODY'), true);
    $path = $data['path'] ?? '';
    $content = $data['content'] ?? '';

    // STRICT SECURITY SANITIZATION (Prevent Directory Traversal RCE)
    if (empty($path) || (strpos($path, 'data/memory/') !== 0 && strpos($path, 'data/skills/') !== 0) || strpos($path, '..') !== false) {
        echo json_encode(['error' => 'Unauthorized or invalid file path.']);
        exit;
    }

    $fullPath = PROJECT_ROOT . '/' . $path;
    if (file_put_contents($fullPath, $content) !== false) {
        echo json_encode(['success' => true]);
    } else {
        echo json_encode(['error' => 'Failed to write file. Check file permissions.']);
    }
    exit;
});

// 5. Unix Pipe Stream Bridge (Option C) for Interactive Web Chat
$f3->route('GET /api/chat/stream', function($f3) {
    header('Content-Type: text/event-stream');
    header('Cache-Control: no-cache');
    header('Connection: keep-alive');
    header('X-Accel-Buffering: no'); // Disable buffering for Nginx/Apache

    $query = $f3->get('GET.q');
    if (empty($query)) {
        echo "data: " . json_encode(['error' => 'Empty query']) . PHP_EOL . PHP_EOL;
        exit;
    }

    // Target execution script
    $script = PROJECT_ROOT . '/data/test-core.sh';
    if (!file_exists($script)) {
        $script = PROJECT_ROOT . '/core.sh';
    }

    if (!file_exists($script)) {
        echo "data: " . json_encode(['type' => 'error', 'text' => 'Core script not found: ' . $script]) . PHP_EOL . PHP_EOL;
        exit;
    }

    $descriptorspec = [
        0 => ["pipe", "r"], // stdin
        1 => ["pipe", "w"], // stdout
        2 => ["pipe", "w"]  // stderr
    ];

    // Establish environment variables
    $env = [
        'RUN_MODE' => 'simple',
        'TERM' => 'xterm-256color', // Preserve ANSI colors for terminal fidelity!
        'PATH' => getenv('PATH'),
        'HOME' => getenv('HOME')
    ];
    if (getenv('TMPDIR')) {
        $env['TMPDIR'] = getenv('TMPDIR');
    }

    // Launch subprocess asynchronously
    $process = proc_open("bash " . escapeshellarg($script) . " " . escapeshellarg($query), $descriptorspec, $pipes, dirname(__DIR__), $env);

    if (is_resource($process)) {
        fclose($pipes[0]); // No stdin needed

        // Non-blocking IO stream flags
        stream_set_blocking($pipes[1], 0);
        stream_set_blocking($pipes[2], 0);

        while (!feof($pipes[1]) || !feof($pipes[2])) {
            $read = [$pipes[1], $pipes[2]];
            $write = null;
            $except = null;

            // Wait for data (100ms timeout)
            if (stream_select($read, $write, $except, 0, 100000) > 0) {
                foreach ($read as $pipe) {
                    if ($pipe === $pipes[1]) {
                        $line = fgets($pipes[1]);
                        if ($line !== false && $line !== '') {
                            echo "data: " . json_encode(['type' => 'stdout', 'text' => $line]) . PHP_EOL . PHP_EOL;
                            ob_flush();
                            flush();
                        }
                    } else if ($pipe === $pipes[2]) {
                        $line = fgets($pipes[2]);
                        if ($line !== false && $line !== '') {
                            echo "data: " . json_encode(['type' => 'stderr', 'text' => $line]) . PHP_EOL . PHP_EOL;
                            ob_flush();
                            flush();
                        }
                    }
                }
            }

            if (connection_aborted()) {
                break;
            }
        }

        fclose($pipes[1]);
        fclose($pipes[2]);
        proc_close($process);
    } else {
        echo "data: " . json_encode(['type' => 'error', 'text' => 'Failed to initialize core subprocess.']) . PHP_EOL . PHP_EOL;
    }

    echo "data: " . json_encode(['type' => 'done']) . PHP_EOL . PHP_EOL;
    ob_flush();
    flush();
    exit;
});


// =============================================================================
// MAIN DASHBOARD RENDERING ROUTE
// =============================================================================
$f3->route('GET /', function($f3) {
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
    <title>⚡ <?= __('title') ?></title>

    <!-- Fomantic UI CSS v2.9.4 -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/fomantic-ui/2.9.4/semantic.min.css" integrity="sha512-ySrYzxj+EI1e9xj/kRYqeDL5l1wW0IWY8pzHNTIZ+vc1D3Z14UDNPbwup4yOUmlRemYjgUXsUZ/xvCQU2ThEAw==" crossorigin="anonymous" referrerpolicy="no-referrer" />
    <style>
        /* Obsidian Dark Custom Color Palette */
        :root {
            --bg-main: #0c0e14;
            --bg-card: #151821;
            --bg-input: #1a1e2b;
            --border-neon: rgba(100, 181, 246, 0.15);
            --color-text: #e2e8f0;
            --color-text-dim: #94a3b8;
            --accent-cyan: #00b5ad;
            --accent-blue: #64b5f6;
            --accent-orange: #f2711c;
        }

        body {
            background-color: var(--bg-main);
            color: var(--color-text);
            font-family: 'Lato', 'Helvetica Neue', Arial, Helvetica, sans-serif;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            overflow-x: hidden;
        }

        .main-grid {
            margin-top: 1rem !important;
            height: calc(100vh - 90px);
        }

        .premium-card {
            background: var(--bg-card) !important;
            border: 1px solid var(--border-neon) !important;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.5) !important;
            border-radius: 12px !important;
            backdrop-filter: blur(10px);
        }

        .neon-divider {
            height: 1px;
            background: linear-gradient(90deg, rgba(33, 133, 208, 0) 0%, rgba(33, 133, 208, 0.4) 50%, rgba(33, 133, 208, 0) 100%);
            margin: 1rem 0;
        }

        /* Ambient Glow Pulse Indicator */
        .pulse-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: #21ba45;
            box-shadow: 0 0 0 0 rgba(33, 186, 69, 0.7);
            animation: pulse-green 1.8s infinite;
            margin-right: 8px;
            vertical-align: middle;
        }

        @keyframes pulse-green {
            0 { transform: scale(0.95); box-shadow: 0 0 0 0 rgba(33, 186, 69, 0.7); }
            70% { transform: scale(1); box-shadow: 0 0 0 10px rgba(33, 186, 69, 0); }
            100% { transform: scale(0.95); box-shadow: 0 0 0 0 rgba(33, 186, 69, 0); }
        }

        /* Sidebar Tabs Custom styling */
        .ui.vertical.menu.inverted.sidebar-menu {
            background: var(--bg-card);
            border-right: 1px solid var(--border-neon);
            height: 100%;
            border-radius: 12px !important;
        }

        .ui.vertical.menu.inverted.sidebar-menu .item.active {
            background: rgba(100, 181, 246, 0.15) !important;
            border-left: 3px solid var(--accent-blue) !important;
            color: var(--accent-blue) !important;
        }

        /* Chat layout custom styling */
        .chat-container {
            display: flex;
            flex-direction: column;
            height: 100%;
        }

        .chat-history {
            flex-grow: 1;
            overflow-y: auto;
            padding: 1rem;
            background: rgba(0, 0, 0, 0.15);
            border-radius: 8px;
            border: 1px solid rgba(255, 255, 255, 0.03);
            margin-bottom: 1rem;
            max-height: calc(100vh - 350px);
        }

        .chat-bubble {
            margin-bottom: 1rem;
            padding: 1rem;
            border-radius: 8px;
            max-width: 85%;
            line-height: 1.5;
        }

        .chat-bubble.user {
            background: rgba(33, 133, 208, 0.15);
            border: 1px solid rgba(33, 133, 208, 0.3);
            margin-left: auto;
            color: #e3f2fd;
        }

        .chat-bubble.assistant {
            background: rgba(255, 255, 255, 0.03);
            border: 1px solid rgba(255, 255, 255, 0.05);
            margin-right: auto;
            color: var(--color-text);
        }

        /* Glowing console logging window */
        .terminal-panel {
            background: #08090f !important;
            border: 1px solid rgba(0, 181, 173, 0.2) !important;
            border-radius: 8px;
            padding: 10px;
            font-family: 'Courier New', Courier, monospace;
            font-size: 0.85rem;
            color: #2ecc71;
            height: 160px;
            overflow-y: auto;
            margin-top: 1rem;
            box-shadow: inset 0 0 10px rgba(0,0,0,0.8);
        }

        .terminal-panel::-webkit-scrollbar { width: 4px; }
        .terminal-panel::-webkit-scrollbar-thumb { background: rgba(0, 181, 173, 0.3); border-radius: 2px; }

        /* Memory file explorer & editor custom CSS */
        .explorer-list {
            max-height: calc(100vh - 160px);
            overflow-y: auto;
            border-right: 1px solid rgba(255, 255, 255, 0.05);
            padding-right: 8px;
        }

        .explorer-item {
            background: rgba(255, 255, 255, 0.01) !important;
            border-radius: 6px !important;
            margin-bottom: 6px !important;
            border: 1px solid rgba(255, 255, 255, 0.03) !important;
            transition: all 0.2s ease-in-out !important;
            cursor: pointer;
        }

        .explorer-item:hover, .explorer-item.active {
            background: rgba(33, 133, 208, 0.12) !important;
            border-color: rgba(33, 133, 208, 0.3) !important;
        }

        .editor-textarea {
            width: 100%;
            height: calc(100vh - 280px);
            background: #111420;
            color: #d1d5db;
            font-family: 'Courier New', Courier, monospace;
            font-size: 0.95rem;
            border: 1px solid rgba(255,255,255,0.08);
            border-radius: 6px;
            padding: 15px;
            resize: none;
            outline: none;
        }

        .editor-textarea:focus {
            border-color: var(--accent-blue);
            box-shadow: 0 0 10px rgba(100,181,246,0.15);
        }

        .preview-pane {
            height: calc(100vh - 280px);
            border: 1px solid rgba(255,255,255,0.05);
            border-radius: 6px;
            padding: 15px;
            background: rgba(0,0,0,0.1);
            overflow-y: auto;
        }

        /* Modern styled scrollbars */
        ::-webkit-scrollbar { width: 6px; height: 6px; }
        ::-webkit-scrollbar-track { background: rgba(255, 255, 255, 0.01); border-radius: 4px; }
        ::-webkit-scrollbar-thumb { background: rgba(255, 255, 255, 0.1); border-radius: 4px; }
        ::-webkit-scrollbar-thumb:hover { background: rgba(33, 133, 208, 0.3); }

        /* Code syntax formatting overrides */
        pre {
            background: #0a0b10 !important;
            padding: 12px;
            border-radius: 6px;
            border: 1px solid rgba(255,255,255,0.05);
            overflow-x: auto;
        }
        code {
            color: #64b5f6 !important;
            font-family: 'Courier New', Courier, monospace;
        }

        /* ================================================================
           HAMBURGER BUTTON — hidden on desktop
           ================================================================ */
        #mobile-nav-toggle {
            display: none;
            background: none;
            border: 1px solid rgba(255,255,255,0.12);
            color: var(--color-text);
            font-size: 1.3rem;
            padding: 6px 10px;
            border-radius: 6px;
            cursor: pointer;
            position: absolute;
            top: 12px;
            right: 12px;
            z-index: 1001;
        }
        #mobile-nav-toggle:hover { background: rgba(255,255,255,0.05); }

        /* Sidebar overlay backdrop */
        #sidebar-overlay {
            display: none;
            position: fixed;
            inset: 0;
            background: rgba(0,0,0,0.5);
            z-index: 998;
        }

        /* ================================================================
           MOBILE RESPONSIVE — v0.0.1
           ================================================================ */
        @media (max-width: 767px) {
            body { font-size: 14px; overflow-x: hidden; }

            /* Show hamburger, hide it on desktop handled by default */
            #mobile-nav-toggle { display: block !important; }

            .main-grid {
                height: auto !important;
                margin: 0 2px !important;
            }

            /* Sidebar: slide-in overlay from left */
            .ui.grid.main-grid > .three.wide.column {
                position: fixed !important;
                top: 0;
                left: -285px;
                width: 270px !important;
                height: 100vh !important;
                z-index: 999;
                transition: left 0.28s cubic-bezier(0.4, 0, 0.2, 1);
                padding: 12px !important;
                overflow-y: auto;
                background: var(--bg-card);
                border-right: 1px solid var(--border-neon);
                box-shadow: 4px 0 30px rgba(0,0,0,0.6);
            }
            .ui.grid.main-grid > .three.wide.column.open {
                left: 0 !important;
            }

            .ui.vertical.menu.inverted.sidebar-menu {
                height: 100% !important;
                display: flex !important;
                flex-direction: column !important;
                border-right: none !important;
                border-radius: 0 !important;
                background: transparent !important;
            }
            .sidebar-menu .item {
                font-size: 0.9rem !important;
                padding: 12px 14px !important;
                border-left: 3px solid transparent !important;
                border-bottom: none !important;
                text-align: left !important;
            }
            .sidebar-menu .item i.icon { display: inline-block !important; margin-right: 8px !important; font-size: 1rem !important; }
            .sidebar-menu .item.active {
                border-left: 3px solid var(--accent-blue) !important;
                border-bottom: none !important;
            }

            /* Show profile card in slide-out sidebar */
            .sidebar-menu .item[style*="position: absolute"] {
                display: block !important;
                position: relative !important;
                margin-top: auto !important;
                bottom: auto !important;
                left: auto !important;
                right: auto !important;
            }

            /* Right panel full width */
            .ui.grid.main-grid > .thirteen.wide.column {
                width: 100% !important;
                padding: 0 4px !important;
                height: auto !important;
            }

            /* Header: relative for hamburger positioning */
            .premium-card:first-of-type { position: relative !important; padding-right: 50px !important; }
            .premium-card > .ui.grid > .column { width: 100% !important; text-align: left !important; }
            .premium-card > .ui.grid > .six.wide.column { margin-top: 8px !important; }
            .premium-card h2 { font-size: 1.2rem !important; }
            .premium-card .sub.header { font-size: 0.78rem !important; }

            /* Chat */
            .chat-history { max-height: 40vh !important; }
            .chat-bubble { max-width: 95% !important; font-size: 0.88rem !important; padding: 0.7rem !important; }
            .ui.action.input.fluid.big .ui.button { padding: 0.6em 0.8em !important; font-size: 0.85rem !important; }
            #chat-input { font-size: 0.9rem !important; }
            .terminal-panel { height: 120px !important; font-size: 0.7rem !important; }
            .explorer-list { max-height: 30vh !important; border-right: none !important; border-bottom: 1px solid rgba(255,255,255,0.05) !important; margin-bottom: 10px !important; }
            .editor-textarea, .preview-pane { height: 35vh !important; min-height: 200px !important; }
            #editor-preview-container { margin-top: 10px !important; }
            .ui.grid.stackable.three.column > .column { padding: 4px !important; }
            .ui.definition.table { font-size: 0.78rem !important; }
            .premium-card { padding: 0.8rem !important; border-radius: 8px !important; }
            #scratchpad-content { height: 200px !important; font-size: 0.82rem !important; }
        }

        @media (max-width: 400px) {
            .ui.grid.main-grid > .three.wide.column { width: 250px !important; left: -265px; }
            .sidebar-menu .item { font-size: 0.82rem !important; padding: 10px 12px !important; }
            .chat-history { max-height: 35vh !important; }
            .editor-textarea, .preview-pane { height: 28vh !important; }
        }
    </style>
</head>
<body>

    <!-- Header Section -->
    <div class="ui inverted segment padded premium-card" style="margin: 1rem 1.5rem; border-radius: 12px !important; padding: 1em 1.5em !important; position: relative;">
        <button id="mobile-nav-toggle" aria-label="Toggle navigation" title="Menu">
            <i class="bars icon"></i>
        </button>
        <div class="ui grid stackable middle aligned">
            <div class="ten wide column">
                <h2 class="ui header inverted" style="margin: 0;">
                    <i class="server icon blue"></i>
                    <div class="content">
                        <span style="color: var(--accent-blue); text-shadow: 0 0 15px rgba(100, 181, 246, 0.4);"><?= __('title') ?></span>
                        <div class="sub header" style="color: var(--color-text-dim); font-size: 0.95rem; margin-top: 0.3rem;">
                            <span class="pulse-indicator"></span><?= __('subtitle') ?> <span class="ui label tiny black" style="border:1px solid rgba(0,181,173,0.3); color:var(--accent-cyan);"><?= !is_null($f3->get('WEB_VERSION')) ? $f3->get('WEB_VERSION') : 'N/A' ?></span>
                        </div>
                    </div>
                </h2>
            </div>
            <!-- Dynamic Telemetry Badges & Lang Switcher -->
            <div class="six wide column right aligned">
                <div class="ui inverted label black basic" style="border-color: rgba(100, 181, 246, 0.2);">
                    <i class="microchip icon teal" id="telemetry-cpu-icon"></i> <span id="badge-cpu" style="color: var(--color-text);"><?= __('cpu_label') ?>: --%</span>
                </div>
                <div class="ui inverted label black basic" style="border-color: rgba(100, 181, 246, 0.2);">
                    <i class="tasks icon blue" id="telemetry-mem-icon"></i> <span id="badge-mem" style="color: var(--color-text);"><?= __('ram_label') ?>: --%</span>
                </div>
                <div class="ui inverted label black basic" style="border-color: rgba(100, 181, 246, 0.2); display: none;" id="badge-bat-container">
                    <i class="battery half icon green" id="telemetry-bat-icon"></i> <span id="badge-bat" style="color: var(--color-text);"><?= __('bat_label') ?>: --%</span>
                </div>

                <!-- Premium Language Selector Buttons -->
                <div class="ui mini buttons inverted" style="margin-left: 10px; margin-top: 10px; border: 1px solid rgba(255,255,255,0.08);">
                    <a href="?lang=en" class="ui button mini <?= $f3->get('ACTIVE_LANG') === 'en' ? 'active teal' : 'black' ?>">EN</a>
                    <a href="?lang=fr" class="ui button mini <?= $f3->get('ACTIVE_LANG') === 'fr' ? 'active teal' : 'black' ?>">FR</a>
                </div>
            </div>
        </div>
    </div>

    <!-- Sidebar overlay backdrop (mobile only) -->
    <div id="sidebar-overlay"></div>

    <!-- Main Workspace Container -->
    <div class="ui grid main-grid" style="margin: 0 10px !important;">
        <!-- Left Sidebar Navigation -->
        <div class="three wide column" style="padding-top: 0; padding-bottom: 0;">
            <div class="ui vertical menu inverted sidebar-menu fluid">
                <a class="item active" data-tab="tab-chat">
                    <i class="comments outline icon"></i> <?= __('tab_chat') ?>
                </a>
                <a class="item" data-tab="tab-memory">
                    <i class="brain icon"></i> <?= __('tab_memory') ?>
                </a>
                <a class="item" data-tab="tab-telemetry">
                    <i class="chart area icon"></i> <?= __('tab_telemetry') ?>
                </a>
                <a class="item" data-tab="tab-ingestion">
                    <i class="folder open outline icon"></i> <?= __('tab_scratchpad') ?>
                </a>

                <!-- Active AI Profile Status -->
                <div class="item" style="position: absolute; bottom: 10px; left: 0; right: 0; margin: 0 10px; background: rgba(0,0,0,0.2); border-radius: 8px; padding: 10px;">
                    <div style="font-size: 0.8rem; color: var(--color-text-dim); text-transform: uppercase; margin-bottom: 5px;"><?= __('active_engine_profile') ?></div>
                    <div style="font-size: 0.85rem; margin-top: 5px; color: var(--color-text);" id="sidebar-backend"><?= __('backend_label') ?>: ...</div>
                    <div style="font-size: 0.85rem; margin-top: 5px; color: var(--color-text);" id="sidebar-provider"><?= __('provider_label') ?>: ...</div>
                    <div style="font-size: 0.85rem; margin-top: 5px; color: var(--color-text);"><?= __('model_label') ?>: <span style="font-weight: bold; color: var(--accent-cyan); word-break: break-all;" id="sidebar-model">...</span></div>
                    <div style="font-size: 0.8rem; margin-top: 5px; color: #2ecc71; display: none;" id="sidebar-credits-container">
                        <?= __('credits_label') ?>: <span id="sidebar-credits" style="font-weight: bold;">--</span>
                    </div>
                </div>
            </div>
        </div>

        <!-- Right Panels (Tabs) -->
        <div class="thirteen wide column" style="padding-top: 0; padding-bottom: 0; height: 100%;">
            <div class="ui inverted segment premium-card" style="height: 100%; padding: 1.5rem !important;">

                <!-- =================================================================== -->
                <!-- TAB 1: COCKPIT INTERACTIVE CHAT -->
                <!-- =================================================================== -->
                <div class="ui tab active chat-container" data-tab="tab-chat" style="height: 100%;">
                    <div class="chat-history" id="chat-history">
                        <!-- Default greeting greeting -->
                        <div class="chat-bubble assistant">
                            <strong>Jarvis:</strong> <?= __('welcome_message') ?>
                        </div>
                    </div>

                    <!-- Chat Input and Controls -->
                    <div class="ui form">
                        <div class="ui action input fluid big" style="background: transparent;">
                            <input type="text" id="chat-input" placeholder="<?= __('chat_placeholder') ?>" style="background: var(--bg-input); color: var(--color-text); border: 1px solid rgba(255,255,255,0.08); border-radius: 8px 0 0 8px;">
                            <button class="ui button teal" id="btn-send-chat" style="border-radius: 0 8px 8px 0;"><i class="paper plane icon"></i> <?= __('chat_send') ?></button>
                        </div>
                    </div>

                    <!-- Real-Time Unix Output Monitor (The terminal stream bridge output) -->
                    <div class="terminal-panel" id="terminal-monitor">
                        <div><?= __('terminal_waiting') ?></div>
                    </div>
                </div>

                <!-- =================================================================== -->
                <!-- TAB 2: COGNITIVE FREEDOM MEMORY EXPLORER -->
                <!-- =================================================================== -->
                <div class="ui tab" data-tab="tab-memory" style="height: 100%;">
                    <div class="ui grid stackable" style="height: 100%;">
                        <!-- Left pane: Memory Files Index -->
                        <div class="four wide column explorer-list" id="memory-files-list">
                            <h4 class="ui header inverted teal" style="margin-bottom: 10px;">
                                <i class="brain icon"></i> <?= __('memory_core') ?>
                            </h4>
                            <div class="ui selection list inverted relaxed" id="memory-group-list">
                                <!-- Prepopulated with beautiful Fomantic Skeletal Placeholder list during loading -->
                                <div class="ui placeholder inverted" id="memory-skeleton-loader" style="padding: 10px;">
                                    <div class="line"></div>
                                    <div class="line"></div>
                                    <div class="line"></div>
                                    <div class="line"></div>
                                </div>
                            </div>
                        </div>

                        <!-- Right pane: Markdown File Editor -->
                        <div class="twelve wide column" style="display: flex; flex-direction: column;">
                            <div class="ui grid middle aligned stackable" style="margin-bottom: 10px;">
                                <div class="eight wide column">
                                    <!-- Breadcrumb navigation replaces the flat heading -->
                                    <div class="ui breadcrumb inverted" id="editor-active-file-title" style="font-size: 1.1rem; vertical-align: middle;">
                                        <div class="active section" style="color: var(--color-text-dim); font-style: italic;"><?= __('editor_select_file') ?></div>
                                    </div>
                                </div>
                                <div class="eight wide column right aligned">
                                    <button class="ui button inverted blue basic small" id="btn-commit-memory" disabled>
                                        <i class="save icon"></i> <?= __('editor_commit_btn') ?>
                                    </button>
                                </div>
                            </div>

                            <div class="ui grid stackable">
                                <div class="row">
                                    <!-- Editor Source Panel -->
                                    <div class="eight wide column" id="editor-textarea-container">
                                        <div style="font-size:0.8rem; color:var(--color-text-dim); text-transform:uppercase; margin-bottom:5px;"><?= __('editor_source_title') ?></div>
                                        <textarea class="editor-textarea" id="editor-content" disabled></textarea>
                                    </div>
                                    <!-- Editor Live Preview Panel -->
                                    <div class="eight wide column" id="editor-preview-container">
                                        <div style="font-size:0.8rem; color:var(--color-text-dim); text-transform:uppercase; margin-bottom:5px;"><?= __('editor_preview_title') ?></div>
                                        <div class="preview-pane" id="editor-preview">
                                            <p style="color:var(--color-text-dim); font-style:italic;"><?= __('editor_no_file') ?></p>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- =================================================================== -->
                <!-- TAB 3: SYSTEM TELEMETRY HUD -->
                <!-- =================================================================== -->
                <div class="ui tab" data-tab="tab-telemetry">
                    <h3 class="ui dividing header inverted teal">
                        <i class="chart area icon"></i> <?= __('telemetry_title') ?>
                    </h3>

                    <div class="ui grid stackable three column">
                        <!-- Column 1: CPU Metrics -->
                        <div class="column">
                            <div class="ui segment inverted black" style="background: rgba(0,0,0,0.2) !important; border: 1px solid rgba(255,255,255,0.05);">
                                <h4 class="ui header inverted teal"><i class="microchip icon"></i> <?= __('telemetry_cpu_title') ?></h4>
                                <div class="ui divider"></div>
                                <!-- Upgraded to modern UI Definition Table -->
                                <table class="ui celled definition table inverted compact">
                                    <tbody>
                                        <tr>
                                            <td class="collapsing">CPU Load (1m)</td>
                                            <td id="hud-cpu-load-1">--</td>
                                        </tr>
                                        <tr>
                                            <td class="collapsing">CPU Load (5m)</td>
                                            <td id="hud-cpu-load-5">--</td>
                                        </tr>
                                        <tr>
                                            <td class="collapsing">CPU Load (15m)</td>
                                            <td id="hud-cpu-load-15">--</td>
                                        </tr>
                                        <tr>
                                            <td class="collapsing">Total Cores</td>
                                            <td id="hud-cpu-cores">--</td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                        </div>

                        <!-- Column 2: Memory Metrics -->
                        <div class="column">
                            <div class="ui segment inverted black" style="background: rgba(0,0,0,0.2) !important; border: 1px solid rgba(255,255,255,0.05);">
                                <h4 class="ui header inverted blue"><i class="tasks icon"></i> <?= __('telemetry_ram_title') ?></h4>
                                <div class="ui divider"></div>
                                <div class="ui progress inverted blue tiny" id="progress-ram">
                                    <div class="bar"></div>
                                    <div class="label" style="color:var(--color-text-dim) !important;"><?= __('telemetry_ram_label') ?></div>
                                </div>
                                <table class="ui celled definition table inverted compact">
                                    <tbody>
                                        <tr>
                                            <td class="collapsing">Total Memory</td>
                                            <td id="hud-ram-total">-- MB</td>
                                        </tr>
                                        <tr>
                                            <td class="collapsing">Used Memory</td>
                                            <td id="hud-ram-used">-- MB</td>
                                        </tr>
                                        <tr>
                                            <td class="collapsing">Available Free</td>
                                            <td id="hud-ram-free">-- MB</td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                        </div>

                        <!-- Column 3: Platform Metrics -->
                        <div class="column">
                            <div class="ui segment inverted black" style="background: rgba(0,0,0,0.2) !important; border: 1px solid rgba(255,255,255,0.05);">
                                <h4 class="ui header inverted orange"><i class="info circle icon"></i> <?= __('telemetry_os_title') ?></h4>
                                <div class="ui divider"></div>
                                <table class="ui celled definition table inverted compact">
                                    <tbody>
                                        <tr>
                                            <td class="collapsing">System OS</td>
                                            <td id="hud-os-name">--</td>
                                        </tr>
                                        <tr>
                                            <td class="collapsing">Family Platform</td>
                                            <td id="hud-os-family">--</td>
                                        </tr>
                                        <tr>
                                            <td class="collapsing">Kernel Build</td>
                                            <td id="hud-os-version" style="font-size:0.8rem; word-break:break-all;">--</td>
                                        </tr>
                                        <tr>
                                            <td class="collapsing">Tor Proxy Tunnel</td>
                                            <td id="hud-tor-status">Disconnected</td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- =================================================================== -->
                <!-- TAB 4: SCRATCHPAD & COGNITIVE INGESTION -->
                <!-- =================================================================== -->
                <div class="ui tab" data-tab="tab-ingestion">
                    <h3 class="ui dividing header inverted teal">
                        <i class="folder open outline icon"></i> <?= __('scratchpad_title') ?>
                    </h3>
                    <p style="color:var(--color-text-dim);">
                        <?= __('scratchpad_description') ?>
                    </p>

                    <div class="ui form">
                        <div class="field">
                            <label style="color: var(--accent-blue); font-size: 1rem;"><?= __('scratchpad_label') ?></label>
                            <textarea id="scratchpad-content" style="background:#111420; color:#d1d5db; font-family:'Courier New', Courier, monospace; height:320px;" placeholder="<?= __('scratchpad_placeholder') ?>"></textarea>
                        </div>
                        <button class="ui button inverted blue basic" id="btn-scratchpad-clear">
                            <i class="trash icon"></i> <?= __('scratchpad_clear_btn') ?>
                        </button>
                    </div>
                </div>

            </div>
        </div>
    </div>

    <!-- Foot page copyright disclaimer -->
    <div style="color: #5a6578; font-size: 0.85rem; text-align: center; padding: 1.5rem 0; margin-top: auto;">
        <?= __('footer_disclaimer') ?>
    </div>

    <!-- Script dependencies imports -->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js" integrity="sha512-v2CJ7UaYy4JwqLDIrZUI/4hqeoQieOmAZNXBeQyjo21dadnwR+8ZaIJVT8EE2iyI61OV8e6M8PP2/4hpQINQ/g==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/fomantic-ui/2.9.4/semantic.min.js" integrity="sha512-Y/wIVu+S+XJsDL7I+nL50kAVFLMqSdvuLqF2vMoRqiMkmvcqFjEpEgeu6Rx8tpZXKp77J8OUpMKy0m3jLYhbbw==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
    <!-- Marked.js for fast Markdown Rendering -->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/marked/16.3.0/lib/marked.umd.min.js" integrity="sha512-V6rGY7jjOEUc7q5Ews8mMlretz1Vn2wLdMW/qgABLWunzsLfluM0FwHuGjGQ1lc8jO5vGpGIGFE+rTzB+63HdA==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>

    <script>
        $(document).ready(function() {
            // Initialize Tabs Navigation
            $('.sidebar-menu .item').tab({
                onVisible: function(tabPath) {
                    if (tabPath === 'tab-memory') {
                        loadMemoryCoreIndex();
                    } else if (tabPath === 'tab-telemetry') {
                        refreshTelemetryHUD();
                    }
                }
            });

            // =================================================================
            // MOBILE HAMBURGER MENU TOGGLE
            // =================================================================
            const $sidebar = $('.ui.grid.main-grid > .three.wide.column');
            const $overlay = $('#sidebar-overlay');
            const $toggle = $('#mobile-nav-toggle');

            function openSidebar() {
                $sidebar.addClass('open');
                $overlay.fadeIn(200);
                $toggle.find('i').removeClass('bars').addClass('times');
            }
            function closeSidebar() {
                $sidebar.removeClass('open');
                $overlay.fadeOut(200);
                $toggle.find('i').removeClass('times').addClass('bars');
            }

            $toggle.on('click', function(e) {
                e.stopPropagation();
                $sidebar.hasClass('open') ? closeSidebar() : openSidebar();
            });

            $overlay.on('click', closeSidebar);

            // Close sidebar when a tab is clicked (mobile)
            $sidebar.find('.item[data-tab]').on('click', function() {
                if ($(window).width() <= 767) {
                    closeSidebar();
                }
            });

            // Global State Store
            let activeMemoryPath = '';
            let telemetryInterval = null;

            // Simple Javascript ANSI to HTML conversion engine
            function ansiToHtml(text) {
                const ansiMap = {
                    '0': 'font-weight: normal; color: var(--color-text);',
                    '1': 'font-weight: bold;',
                    '30': 'color: #1e293b;',
                    '31': 'color: #f87171;',
                    '32': 'color: #4ade80;',
                    '33': 'color: #facc15;',
                    '34': 'color: #60a5fa;',
                    '35': 'color: #c084fc;',
                    '36': 'color: #2dd4bf;',
                    '37': 'color: #f1f5f9;',
                    '90': 'color: #64748b;',
                    '30;1': 'color: #475569; font-weight: bold;',
                    '31;1': 'color: #ef4444; font-weight: bold;',
                    '32;1': 'color: #22c55e; font-weight: bold;',
                    '33;1': 'color: #eab308; font-weight: bold;',
                    '34;1': 'color: #3b82f6; font-weight: bold;',
                    '35;1': 'color: #a855f7; font-weight: bold;',
                    '36;1': 'color: #0d9488; font-weight: bold;',
                    '37;1': 'color: #cbd5e1; font-weight: bold;'
                };

                // Remove cursor controls and reset codes
                text = text.replace(/\x1B\[\d*[A-D]/g, '');
                text = text.replace(/\x1B\[\d*[KJK]/g, '');

                let matches = text.match(/\x1B\[[0-9;]+m/g);
                if (!matches) return text;

                let openSpans = 0;
                matches.forEach(match => {
                    let code = match.substring(2, match.length - 1);
                    if (code === '0') {
                        // Close all open spans
                        let closeTags = '';
                        for (let i = 0; i < openSpans; i++) {
                            closeTags += '</span>';
                        }
                        text = text.replace(match, closeTags);
                        openSpans = 0;
                    } else if (ansiMap[code]) {
                        text = text.replace(match, `<span style="${ansiMap[code]}">`);
                        openSpans++;
                    } else {
                        text = text.replace(match, '');
                    }
                });

                // Safely close remaining open spans
                for (let i = 0; i < openSpans; i++) {
                    text += '</span>';
                }
                return text;
            }

            // =================================================================
            // CHAT HANDLERS (OPTION C BRIDGE)
            // =================================================================

            function sendChatMessage() {
                const query = $('#chat-input').val().trim();
                if (!query) return;

                // Disable UI elements during stream
                $('#chat-input').val('').prop('disabled', true);
                $('#btn-send-chat').addClass('loading').prop('disabled', true);

                // Add User message bubble with slide down transition
                const userBubble = $(`
                    <div class="chat-bubble user" style="display: none;">
                        <strong>User:</strong> ${escapeHtml(query)}
                    </div>
                `);
                $('#chat-history').append(userBubble);
                userBubble.transition('slide down in', '300ms');
                scrollChatToBottom();

                // Prepare Assistant streaming placeholder
                const assistantId = 'assistant-' + Date.now();
                const assistantBubble = $(`
                    <div class="chat-bubble assistant" id="${assistantId}" style="display: none;">
                        <strong>Jarvis:</strong> <span class="ui active inline loader tiny"></span> Thinking...
                    </div>
                `);
                $('#chat-history').append(assistantBubble);
                assistantBubble.transition('slide down in', '300ms');
                scrollChatToBottom();

                // Clear and reset the Unix Monitor Console
                $('#terminal-monitor').html('<div>[SYSTEM] Unix Pipe Stream Bridge opened. Stream flowing...</div>');

                // Initialize SSE connection to stream pipeline response
                const streamUrl = 'api/chat/stream?q=' + encodeURIComponent(query);
                const eventSource = new EventSource(streamUrl);

                let answerBuffer = '';
                let isThinking = true;

                eventSource.onmessage = function(event) {
                    const data = JSON.parse(event.data);

                    if (data.type === 'stdout') {
                        // Append raw Unix output to Console monitor
                        const parsedLine = ansiToHtml(data.text);
                        $('#terminal-monitor').append(`<div>${parsedLine}</div>`);
                        scrollTerminalToBottom();

                        // Detect AI answers and append to chat bubble
                        const cleanText = data.text.replace(/\x1B\[[0-9;]*[a-zA-Z]/g, '');

                        // Ignore system headers or logs in assistant bubble, concentrate on answer
                        if (cleanText.includes('🤖 Jarvis ❯') || cleanText.includes('[AI ANSWER]')) {
                            isThinking = false;
                            $(`#${assistantId}`).html('<strong>Jarvis:</strong> ');
                        }

                        if (!isThinking && !cleanText.startsWith('🤖') && !cleanText.startsWith('[') && !cleanText.includes('❯')) {
                            answerBuffer += cleanText;
                            const renderedHtml = marked.parse(answerBuffer);
                            $(`#${assistantId}`).html(`<strong>Jarvis:</strong> ${renderedHtml}`);
                            scrollChatToBottom();
                        }
                    } else if (data.type === 'stderr') {
                        // Append warning/error logs to monitor console
                        const parsedLine = ansiToHtml(data.text);
                        $('#terminal-monitor').append(`<div style="color: #ef4444 !important;">${parsedLine}</div>`);
                        scrollTerminalToBottom();
                    } else if (data.type === 'done') {
                        eventSource.close();

                        // Re-enable input controls
                        $('#chat-input').prop('disabled', false).focus();
                        $('#btn-send-chat').removeClass('loading').prop('disabled', false);

                        // If answer buffer was empty, fallback to display full terminal output
                        if (isThinking) {
                            $(`#${assistantId}`).html(`<strong>Jarvis:</strong> Command executed. See Unix output log console below for complete diagnostics.`);
                        }

                        // Auto refresh credits and metrics after call
                        updateGlobalTelemetry();
                    } else if (data.type === 'error') {
                        eventSource.close();
                        $('#chat-input').prop('disabled', false);
                        $('#btn-send-chat').removeClass('loading').prop('disabled', false);
                        $(`#${assistantId}`).html(`<strong>Jarvis:</strong> <span style="color:#ef4444;">System Error occurred while running pipeline.</span>`);

                        $('body').toast({
                            class: 'error',
                            message: 'System Error occurred while running pipeline subprocess.',
                            position: 'bottom right'
                        });
                    }
                };

                eventSource.onerror = function() {
                    eventSource.close();
                    $('#chat-input').prop('disabled', false);
                    $('#btn-send-chat').removeClass('loading').prop('disabled', false);
                    updateGlobalTelemetry();
                };
            }

            // Keyboard and Send Button binds
            $('#chat-input').keypress(function(e) {
                if (e.which === 13) {
                    sendChatMessage();
                }
            });
            $('#btn-send-chat').click(sendChatMessage);

            // Helpers
            function scrollChatToBottom() {
                const ch = document.getElementById('chat-history');
                ch.scrollTop = ch.scrollHeight;
            }
            function scrollTerminalToBottom() {
                const tm = document.getElementById('terminal-monitor');
                tm.scrollTop = tm.scrollHeight;
            }
            function escapeHtml(text) {
                return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
            }


            // =================================================================
            // COGNITIVE CORE FILE EXPLORER HANDLERS
            // =================================================================

            function loadMemoryCoreIndex() {
                // Show beautiful skeleton placeholder while scanning memory files
                $('#memory-group-list').html(`
                    <div class="ui placeholder inverted" style="padding: 10px; background: transparent;">
                        <div class="line"></div>
                        <div class="line"></div>
                        <div class="line"></div>
                        <div class="line"></div>
                    </div>
                `);

                $.getJSON('api/memory', function(data) {
                    const listContainer = $('#memory-group-list');
                    listContainer.empty();

                    if (!data.files || data.files.length === 0) {
                        listContainer.append('<div class="item">No memory core files found.</div>');
                        return;
                    }

                    // Sort files by group, then name
                    data.files.sort((a, b) => a.group.localeCompare(b.group) || a.name.localeCompare(b.name));

                    let currentGroup = '';
                    data.files.forEach(file => {
                        if (file.group !== currentGroup) {
                            currentGroup = file.group;
                            listContainer.append(`
                                <div class="header" style="color:var(--accent-cyan); text-transform:uppercase; font-size:0.8rem; margin:10px 0 5px 0;">
                                    <i class="folder open outline icon"></i> ${currentGroup}
                                </div>
                            `);
                        }

                        const itemSize = (file.size / 1024).toFixed(1) + ' KB';
                        listContainer.append(`
                            <div class="item explorer-item" data-path="${file.path}">
                                <i class="file alternate outline icon grey middle aligned" style="padding-top:4px;"></i>
                                <div class="content">
                                    <div class="header file-title-name" style="color:var(--accent-blue); font-weight:bold; font-size:0.9rem;">${file.name}</div>
                                    <div class="description" style="font-size:0.75rem; color:var(--color-text-dim); margin-top:2px;">Size: ${itemSize}</div>
                                </div>
                            </div>
                        `);
                    });

                    // Set click list bindings
                    $('.explorer-item').click(function() {
                        $('.explorer-item').removeClass('active');
                        $(this).addClass('active');
                        loadMemoryFileContent($(this).attr('data-path'));
                    });
                });
            }

            function loadMemoryFileContent(path) {
                activeMemoryPath = path;
                const filename = path.split('/').pop();
                const groupName = path.includes('skills') ? 'Skills' : 'Memory';

                // Set Breadcrumb loading state
                $('#editor-active-file-title').html(`
                    <span class="section" style="color:var(--color-text-dim);">Workspace</span>
                    <i class="right chevron icon divider" style="color:var(--border-neon); margin: 0 0.5rem;"></i>
                    <span class="section" style="color:var(--color-text-dim);">${groupName}</span>
                    <i class="right chevron icon divider" style="color:var(--border-neon); margin: 0 0.5rem;"></i>
                    <div class="active section" style="color:var(--accent-blue); font-weight:bold;">
                        <span class="ui active inline loader tiny" style="margin-right: 5px;"></span> ${filename}
                    </div>
                `);

                // Instatiate visual skeleton preview cards while loading content
                $('#editor-preview').html(`
                    <div class="ui placeholder inverted" style="background: transparent;">
                        <div class="header">
                            <div class="line"></div>
                            <div class="line"></div>
                        </div>
                        <div class="paragraph">
                            <div class="line"></div>
                            <div class="line"></div>
                            <div class="line"></div>
                        </div>
                    </div>
                `);

                $.getJSON('api/memory/content', { path: path }, function(data) {
                    if (data.error) {
                        $('#editor-active-file-title').html(`<span style="color:#ef4444;">Error: ${data.error}</span>`);
                        return;
                    }

                    // Complete full Breadcrumb path render
                    $('#editor-active-file-title').html(`
                        <span class="section" style="color:var(--color-text-dim);">Workspace</span>
                        <i class="right chevron icon divider" style="color:var(--border-neon); margin: 0 0.5rem;"></i>
                        <span class="section" style="color:var(--color-text-dim);">${groupName}</span>
                        <i class="right chevron icon divider" style="color:var(--border-neon); margin: 0 0.5rem;"></i>
                        <div class="active section" style="color:var(--accent-blue); font-weight:bold;">${filename}</div>
                    `);

                    $('#editor-content').val(data.content).prop('disabled', false);
                    $('#btn-commit-memory').prop('disabled', false);
                    renderEditorPreview(data.content);
                });
            }

            // Real-Time markdown renderer input trigger bind
            $('#editor-content').on('input', function() {
                renderEditorPreview($(this).val());
            });

            function renderEditorPreview(markdown) {
                const rendered = marked.parse(markdown);
                $('#editor-preview').html(rendered);
            }

            // Save edited content route save action bind using Fomantic Toasts
            $('#btn-commit-memory').click(function() {
                if (!activeMemoryPath) return;

                const content = $('#editor-content').val();
                const $btn = $(this);
                $btn.addClass('loading').prop('disabled', true);

                $.ajax({
                    url: 'api/memory/save',
                    type: 'POST',
                    contentType: 'application/json',
                    data: JSON.stringify({
                        path: activeMemoryPath,
                        content: content
                    }),
                    success: function(res) {
                        $btn.removeClass('loading').prop('disabled', false);
                        if (res.success) {
                            // Flash premium sémantique inline success label inside breadcrumb
                            $('#editor-active-file-title').append(' <span class="ui label tiny green animated flash" style="vertical-align: middle;"><i class="check icon"></i> Saved</span>');
                            setTimeout(() => {
                                $('#editor-active-file-title').find('.label').fadeOut(400, function() { $(this).remove(); });
                            }, 2000);

                            // Emit a premium floating FUI Toast notification
                            $('body').toast({
                                class: 'success',
                                title: 'Commit Successful',
                                message: `Successfully persisted changes to ${activeMemoryPath}`,
                                showProgress: 'bottom',
                                position: 'bottom right'
                            });

                            loadMemoryCoreIndex(); // reload sizes
                        } else {
                            $('body').toast({
                                class: 'error',
                                title: 'Save Failed',
                                message: res.error,
                                position: 'bottom right'
                            });
                        }
                    },
                    error: function() {
                        $btn.removeClass('loading').prop('disabled', false);
                        $('body').toast({
                            class: 'error',
                            title: 'Network Error',
                            message: 'Could not connect to backend server for writing files.',
                            position: 'bottom right'
                        });
                    }
                });
            });


            // =================================================================
            // TELEMETRY HUD & BADGES ENGINE
            // =================================================================

            function updateGlobalTelemetry() {
                $.getJSON('api/telemetry', function(data) {
                    console.group('Telemetry');
                    console.log(data);
                    console.groupEnd();

                    // Update global UI labels
                    $('#badge-cpu').text('<?= __("cpu_label") ?>: ' + (data.cpu.load[0] * 10).toFixed(0) + '%');
                    $('#badge-mem').text('<?= __("ram_label") ?>: ' + data.memory.percentage + '%');

                    if (data.battery && data.battery.percentage) {
                        $('#badge-bat-container').show();
                        $('#badge-bat').text('<?= __("bat_label") ?>: ' + data.battery.percentage + '% (' + data.battery.status + ')');
                        $('#telemetry-bat-icon').removeClass('empty low quarter half three full red orange yellow olive green');
                        if (data.battery.percentage < 10) {
                            $('#telemetry-bat-icon')
                                .addClass('empty')
                                .addClass('red');
                        }
                        else if (data.battery.percentage < 20) {
                            $('#telemetry-bat-icon')
                                .addClass('low')
                                .addClass('red');
                        }
                        else if (data.battery.percentage < 40) {
                            $('#telemetry-bat-icon')
                                .addClass('quarter')
                                .addClass('orange');
                        }
                        else if (data.battery.percentage < 60) {
                            $('#telemetry-bat-icon')
                                .addClass('half')
                                .addClass('yellow');
                        }
                        else if (data.battery.percentage < 80) {
                            $('#telemetry-bat-icon')
                                .addClass('three')
                                .addClass('olive');
                        }
                        else if (data.battery.percentage >= 80) {
                            $('#telemetry-bat-icon')
                                .addClass('full')
                                .addClass('green');
                        }
                    } else {
                        $('#badge-bat-container').hide();
                    }

                    // Sidebar AI Profile Card
                    $('#sidebar-backend').text('<?= __("backend_label") ?>: ' + data.ai.backend.toUpperCase());
                    $('#sidebar-provider').text('<?= __("provider_label") ?>: ' + data.ai.provider.toUpperCase());
                    $('#sidebar-model').text(data.ai.model);

                    if (data.ai.credits !== null) {
                        $('#sidebar-credits-container').show();
                        $('#sidebar-credits').text('$' + parseFloat(data.ai.credits).toFixed(4));
                    } else {
                        $('#sidebar-credits-container').hide();
                    }
                });
            }

            function refreshTelemetryHUD() {
                $.getJSON('api/telemetry', function(data) {
                    // CPU UI Details
                    $('#hud-cpu-load-1').text(parseFloat(data.cpu.load[0]).toFixed(2));
                    $('#hud-cpu-load-5').text(parseFloat(data.cpu.load[1]).toFixed(2));
                    $('#hud-cpu-load-15').text(parseFloat(data.cpu.load[2]).toFixed(2));
                    $('#hud-cpu-cores').text(data.cpu.cores + ' Cores');

                    // RAM UI Details (Upgraded to Fomantic standard progress API initialization)
                    $('#progress-ram').progress({
                        percent: data.memory.percentage,
                        text: {
                            active  : '{percent}% Used',
                            success : 'RAM Available'
                        }
                    });

                    $('#hud-ram-total').text((data.memory.total / (1024 * 1024)).toFixed(0) + ' MB');
                    $('#hud-ram-used').text((data.memory.used / (1024 * 1024)).toFixed(0) + ' MB');
                    $('#hud-ram-free').text((data.memory.free / (1024 * 1024)).toFixed(0) + ' MB');

                    // OS UI Details
                    $('#hud-os-name').text(data.os.name);
                    $('#hud-os-family').text(data.os.family);
                    $('#hud-os-version').text(data.os.version);

                    // Tor UI Status
                    if (data.ai.tor) {
                        $('#hud-tor-status').html('<span style="color:#2ecc71; font-weight:bold;"><i class="shield alternate icon"></i> <?= __("telemetry_tor_active") ?></span>');
                    } else {
                        $('#hud-tor-status').html('<span style="color:#f2711c;"><i class="warning sign icon"></i> <?= __("telemetry_tor_inactive") ?></span>');
                    }
                });
            }

            // Active poll telemetry on 5-seconds interval loop
            updateGlobalTelemetry();
            telemetryInterval = setInterval(updateGlobalTelemetry, 5000);


            // =================================================================
            // SCRATCHPAD AUTO-STORAGE & CONFIRMATIONS USING TOAST ACTIONS
            // =================================================================

            const localScratchKey = 'jwcc_scratchpad';
            if (localStorage.getItem(localScratchKey)) {
                $('#scratchpad-content').val(localStorage.getItem(localScratchKey));
            }

            $('#scratchpad-content').on('input', function() {
                localStorage.setItem(localScratchKey, $(this).val());
            });

            $('#btn-scratchpad-clear').click(function() {
                // Instanciate beautiful FUI dynamic toast modal confirmation
                $('body').toast({
                    class: 'warning',
                    title: 'Clear Scratchpad?',
                    message: '<?= __("scratchpad_confirm_clear") ?>',
                    displayTime: 0, // Wait for user interaction
                    closeIcon: true,
                    position: 'top center',
                    actions: [
                        {
                            text: 'Clear',
                            class: 'red',
                            click: function() {
                                $('#scratchpad-content').val('');
                                localStorage.removeItem(localScratchKey);
                                $('body').toast({
                                    class: 'info',
                                    message: 'Scratchpad cleared.',
                                    showProgress: 'bottom'
                                });
                            }
                        },
                        {
                            text: 'Cancel',
                            class: 'black'
                        }
                    ]
                });
            });

        });
    </script>
</body>
</html>
<?php
});

// Run F3 App routing sequence
$f3->run();
