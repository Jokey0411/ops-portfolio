<?php
/**
 * LNMP 环境验证页（含 Redis 缓存 + Session 共享）
 *
 * 设计要点：
 *  1. cache-aside：先查 Redis，未命中回源 MySQL，再写回缓存（TTL 60s）
 *  2. 缓存不可用时**降级**：Redis 连不上就直连 MySQL，页面照常打开
 *     —— 缓存是性能组件，不该成为可用性的单点
 *  3. session 存 Redis：多个 php 副本共享同一份会话，不依赖负载均衡的会话粘滞
 */
declare(strict_types=1);

header('Content-Type: text/html; charset=utf-8');

$dbHost = getenv('DB_HOST') ?: 'mysql';
$dbName = getenv('DB_NAME') ?: 'shop';
$dbUser = getenv('DB_USER') ?: 'app';
$dbPass = getenv('DB_PASS') ?: 'App@123456';
$rdHost = getenv('REDIS_HOST') ?: 'redis';
$rdPort = (int)(getenv('REDIS_PORT') ?: 6379);

$start = microtime(true);

// ---------------- 1. Session（存 Redis） ----------------
$sess = ['ok' => false, 'id' => '-', 'visits' => 0, 'err' => ''];
try {
    if (session_status() === PHP_SESSION_NONE) {
        // ★ 前面加 @ 抑制警告：Redis 挂掉时 session_start() 会抛 E_WARNING
        //   （display_errors=On 会把它打到页面最上面，看起来像页面坏了）。
        //   我们要的是「降级后照常显示」，不是「把 PHP 警告糊在用户脸上」。
        @session_start();
    }
    if (session_status() === PHP_SESSION_ACTIVE) {
        $_SESSION['visits'] = ($_SESSION['visits'] ?? 0) + 1;
        $sess = ['ok' => true, 'id' => substr(session_id(), 0, 8), 'visits' => $_SESSION['visits'], 'err' => ''];
    } else {
        $sess['err'] = '会话未建立（Redis 不可用，已降级）';
    }
} catch (Throwable $e) {
    $sess['err'] = $e->getMessage();
}

// ---------------- 2. 连接 Redis（失败即降级，不阻断页面） ----------------
$redis = null;
$rdErr = '';
$rdMs  = 0.0;
$t0 = microtime(true);
try {
    $redis = new Redis();
    // 0.5s 超时：Redis 卡住时不能把整个页面拖死
    if (!$redis->connect($rdHost, $rdPort, 0.5)) {
        throw new RuntimeException('connect timeout');
    }
    $redis->setOption(Redis::OPT_READ_TIMEOUT, 0.5);
    $redis->ping();
} catch (Throwable $e) {
    $redis = null;
    $rdErr = $e->getMessage();
}
$rdMs = round((microtime(true) - $t0) * 1000, 2);

$cacheKey = 'lnmp:stats:v1';
$cacheTtl = 60;
$cache    = 'off';        // off | hit | miss | bypass
$statsMs  = 0.0;
$stats    = null;
$error    = null;

// 手动清缓存：?flush=1
if ($redis && isset($_GET['flush'])) {
    try { $redis->del($cacheKey); } catch (Throwable $e) {}
}

// ---------------- 3. 先读缓存 ----------------
if ($redis && !isset($_GET['nocache'])) {
    $t0 = microtime(true);
    try {
        $cached = $redis->get($cacheKey);
        if (is_string($cached)) {
            $decoded = json_decode($cached, true);
            if (is_array($decoded)) {
                $stats = $decoded;
                $cache = 'hit';
            }
        }
    } catch (Throwable $e) {
        $redis = null;
        $rdErr = $e->getMessage();
    }
    $statsMs = round((microtime(true) - $t0) * 1000, 2);
}

// ---------------- 4. 未命中则回源 MySQL ----------------
$pdo = null;
if ($stats === null || isset($_GET['q'])) {
    try {
        $t0 = microtime(true);
        $pdo = new PDO(
            "mysql:host={$dbHost};dbname={$dbName};charset=utf8mb4",
            $dbUser, $dbPass,
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_TIMEOUT => 5]
        );

        if ($stats === null) {
            $stats = [
                'mysql_version' => $pdo->query('SELECT VERSION()')->fetchColumn(),
                'orders_count'  => (int)$pdo->query('SELECT COUNT(*) FROM orders')->fetchColumn(),
                'users_count'   => (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn(),
                'items_count'   => (int)$pdo->query('SELECT COUNT(*) FROM order_items')->fetchColumn(),
            ];
            $statsMs = round((microtime(true) - $t0) * 1000, 2);
            $cache = $redis ? (isset($_GET['nocache']) ? 'bypass' : 'miss') : 'off';

            if ($redis) {
                try { $redis->setex($cacheKey, $cacheTtl, json_encode($stats)); } catch (Throwable $e) {}
            }
        }
    } catch (Throwable $e) {
        $error = $e->getMessage();
    }
}

