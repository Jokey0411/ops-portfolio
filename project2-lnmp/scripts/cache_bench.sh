#!/bin/bash
# =============================================================
#  HTTP 压测：对比「走缓存」与「强制回源」的性能差
#
#  用法：
#    bash scripts/cache_bench.sh              # 默认 1000 请求 / 20 并发
#    bash scripts/cache_bench.sh 2000 50      # 自定义请求数与并发
#
#  产物：docs/benchmark_cache.txt
#
#  为什么用 ab 而不是 curl 循环：
#    curl 串行发请求，测出来的是「一次往返的延迟」，不是吞吐。
#    ab 能压出 QPS（每秒处理请求数）和 P95，这两个才是简历上写得出手的指标。
# =============================================================

set -uo pipefail

BASE="${BASE_URL:-http://127.0.0.1:8080}"
N="${1:-1000}"
C="${2:-20}"
IMG="${IMG:-httpd:2.4-alpine}"
OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/docs"
OUT="$OUT_DIR/benchmark_cache.txt"

mkdir -p "$OUT_DIR"

echo "========================================" | tee "$OUT"
echo " 缓存压测  $(date '+%F %T')"             | tee -a "$OUT"
echo " 目标: $BASE   请求数: $N   并发: $C"     | tee -a "$OUT"
echo "========================================" | tee -a "$OUT"

run_ab() {
    local label="$1" url="$2"
    echo "" | tee -a "$OUT"
    echo "--- $label ---" | tee -a "$OUT"
    echo "URL: $url" | tee -a "$OUT"

    # 预热 50 次：第一次请求要建连接、编译脚本，不能算进正式数据
    docker run --rm --network host "$IMG" ab -n 50 -c 5 -q "$url" >/dev/null 2>&1

    docker run --rm --network host "$IMG" ab -n "$N" -c "$C" -q "$url" 2>/dev/null \
      | grep -E 'Complete requests|Failed requests|Requests per second|Time per request|Transfer rate' \
      | tee -a "$OUT"
}

# ① 强制回源：每次都打 MySQL
run_ab "A. 强制回源（nocache=1）" "$BASE/?nocache=1"

# ② 走缓存：第二次以后的请求应该全部 HIT
run_ab "B. 走缓存（Cache-Aside）" "$BASE/"

echo "" | tee -a "$OUT"
echo "========================================" | tee -a "$OUT"
echo " 结果已保存：$OUT" | tee -a "$OUT"
echo " 判读要点：" | tee -a "$OUT"
echo "   1. Failed requests 必须是 0 —— 非 0 说明有 5xx，压测数据不可用" | tee -a "$OUT"
echo "   2. 看 Requests per second 的倍数差，这是 QPS 提升" | tee -a "$OUT"
echo "   3. Time per request 看平均延迟，而非单次采样" | tee -a "$OUT"
echo "========================================" | tee -a "$OUT"
