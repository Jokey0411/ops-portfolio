<?php
/**
 * LNMP 环境验证页
 * 访问 http://你的IP:8080/
 */
declare(strict_types=1);

header('Content-Type: text/html; charset=utf-8');

$dbHost = getenv('DB_HOST') ?: 'mysql';
$dbName = getenv('DB_NAME') ?: 'shop';
$dbUser = getenv('DB_USER') ?: 'app';
$dbPass = getenv('DB_PASS') ?: 'App@123456';

$result = [];
$error  = null;
$start  = microtime(true);

try {
    $pdo = new PDO(
        "mysql:host={$dbHost};dbname={$dbName};charset=utf8mb4",
        $dbUser, $dbPass,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_TIMEOUT => 5]
    );
    $result['mysql_version'] = $pdo->query('SELECT VERSION()')->fetchColumn();
    $result['orders_count']  = (int)$pdo->query('SELECT COUNT(*) FROM orders')->fetchColumn();
    $result['users_count']   = (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn();

    // 演示查询：走索引前后对比（?q=1 时执行）
    if (isset($_GET['q'])) {
        $t0 = microtime(true);
        $stmt = $pdo->prepare(
            "SELECT id, user_id, amount, status, created_at
             FROM orders WHERE user_id = ? AND status = 'paid'
             ORDER BY created_at DESC LIMIT 20"
        );
        $stmt->execute([(int)($_GET['q'] ?: 100)]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $result['query'] = [
            'rows' => count($rows),
            'cost_ms' => round((microtime(true) - $t0) * 1000, 2),
            'sample' => array_slice($rows, 0, 3),
        ];
        // 顺带看执行计划
        $explain = $pdo->query(
            "EXPLAIN SELECT id,user_id,amount,status,created_at FROM orders
             WHERE user_id = " . (int)$_GET['q'] . " AND status='paid'
             ORDER BY created_at DESC LIMIT 20"
        )->fetch(PDO::FETCH_ASSOC);
        $result['explain'] = $explain;
    }
} catch (Throwable $e) {
    $error = $e->getMessage();
}

$totalMs = round((microtime(true) - $start) * 1000, 2);
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>LNMP 环境状态</title>
<style>
 body{margin:0;background:#0f172a;color:#e2e8f0;font-family:-apple-system,"Microsoft YaHei",sans-serif;
      display:flex;justify-content:center;padding:40px 20px}
 .card{background:#1e293b;border:1px solid #334155;border-radius:12px;padding:28px 36px;max-width:760px;width:100%}
 h1{margin:0 0 6px;font-size:20px}
 .sub{color:#94a3b8;font-size:13px;margin-bottom:22px}
 .row{display:flex;justify-content:space-between;padding:9px 0;border-bottom:1px solid #334155;font-size:14px}
 .row:last-child{border:none}
 .k{color:#94a3b8}
 .v{font-family:Consolas,monospace;color:#38bdf8}
 .ok{color:#6ee7b7} .bad{color:#fca5a5}
 a.btn{display:inline-block;margin-top:18px;background:#2563eb;color:#fff;text-decoration:none;
       padding:9px 16px;border-radius:6px;font-size:14px}
 pre{background:#0b1220;padding:12px;border-radius:6px;font-size:12px;overflow:auto;color:#a5b4fc}
</style>
</head>
<body>
<div class="card">
  <h1>LNMP 环境运行状态</h1>
  <div class="sub">Docker Compose: Nginx + PHP-FPM + MySQL 8.0</div>

  <div class="row"><span class="k">Nginx 节点</span><span class="v"><?= htmlspecialchars(gethostname()) ?></span></div>
  <div class="row"><span class="k">PHP 版本</span><span class="v"><?= PHP_VERSION ?></span></div>
  <div class="row"><span class="k">OPcache</span><span class="v"><?= function_exists('opcache_get_status') && opcache_get_status() ? '<span class="ok">已启用</span>' : '<span class="bad">未启用</span>' ?></span></div>
  <div class="row"><span class="k">页面总耗时</span><span class="v"><?= $totalMs ?> ms</span></div>

<?php if ($error): ?>
  <div class="row"><span class="k">MySQL</span><span class="v bad">连接失败: <?= htmlspecialchars($error) ?></span></div>
<?php else: ?>
  <div class="row"><span class="k">MySQL 版本</span><span class="v ok"><?= htmlspecialchars($result['mysql_version']) ?></span></div>
  <div class="row"><span class="k">orders 表行数</span><span class="v"><?= number_format($result['orders_count']) ?></span></div>
  <div class="row"><span class="k">users 表行数</span><span class="v"><?= number_format($result['users_count']) ?></span></div>
<?php endif; ?>

  <a class="btn" href="?q=100">执行演示查询（user_id=100）</a>
  <a class="btn" href="?q=42" style="background:#0ea5e9">换一个用户（user_id=42）</a>

<?php if (isset($result['query'])): ?>
  <h3 style="margin-top:26px;font-size:15px">查询耗时：<?= $result['query']['cost_ms'] ?> ms（返回 <?= $result['query']['rows'] ?> 行）</h3>
  <pre><?= htmlspecialchars(print_r($result['explain'], true)) ?></pre>
  <pre><?= htmlspecialchars(print_r($result['query']['sample'], true)) ?></pre>
<?php endif; ?>

  <p style="color:#64748b;font-size:12px;margin-top:20px">
    提示：先访问一次本页记录未建索引时的耗时，执行 sql/optimize.sql 后再对比。
  </p>
</div>
</body>
</html>