// ---------------- 5. 演示查询（走索引） ----------------
$query = null;
if (isset($_GET['q']) && $pdo) {
    try {
        $t0 = microtime(true);
        $stmt = $pdo->prepare(
            "SELECT id, user_id, amount, status, created_at FROM orders
             WHERE user_id = ? AND status = 'paid' ORDER BY created_at DESC LIMIT 20"
        );
        $stmt->execute([(int)($_GET['q'] ?: 100)]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $query = ['rows' => count($rows), 'cost_ms' => round((microtime(true) - $t0) * 1000, 2)];
    } catch (Throwable $e) {
        $error = $e->getMessage();
    }
}

$totalMs = round((microtime(true) - $start) * 1000, 2);
$badge = ['hit' => 'ok', 'miss' => 'warn', 'bypass' => 'warn', 'off' => 'bad'];
$label = ['hit' => 'HIT 命中缓存', 'miss' => 'MISS 回源', 'bypass' => 'BYPASS 强制回源', 'off' => '未启用'];
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>LNMP 环境状态</title>
<style>
 body{margin:0;background:#0f172a;color:#e2e8f0;font-family:-apple-system,"Microsoft YaHei",sans-serif;
      display:flex;justify-content:center;padding:36px 20px}
 .card{background:#1e293b;border:1px solid #334155;border-radius:12px;padding:26px 34px;max-width:760px;width:100%}
 h1{margin:0 0 6px;font-size:20px}
 .sub{color:#94a3b8;font-size:13px;margin-bottom:20px}
 h3{margin:24px 0 8px;font-size:14px;color:#93c5fd;border-bottom:1px solid #334155;padding-bottom:6px}
 .row{display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #1f2f47;font-size:14px}
 .row:last-child{border:none}
 .k{color:#94a3b8} .v{font-family:Consolas,monospace;color:#38bdf8}
 .ok{color:#6ee7b7} .warn{color:#fbbf24} .bad{color:#fca5a5}
 a.btn{display:inline-block;margin:14px 8px 0 0;background:#2563eb;color:#fff;text-decoration:none;
       padding:8px 14px;border-radius:6px;font-size:13px}
</style>
</head>
<body>
<div class="card">
  <h1>LNMP 运行状态</h1>
  <div class="sub">Nginx + PHP-FPM + MySQL 8.0 + Redis</div>

  <h3>环境</h3>
  <div class="row"><span class="k">PHP 版本</span><span class="v"><?= PHP_VERSION ?></span></div>
  <div class="row"><span class="k">OPcache</span><span class="v"><?= function_exists('opcache_get_status') && opcache_get_status() ? '<span class="ok">已启用</span>' : '<span class="bad">未启用</span>' ?></span></div>
  <div class="row"><span class="k">Redis 扩展</span><span class="v"><?= class_exists('Redis') ? '<span class="ok">phpredis 已加载</span>' : '<span class="bad">未加载</span>' ?></span></div>

  <h3>Redis</h3>
  <div class="row"><span class="k">连接状态</span><span class="v"><?= $redis ? '<span class="ok">已连接</span>' : '<span class="bad">未连接，已降级直连 MySQL</span>' ?></span></div>
<?php if (!$redis && $rdErr): ?>
  <div class="row"><span class="k">连接失败原因</span><span class="v bad"><?= htmlspecialchars($rdErr) ?></span></div>
<?php endif; ?>
  <div class="row"><span class="k">连接耗时</span><span class="v"><?= $rdMs ?> ms</span></div>
  <div class="row"><span class="k">缓存状态</span><span class="v <?= $badge[$cache] ?>"><?= $label[$cache] ?></span></div>
  <div class="row"><span class="k">取数耗时</span><span class="v"><?= $statsMs ?> ms</span></div>
  <div class="row"><span class="k">缓存 TTL</span><span class="v"><?= $cacheTtl ?> s</span></div>

  <h3>Session（存 Redis）</h3>
  <div class="row"><span class="k">会话 ID</span><span class="v"><?= htmlspecialchars($sess['id']) ?></span></div>
  <div class="row"><span class="k">本会话访问次数</span><span class="v"><?= (int)$sess['visits'] ?></span></div>
<?php if (!$sess['ok'] && $sess['err']): ?>
  <div class="row"><span class="k">状态</span><span class="v bad"><?= htmlspecialchars($sess['err']) ?></span></div>
<?php endif; ?>

  <h3>MySQL</h3>
<?php if ($error): ?>
  <div class="row"><span class="k">状态</span><span class="v bad"><?= htmlspecialchars($error) ?></span></div>
<?php elseif ($stats): ?>
  <div class="row"><span class="k">版本</span><span class="v ok"><?= htmlspecialchars((string)$stats['mysql_version']) ?></span></div>
  <div class="row"><span class="k">orders 行数</span><span class="v"><?= number_format((int)$stats['orders_count']) ?></span></div>
  <div class="row"><span class="k">users 行数</span><span class="v"><?= number_format((int)$stats['users_count']) ?></span></div>
  <div class="row"><span class="k">order_items 行数</span><span class="v"><?= number_format((int)$stats['items_count']) ?></span></div>
<?php endif; ?>

  <div class="row" style="border:none;padding-top:14px">
    <span class="k">页面总耗时</span><span class="v"><?= $totalMs ?> ms</span>
  </div>

  <a class="btn" href="/">刷新（看缓存是否命中）</a>
  <a class="btn" href="?nocache=1" style="background:#0ea5e9">强制回源 nocache=1</a>
  <a class="btn" href="?flush=1" style="background:#dc2626">清缓存 flush=1</a>
  <a class="btn" href="?q=100" style="background:#7c3aed">演示查询 q=100</a>

<?php if ($query): ?>
  <h3>查询耗时：<?= $query['cost_ms'] ?> ms（返回 <?= $query['rows'] ?> 行）</h3>
<?php endif; ?>
</div>
</body>
</html>
