# Docker 镜像拉取失败排查

> 适用：腾讯云轻量 / OpenCloudOS，国内机房拉 Docker Hub 失败。
> 配套脚本：`scripts/mirror_probe.sh`（一次探测所有候选源）

---

## 一、先分清你遇到的是哪一种

不同报错指向完全不同的原因，**看错报错会白折腾半小时**：

| 报错关键词 | 真实含义 | 该往哪个方向查 |
|---|---|---|
| `manifest unknown: manifest unknown` | **源是通的，但这个 tag 不存在** | 换 tag（本文第四节） |
| `net/http: TLS handshake timeout` | 能连上但握手超时 | 换源 / 代理 |
| `no such host` / `dial tcp: lookup ... no such host` | DNS 解析失败 | `/etc/resolv.conf`、换源 |
| `connection refused` | 端口不通 | 源已下线，换源 |
| `toomanyrequests: You have reached your pull rate limit` | Docker Hub 限流 | 换源（不要登录，登录反而更容易限） |
| `x509: certificate signed by unknown authority` | 证书问题（少见） | 检查系统时间 `date`、ca-certificates |
| `pull access denied` | 需要登录 | 公共镜像不该出现，多半是仓库名拼错 |

**你这次的 `manifest unknown` 属于第一类**——好消息，说明 `ccr.ccs.tencentyun.com` 这个源**是通的、路径 `library/nginx` 也是对的**，只是它没有 `1.25-alpine` 这个 tag。

> **但本次实测的最终结论不是换 tag，而是别手写域名**：
> 配好 `registry-mirrors` 之后，`docker pull nginx:1.25-alpine` **直接成功**
> （`mirror.ccs.tencentyun.com` 上有这个 tag）。
> 之前失败是因为写了 `ccr.ccs.tencentyun.com/library/nginx:1.25-alpine`——
> **显式带域名会绕过 mirror 配置**，把自己锁死在单个源上，而那个源恰好没同步这个 tag。
>
> ★ 记住：**mirror 配好后一律写官方原名，不要加前缀。**

---

## 二、三步定位（按顺序做，别跳）

### Step 1：确认加速源有没有真的生效

```bash
docker info 2>/dev/null | grep -A8 "Registry Mirrors"
```

**重点**：如果这里只显示 `https://registry-1.docker.io/`，说明 `daemon.json` 没生效——
改完 `daemon.json` 必须 `systemctl restart docker`，只 `reload` 不行。

```bash
systemctl restart docker
docker info | grep -A8 "Registry Mirrors"     # 再确认一次
```

### Step 2：不带 tag 拉一次，判断是"源不通"还是"tag 没有"

```bash
docker pull ccr.ccs.tencentyun.com/library/nginx        # 不写 tag = latest
```

- **成功** → 源和路径都对，纯粹是 `1.25-alpine` 这个 tag 没同步 → 跳到第四节换 tag
- **失败** → 源本身有问题 → 继续 Step 3

### Step 3：跑探测脚本，一次试完所有候选源

```bash
cd /opt/ops
bash scripts/mirror_probe.sh
```

脚本会依次做四件事：打印当前 mirrors → 直拉官方名测 mirror → 挨个测前缀式源 → **输出可直接复制的 sed 命令**。

---

## 三、四条解法（按推荐度排）

### 方案 A：registry-mirrors（最优）

改 `/etc/docker/daemon.json`，让 docker 自动走加速，**compose 文件一个字都不用改**。

```bash
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "20m", "max-file": "3" },
  "live-restore": true,
  "exec-opts": ["native.cgroupdriver=systemd"],
  "storage-driver": "overlay2"
}
EOF
systemctl restart docker          # 必须 restart，不是 reload
docker pull nginx:alpine          # 验证
```

> 一次可以配多个 mirror，docker 会**按顺序尝试**，前面失败自动换下一个。
> 所以不用纠结哪个最好用，多写几个就完了。

### 方案 B：前缀式直连（mirror 全挂时的兜底）

直接把源域名写进镜像名，绕过 mirror 配置：

```bash
docker pull ccr.ccs.tencentyun.com/library/nginx:alpine
```

要让 compose 也用上，得批量改镜像名：

```bash
cd /opt/ops
REG="ccr.ccs.tencentyun.com"          # 换成探测脚本给出的可用源

for f in project1-cluster/docker-compose.yml project2-lnmp/docker-compose.yml; do
  cp -a "$f" "$f.bak.$(date -I)"       # 先备份
  sed -i -E "s#image: (nginx|mysql|python|php|redis):#image: ${REG}/library/\1:#" "$f"
done

# Dockerfile 里的 FROM 也要改（build 时才会拉）
sed -i "s#^FROM #FROM ${REG}/library/#" project1-cluster/app/Dockerfile project2-lnmp/php/Dockerfile

# 验证语法
cd project1-cluster && docker compose config >/dev/null && echo "compose 语法 OK"
```

### 方案 C：给 docker 配 HTTP 代理

适合你本机有可用代理的情况（Clash / v2rayN）：

```bash
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/proxy.conf <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:7890"
Environment="HTTPS_PROXY=http://127.0.0.1:7890"
Environment="NO_PROXY=localhost,127.0.0.1,ccr.ccs.tencentyun.com,mirror.ccs.tencentyun.com"
EOF
systemctl daemon-reload && systemctl restart docker
docker pull nginx:alpine
```

> `NO_PROXY` 一定要带上腾讯云内网域名，否则内网镜像源也会被送去绕代理。

取消代理：
```bash
rm -f /etc/systemd/system/docker.service.d/proxy.conf
systemctl daemon-reload && systemctl restart docker
```

### 方案 D：换 tag（你这次大概率就是这条）

见下一节。

---

## 四、关于 tag：什么时候才需要换

> **先看完第三节**：如果 `docker pull nginx:1.25-alpine`（不带域名）能成功，
> **就不需要换 tag**，本节跳过。本次实测就是这样。

只有在**官方原名也拉不到**时，才考虑换 tag —— 因为老版本 tag 有被清理的风险。

`nginx:1.25-alpine` 里的 **1.25 是 nginx 主线版，2024 年就已 EOL**。
Docker Hub 官方虽然还留着这个 tag，但**国内镜像源普遍只同步 `latest` 和仍在维护的版本**，
所以老 tag 经常在镜像源里查不到。

**建议改成这两个之一**：

| tag | 说明 |
|---|---|
| `nginx:1.27-alpine` | 1.27 是目前广泛同步的稳定版，**推荐** |
| `nginx:alpine` | 永远指向最新 alpine 版，最不容易拉不到，但版本会漂移 |

改法（两个 compose 都用 nginx）：

```bash
cd /opt/ops
sed -i 's#nginx:1.25-alpine#nginx:1.27-alpine#g' \
    project1-cluster/docker-compose.yml project2-lnmp/docker-compose.yml
grep -n "image:.*nginx" project1-cluster/docker-compose.yml project2-lnmp/docker-compose.yml
```

> **重要**：`Dockerfile` 里的 `FROM python:3.11-alpine` / `FROM php:8.2-fpm-alpine`
> 也可能踩同样的坑。这两个版本是活跃的（3.11 / 8.2 都在维护期），问题不大；
> 万一拉不到，同样换成 `python:3.12-alpine`、`php:8.3-fpm-alpine` 即可。

---

## 五、本项目需要的镜像清单

先确认这几个都能拉到，再启动 compose，能省掉一半排查时间：

```bash
for IMG in nginx:1.27-alpine mysql:8.0 python:3.11-alpine php:8.2-fpm-alpine; do
  timeout 120 docker pull "$IMG" >/dev/null 2>&1 && echo "✔ $IMG" || echo "✘ $IMG"
done
```

| 镜像 | 用在哪 | 备注 |
|---|---|---|
| `nginx:1.27-alpine` | 项目一 LB + 两个节点、项目二 web | 共 4 处 |
| `mysql:8.0` | 项目一双实例、项目二数据库 | 体积最大（~150MB 压缩） |
| `python:3.11-alpine` | 项目一 app（自建镜像的 base） | 需 build |
| `php:8.2-fpm-alpine` | 项目二 php（需装 pdo_mysql 扩展） | 需 build |

**先单独把 `mysql:8.0` 拉下来**——它最大最容易超时，而且两个项目都要用。
它一旦拉好，后面的基本都顺。

---

## 六、排错表

| 现象 | 原因 | 处理 |
|---|---|---|
| `manifest unknown` | tag 在源里不存在 | 换 tag（第四节） |
| 改了 daemon.json 没变化 | 只 `reload` 没 `restart` | `systemctl restart docker` |
| `docker info` 看不到 mirrors | daemon.json 有 JSON 语法错 | `python3 -m json.tool /etc/docker/daemon.json` |
| 拉取卡住不动 | 某个 mirror 半死不活 | 去掉那个 mirror，只留验证过可用的 |
| 一直 `TLS handshake timeout` | 出口被限 | 走方案 C 代理，或方案 B 前缀源 |
| `no space left on device` | 磁盘满了 | `df -h`、`docker system df`、`docker system prune -a` |
| 拉下来但容器起不来 | 与本问题无关 | `docker logs <容器名>` 看具体报错 |

---

## 七、验证通过的标准

```bash
docker images                        # 能看到 nginx / mysql / python / php
docker compose config >/dev/null     # 无输出 = 语法 OK
cd /opt/ops/project1-cluster && docker compose up -d --build
docker compose ps                    # 7 个容器全 Up
```
