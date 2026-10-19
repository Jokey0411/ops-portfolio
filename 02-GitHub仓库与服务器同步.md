# GitHub 仓库与服务器代码同步

> 针对 `git clone` 在服务器上失败的两种情况：
> HTTPS 报 `Password authentication is not supported`、SSH 报 `Permission denied (publickey)`。

---

## 一、为什么两条路都走不通

| 方式 | 报错 | 原因 |
|---|---|---|
| HTTPS | `Invalid username or token. Password authentication is not supported for Git operations.` | GitHub 在 2021-08 起**彻底关掉了账号密码的 Git 认证**，HTTPS 只能用 **Personal Access Token (PAT)** |
| SSH | `git@github.com: Permission denied (publickey)` | 服务器上**没有任何一把 SSH 私钥**在 GitHub 上登记过 |

两个报错都跟"仓库存不存在"无关，纯粹是**认证没过**。所以先别去查仓库，先把认证搞定。

### 顺带确认一件事：你 yes 的那个指纹是真的 GitHub

```
ECDSA key fingerprint is SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM.
```

这个是 GitHub 官方公布的 ECDSA 主机指纹，核对无误（GitHub 的三个指纹见
`https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints`），
所以你那次 `yes` 没有连到中间人机器上。以后再碰到主机指纹提示，都应该先核对再 yes。

---

## 二、方案 A：给服务器单独配一把 GitHub 钥匙（推荐）

> 推荐理由：不用在服务器上存 token；私钥留在服务器、公钥放 GitHub，
> 以后 `git pull` 全自动化，配合自动备份脚本很合适。

### ⚠️ 第一条命令必须先看这个

你服务器上 `~/.ssh/` 里现在放着**登录用的密钥**（`authorized_keys` 等）。
`ssh-keygen` 如果用默认文件名，会把 `~/.ssh/id_ed25519` **直接覆盖掉，你就登不上服务器了**。
所以 `-f` 参数绝对不能省：

> **万一已经用了默认文件名 `id_ed25519` 生成，会不会把自己锁外面？**
> **不会。** 你登录服务器靠的是「Windows 上的私钥」配对「服务器 `~/.ssh/authorized_keys` 里的公钥」，
> 而 `~/.ssh/id_ed25519` 是**服务器作为客户端**去连别人时用的私钥，跟登录无关。
> 想确认登录凭据没被动过，看这个文件还在不在：
> ```bash
> wc -l ~/.ssh/authorized_keys     # ≥1 就是还在
> ```
> 不过还是建议以后用 `-f ~/.ssh/github_ed25519`，免得跟别的用途混淆。

```bash
# 用新文件名，别碰已有的登录密钥
ssh-keygen -t ed25519 -C "lighthouse-ops" -f ~/.ssh/github_ed25519
# 一路回车（不要设 passphrase，不然 cron 里没法自动 pull）

chmod 600 ~/.ssh/github_ed25519
ls -l ~/.ssh/
# 确认 id_ed25519（登录密钥）还在，多出了 github_ed25519 和 github_ed25519.pub
```

### 步骤 2：把公钥加到 GitHub

```bash
cat ~/.ssh/github_ed25519.pub
```

输出一整行，形如 `ssh-ed25519 AAAAC3NzaC1lZDI1... lighthouse-ops`，**整行复制**。

浏览器打开 → `https://github.com/settings/keys` → **New SSH key** →
Title 填 `lighthouse-ops` → Key type 保持 `Authentication Key` → 粘贴 → **Add SSH key**。

**几个容易选错的地方**：

| 位置 | 怎么选 | 说明 |
|---|---|---|
| 右上角头像 → **Settings** → 左侧 **SSH and GPG keys** | ← 走这里 | 这里是**账号级**密钥，加完对该账号所有仓库生效 |
| Key type | **Authentication Key** | 另一个 `Signing Key` 是给 commit 签名用的，**选错会导致 clone/push 仍然被拒** |
| 仓库 → Settings → **Deploy keys** | 别走这里 | Deploy key 只对**单个仓库**生效，且默认只读；适合 CI 拉代码，不适合你这个场景 |

> 粘进 Key 框的内容必须**是一整行**：`ssh-ed25519 AAAAC3... 备注`。
> 从终端复制时如果自动折行了，先粘到记事本里并成一行再复制。
> 开头必须是 `ssh-ed25519` / `ssh-rsa`，末尾的备注（如 `ops-portfolio`）可有可无。

**加完之后**（可能要求输入一次 GitHub 密码或 2FA 验证码确认）：

```bash
ssh -T git@github.com
# Hi Jokey0411! You've successfully authenticated, but GitHub does not provide shell access.
```

> 看到 `Hi 你的用户名!` 就是成功了。注意它虽然说 "does not provide shell access"，
> **这不是报错**，GitHub 本来就不给 shell，说明认证这一关已经过了。
>
> 如果加完还报 `Permission denied (publickey)`，顺序排查：
> ```bash
> ssh -Tv git@github.com 2>&1 | grep -iE "offering|server accepts|authentications that can continue"
> curl -sI https://github.com/Jokey0411/ops-portfolio | head -1    # 404 = 仓库名/用户名写错
> ```

### 步骤 3：告诉 ssh 用哪把钥匙（多密钥环境必做）

不指定的话，ssh 会拿默认密钥去试，试光了就报 `Permission denied (publickey)`。

```bash
cat >> ~/.ssh/config <<'EOF'

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_ed25519
    IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
```

### 步骤 4：验证（这一步能过，后面就都顺了）

```bash
ssh -T git@github.com
# 预期：Hi Jokey0411! You've successfully authenticated, but GitHub does not provide shell access.
```

> 如果还是 `Permission denied`，加 `-v` 看它到底拿了哪把钥匙：
> `ssh -Tv git@github.com 2>&1 | grep -i "offering\|identity"`

### 步骤 5：clone

```bash
dnf install -y git
rm -rf /opt/ops
git clone git@github.com:Jokey0411/ops-portfolio.git /opt/ops
ls /opt/ops
```

---

## 三、方案 B：用 Personal Access Token 走 HTTPS

适合临时拉一次、不想管 SSH 的情况。

**生成 token**：GitHub → Settings → Developer settings →
**Personal access tokens → Tokens (classic)** → Generate new token →
勾选 `repo`（私有仓库）/ `public_repo`（公开仓库）→ 生成。

> token **只显示一次**，关掉页面就没了，先复制下来。

```bash
git clone https://Jokey0411:<你的TOKEN>@github.com/Jokey0411/ops-portfolio.git /opt/ops
```

**不想让 token 明文留在 history 里**，用凭证存储：

```bash
git config --global credential.helper store
git clone https://github.com/Jokey0411/ops-portfolio.git /opt/ops
# 用户名填 Jokey0411，密码框粘贴 token（不是账号密码）
# 之后 token 存进 ~/.git-credentials，下次不用再输
```

> ⚠️ token 等价于密码：**别写进任何脚本、别提交进仓库**。
> 万一泄露：GitHub → Settings → Developer settings → 立刻 Revoke。
> 已经提交进 history 的 token，必须 Revoke + 用 `git filter-repo` 清历史。

---

## 四、方案 C：仓库还是空的话，反过来做最快（推荐给当前阶段）

你现在的情况大概率是：GitHub 上刚建了个**空仓库**，本地（Windows）有完整文件。
那就别 clone 了 —— 空仓库 clone 下来啥也没有。

**正确顺序是：先传文件上去 → 在服务器上 git init → 推回 GitHub。**

```powershell
# ① 在你电脑上（PowerShell）
cd C:\Users\34794\WorkBuddy\Linux
scp ops-portfolio.tar.gz root@你的公网IP:/root/
```

```bash
# ② 服务器上
mkdir -p /opt/ops
tar xzf /root/ops-portfolio.tar.gz -C /opt/ops
cd /opt/ops && ls

# ③ 修换行符 + 权限（照总 README 步骤 0-5）
find . -name "*.sh" -exec sed -i 's/\r$//' {} \;
find . -name "*.sh" -exec chmod +x {} \;

# ④ 建仓库并推上去
git init
git config user.name "Jokey0411"
git config user.email "你的邮箱@example.com"
git add .
git commit -m "init: 高可用集群 + LNMP 运维方案"

git branch -M main
git remote add origin git@github.com:Jokey0411/ops-portfolio.git
git push -u origin main
```

> **如果 GitHub 建仓库时勾了 "Add a README"**（仓库不是空的），先拉再推：
> ```bash
> git pull --rebase origin main
> git push -u origin main
> ```
> 报 `refusing to merge unrelated histories` 就加参数：
> `git pull --rebase origin main --allow-unrelated-histories`

**本地（Windows）也想要一份仓库**的话，同样在 `C:\Users\34794\WorkBuddy\Linux\ops-portfolio` 里
`git init` 一遍推上去，别在两边同时提交（容易冲突）。

---

## 五、验证仓库可用（面试前必做）

```bash
# 服务器上随便改个文件再提交，验证 push 链路通
cd /opt/ops
echo "# 运维方案" >> README.md
git add README.md && git commit -m "docs: 测试提交链路"
git push
git log --oneline -3
```

然后把仓库链接发给别人（或自己用无痕窗口打开）确认能公开访问。

> **简历上怎么落**：仓库里放一张 `docs/` 下的架构图 + 这份 README，
> 面试时说"代码和文档都在这个仓库里，服务器上是同一份，用 git 同步的"——
> 比口头描述可信得多。

---

## 六、排错表

| 报错 / 现象 | 原因 | 处理 |
|---|---|---|
| `Password authentication is not supported` | GitHub 已禁用密码认证 | 用 PAT（方案 B）或 SSH（方案 A） |
| `Permission denied (publickey)` | 服务器上没有已在 GitHub 登记的私钥 | 方案 A 步骤 1-4 |
| `Permission denied (publickey)` 但已加了 key | ssh 没用对的钥匙 | 写 `~/.ssh/config` 的 `IdentityFile` + `IdentitiesOnly yes` |
| `sign_and_send_pubkey: no mutual signature supported` | 老系统不支持 ed25519 | 改生成 rsa：`ssh-keygen -t rsa -b 4096 -f ~/.ssh/github_rsa` |
| `repository not found` | 仓库不存在 / 没权限 / 拼错用户名 | 浏览器打开该 URL 确认；私有仓库要先授权 |
| `Author identity unknown` + `fatal: unable to auto-detect email address` | 没配 `user.name` / `user.email`，commit 直接失败 | `git config --global user.name "Jokey0411"` + `git config --global user.email "..."` |
| `src refspec main does not match any` | **上一条 commit 没成功**，本地一个 commit 都没有，分支是空的 | 先让 commit 成功（`git log --oneline` 能看到），再 push |
| `warning: LF will be replaced by CRLF` | Windows 上 Git 默认 `core.autocrlf=true` | 加 `.gitattributes` 写 `*.sh text eol=lf` 锁死；仓库里存的其实仍是 LF，不影响 Linux |
| **`Recv failure: Connection was reset`** | 国内网络连 GitHub 被掐（网络层问题，与 git 无关） | 重试 → 配 `http.proxy` → 改 SSH 协议 → 让服务器代推（见第九章） |
| `failed to push some refs` | 远端有本地没有的提交 | 先 `git pull --rebase origin main` |
| `Permission denied (publickey)` 出现在 cron 里 | cron 环境找不到 ssh agent | 优先用 HTTPS + credential store，或在脚本里显式 `GIT_SSH_COMMAND` |
| `Could not open a connection to your authentication agent` | 只跑了 `ssh-agent -s`，没用 `eval` 把变量设进当前 shell | `eval "$(ssh-agent -s)"`；默认路径且无密码的密钥其实不需要 agent |
| 生成了钥匙还是 `publickey` | 公钥没上传到 GitHub（ssh-add 只管本地） | 浏览器打开 `github.com/settings/ssh/new` 粘贴 `.pub` |
| **`ERROR: Repository not found`** | **认证已经过了**，但仓库不存在 / 名字拼错 / 无权限 | 见第八章：先 `curl -sI` 确认，再建仓库 |

---

## 七、ssh-agent 什么时候才需要（本次踩的两个坑）

现场出现过的两条命令，其实**都不需要执行**：

```bash
ssh-agent -s          # ← 它只是"打印"环境变量，不会设置到当前 shell
ssh-add ~/.ssh/id_ed25519
# Could not open a connection to your authentication agent.
```

### 坑 1：`ssh-agent -s` 不带 `eval` 等于没跑

它把 `SSH_AUTH_SOCK=...; export ...` 打印到屏幕上，是为了**让你去执行**这些语句，
所以变量根本没进当前 shell，`ssh-add` 自然找不到 socket。正确写法：

```bash
eval "$(ssh-agent -s)"     # ← eval 才是关键
ssh-add ~/.ssh/id_ed25519
```

> 用 `ssh-agent bash` 或 `eval "$(ssh-agent -s)"` 都可以，但每次开新终端都要重来一遍。

### 坑 2：默认路径 + 无密码的密钥，压根不需要 agent

ssh 会自动依次尝试 `~/.ssh/id_rsa`、`id_ecdsa`、`id_ed25519`……只要你的钥匙满足：

- 文件名是默认的那几个之一（你现在就是 `id_ed25519`）
- 生成时没设 passphrase（你用了 `-N ''`，正是这个）

ssh 会**直接拿它去认证**，不需要 ssh-agent、不需要 ssh-add。
只有在"非默认文件名"或"设了密码"这两种情况下才需要 agent。

> 所以你现在**跳过 agent 直接测**就行：
> ```bash
> ssh -T git@github.com
> ```

### 真正的阻塞点：公钥还没上传到 GitHub

`ssh-add` 加的是**本地**的钥匙，GitHub 那边根本不知道你有这把钥匙。
必须把**公钥**登记到 GitHub 账号上，这一步在浏览器里做，命令行替代不了：

```bash
cat ~/.ssh/id_ed25519.pub
# ssh-ed25519 AAAAC3Nza... ops-portfolio      ← 整行复制
```
打开 `https://github.com/settings/ssh/new` → Title 随便填 → Key type 选 `Authentication Key`
→ 粘贴 → **Add SSH key**。

### 加完还不行，就用 -v 看它到底拿了哪把钥匙

```bash
ssh -Tv git@github.com 2>&1 | tail -25
```

看这三行：
```
Offering public key: /root/.ssh/id_ed25519 ED25519 SHA256:zWu2lCzYdtlPRKl2eO7goOucuR74WLEorNFuqR+DE8A
debug1: Server accepts key: ...
```
- 有 `Offering public key` 但后面是 `Server accepts key: ... invalid user` → 钥匙送过去了，但 GitHub 上没登记
- 连 `Offering` 都没有 → ssh 没找到这把钥匙（文件名不对或权限不对）
- 出现 `Authentication succeeded` → 成了

### 顺便确认仓库真的存在

```bash
curl -sI https://github.com/Jokey0411/ops-portfolio | head -1
# HTTP/2 200  → 存在且可访问；404 → 仓库名或用户名写错了
```

---

## 八、`ERROR: Repository not found` —— 认证过了，但仓库没有

**这个报错是好消息**：它出现在 `Permission denied (publickey)` 之后，说明**钥匙已经被 GitHub 接受了**，
问题从"你是谁"变成了"你要找的东西不存在"。

### 步骤 1：确认仓库到底存不存在

```bash
curl -sI https://github.com/Jokey0411/ops-portfolio | head -1
# HTTP/2 404  → 仓库不存在（或名字拼错）
# HTTP/2 200  → 存在，那是权限问题（私有仓库且没授权）
```

> 注意：GitHub 对**没权限访问的私有仓库也返回 404**（不会返回 403，避免泄漏仓库是否存在），
> 所以 404 有可能是"真没有"，也有可能是"不是你的"。

也可以在浏览器直接打开 `https://github.com/Jokey0411/ops-portfolio` 看。

### 步骤 2：建仓库（三种方式选一）

**方式 A：网页（最直观）**

右上角 `+` → **New repository** → Repository name 填 `ops-portfolio` →
选 Public 或 Private → **下面三个勾都别选**（README / .gitignore / license），
保持**完全空仓库** → Create repository。

> 勾了 "Add a README" 会生成一个非空的初始提交，后面 push 时要先
> `git pull --rebase origin main`，多一步麻烦。空仓库最省事。

**方式 B：用 API + token 在命令行建（不想开浏览器就用这个）**

```bash
curl -X POST https://api.github.com/user/repos \
  -H "Authorization: Bearer 你的TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -d '{"name":"ops-portfolio","private":false,"auto_init":false}'
# 返回里出现 "full_name": "Jokey0411/ops-portfolio" 就是建好了
```

**方式 C：装 GitHub CLI**

```bash
dnf install -y gh
gh auth login          # 按提示选 SSH / HTTPS，浏览器里确认一次
gh repo create ops-portfolio --public --confirm
```
> `gh auth login` 一次之后，后面 clone / push / 建仓库都不用再管认证，最省事。

### 步骤 3：仓库是空的，那就别 clone 了——直接把文件推上去

空仓库 clone 下来什么都没有。正确顺序是**反向**的（完整流程见第四章方案 C）：

```bash
# ① 服务器上：确认 /opt/ops 现在的状态（clone 失败会留下一个空目录）
ls -la /opt/ops

# ② 把文件放进去（Windows 上先 scp 上传 tar.gz）
tar xzf /root/ops-portfolio.tar.gz -C /opt/ops
cd /opt/ops

# ③ 修换行符 + 权限
find . -name "*.sh" -exec sed -i 's/\r$//' {} \;
find . -name "*.sh" -exec chmod +x {} \;

# ④ 推上去
git init
git config user.name "Jokey0411"
git config user.email "你的邮箱@example.com"
git add . && git commit -m "init: 高可用集群 + LNMP 运维方案"
git branch -M main
git remote add origin git@github.com:Jokey0411/ops-portfolio.git
git push -u origin main
```

### ⚠️ clone 完空仓库之后，千万别再 `git init`

`warning: You appear to have cloned an empty repository.` **不是报错**，
它只是说"这个仓库没有任何提交，我只拉到了 `.git` 目录"。

此时 `/opt/ops` 里**已经有 `.git` 和 origin 远端的配置了**，直接往里放文件、
`git add` / `commit` / `push` 就行。**再跑一次 `git init` 会重建一个没有 remote 的仓库**，
后面 push 会报 `No such remote 'origin'`。

确认当前状态：
```bash
cd /opt/ops
ls -la                 # 应该有 .git
git remote -v          # 应该显示 origin  git@github.com:Jokey0411/ops-portfolio.git
git branch             # 看当前分支是 main 还是 master
git log --oneline      # 空仓库会报 "does not have any commits yet"，正常
```

> 分支名取决于 GitHub 账号的默认分支设置。如果是 `master`，后面的 push 用
> `git push -u origin master`，或者先 `git branch -M main` 统一成 main。

推完之后，`/opt/ops` 就既是你跑方案的工作目录，也是一个和 GitHub 同步的 git 仓库。

---

## 九、国内网络推不上 GitHub：`Recv failure: Connection was reset`

```powershell
git push -u origin main
# fatal: unable to access 'https://github.com/xxx/xxx.git/': Recv failure: Connection was reset
```

这是 **TCP 连接被重置**，跟 git 配置、仓库权限都**没有关系**，纯粹是网络层的问题。
（对比：`Connection timed out` 是超时；`reset` 是对方/中间设备直接把你掐了。）

按顺序试，前一个不行再换下一个：

### ① 先重试两次（真的有一半概率是偶发）
```powershell
git push -u origin main
git push -u origin main
```

### ② 看你本机是不是有代理（有就让 git 走代理）

浏览器能打开 GitHub 但 git 不行，**十有八九是浏览器走了代理、git 没走**。

```powershell
netsh winhttp show proxy                 # 看系统代理
# 或：设置 → 网络和 Internet → 代理 → 手动设置代理 里看端口
```

假设代理端口是 7890（Clash 默认 7890，v2rayN 通常 10809，按你自己的改）：
```powershell
git config --global http.proxy  http://127.0.0.1:7890
git config --global https.proxy http://127.0.0.1:7890
git push -u origin main
```

推完想取消代理：
```powershell
git config --global --unset http.proxy
git config --global --unset https.proxy
```

### ③ 改走 SSH 协议（22 端口，有时比 443 稳）

```powershell
# 本地生成钥匙（之前生成过就跳过）
ssh-keygen -t ed25519 -C "win-laptop"
type C:\Users\34794\.ssh\id_ed25519.pub          # 整行复制

# 浏览器打开 https://github.com/settings/ssh/new 粘贴添加

# 把 remote 从 https 改成 ssh
git remote set-url origin git@github.com:Jokey0411/ops-portfolio.git
git remote -v                                     # 确认变成了 git@github.com: 开头
git push -u origin main
```

### ④ 让服务器代推（★ 你的服务器连 GitHub 已经验证可用）

如果本地网络实在不行——**服务器那边是通的**（前面 clone 成功过），让它来推：

```powershell
# Windows → 服务器（需要你的 Windows 私钥已配好）
scp -i C:\Users\34794\.ssh\id_ed25519 ops-portfolio.tar.gz root@111.231.169.180:/root/
```
```bash
# 服务器
cd /opt/ops
tar xzf /root/ops-portfolio.tar.gz -C /opt/ops
find . -name "*.sh" -exec sed -i 's/\r$//' {} \; -exec chmod +x {} \;
git add . && git commit -m "init: 高可用集群 + LNMP 运维方案"
git push -u origin main
```

> 顺带说明：Windows → 服务器 这条链路配好之后，以后**一切都可以在服务器上提交**，
> 本地网络再差也影响不到你。

### 附带：把提交缓冲调大（对大仓库有用，对这次基本没用）

```powershell
git config --global http.postBuffer 524288000
```
> 这条只对"推大文件推到一半断掉"有效。你这次 45 个文件才 110K，不是这个原因，
> 列在这里只是免得你后面踩到。

---

## 十、`tar: Cannot open: No such file or directory` —— 文件压根没传上去

### 报错含义

```bash
tar (child): /root/ops-portfolio.tar.gz: Cannot open: No such file or directory
tar: Child returned status 2
```

这是在**服务器端**执行 `tar` 时报的，说明**服务器的 `/root/` 下根本没有这个包**。
也就是说：上一次 `scp` 根本没成功，你解压的是一个不存在的文件。

> 这类报错跟压缩包内容、权限、tar 版本全都没关系，**只跟"文件在不在"有关**。

先确认一下（在服务器终端执行）：
```bash
ls -lh /root/*.tar.gz 2>/dev/null || echo "服务器上确实没有"
ls -la /opt/ops            # 应该只有 .git 一个目录
```

### 选哪条路

| 路径 | 依赖的链路 | 现状 | 推荐度 |
|---|---|---|---|
| **A. GitHub 网页上传 → 服务器 `git pull`** | 浏览器→GitHub（网页）、服务器→GitHub（SSH） | 两条都**已验证可用** | ★★★ 首选 |
| **B. Windows 配私钥后 `scp`** | Windows→服务器（SSH） | 还卡在 `Permission denied` | ★★ 配好之后最快 |
| **C. Windows 配代理后 `git push`** | Windows→GitHub（HTTPS/443） | 报 `Connection was reset` | ★ 看代理情况 |

**路径 A 是唯一一条不依赖任何"现在还是坏的"链路的走法**，建议先走它。

---

### 路径 A：GitHub 网页拖拽上传（不用配 SSH、不用管本地网络）

**① 在 Windows 上打开仓库页面**
```
https://github.com/Jokey0411/ops-portfolio
```
空仓库页面中间会有一行蓝字 **"uploading an existing file"**，点它；
或者直接在文件区域**把整个 `ops-portfolio` 文件夹拖进去**。

> 拖拽上传目录需要 Chrome / Edge（支持 HTML5 目录上传），会保留目录结构。
> 如果浏览器不支持文件夹拖拽，就手动建目录：点 **Create new file**，
> 文件名框里直接写 `project1-cluster/scripts/backup.sh`，GitHub 会自动建出多级目录。

**② 页面底部 Commit changes**
- 选 **Commit directly to the `main` branch**
- 按钮变绿后点一下

**③ 回服务器终端拉下来**
```bash
cd /opt/ops
git pull origin main
ls /opt/ops
```
应该看到 45 个文件。

**④ 修换行符 + 权限（这步不能省）**
```bash
cd /opt/ops
find . -name "*.sh" -exec sed -i 's/\r$//' {} \; -exec chmod +x {} \;
bash -n 00-init-server.sh && echo "语法 OK"
```

> 走 GitHub 上传的文件，`.sh` 在仓库里存的是 LF（`.gitattributes` 锁死了），
> 但保险起见还是跑一遍 `sed`，反正无害。

---

### 路径 B：把 Windows → 服务器 的 SSH 打通后再 scp

**① 服务器终端（你现在就在）执行这三行**，让服务器认自己的钥匙：
```bash
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
restorecon -R -v ~/.ssh 2>/dev/null
wc -l ~/.ssh/authorized_keys        # ≥1 就成了
cat ~/.ssh/id_ed25519               # 整段私钥复制出来（7 行，首尾 BEGIN/END 都要）
```

**② Windows PowerShell**，存成 `C:\Users\34794\.ssh\id_ed25519`（**不能有 .txt 后缀**），然后：
```powershell
icacls C:\Users\34794\.ssh\id_ed25519 /inheritance:r
icacls C:\Users\34794\.ssh\id_ed25519 /grant:r "$($env:USERNAME):(R)"
cd C:\Users\34794\WorkBuddy\Linux
scp -i C:\Users\34794\.ssh\id_ed25519 ops-portfolio.tar.gz root@111.231.169.180:/root/
```

**③ 成功后回服务器终端**：
```bash
ls -lh /root/ops-portfolio.tar.gz     # 先确认包真的到了
cd /opt/ops
tar xzf /root/ops-portfolio.tar.gz -C /opt/ops
find . -name "*.sh" -exec sed -i 's/\r$//' {} \; -exec chmod +x {} \;
git add . && git commit -m "init: 高可用集群 + LNMP 运维方案"
git push -u origin main
```

---

### 排错补充

| 报错 | 含义 | 处理 |
|---|---|---|
| `tar: Cannot open: No such file or directory` | 源文件不在（没传上去 / 路径拼错） | 先 `ls -lh /root/*.tar.gz` 确认 |
| `tar: Child returned status 2` | 同上，是第一条的连带输出 | 别管它，看上面那行 |
| `Not found in archive` | 包在，但里面没这个路径 | `tar tzf xxx.tar.gz \| head` 看包内结构 |
| `Cannot open: Permission denied` | 文件在但没读权限 | `chmod +r` 或换 `sudo` |
| scp 成功但解压后是空的 | `-C` 目标目录写错 | 确认 `-C /opt/ops` 而不是 `-C /opt` |

> 一个容易看漏的细节：`tar xzf xxx -C /opt/ops` 的 `-C` 是**先切目录再解压**，
> 所以目标目录必须**已经存在**。`/opt/ops` 是 clone 出来的，存在，没问题。

---

## 十一、一句话速记

```bash
# ① 生成钥匙（文件名一定是 github_ed25519，别碰登录用的 id_ed25519）
ssh-keygen -t ed25519 -C "lighthouse-ops" -f ~/.ssh/github_ed25519 -N ""
#     ↑ -N "" 表示不设密码；如果它提示已存在，说明你之前建过，直接跳到 ②

# ② 复制公钥去 GitHub → Settings → SSH and GPG keys → New SSH key
cat ~/.ssh/github_ed25519.pub

# ③ 绑定钥匙和主机
printf '\nHost github.com\n    HostName github.com\n    User git\n    IdentityFile ~/.ssh/github_ed25519\n    IdentitiesOnly yes\n' >> ~/.ssh/config
chmod 600 ~/.ssh/config

# ④ 验收
ssh -T git@github.com                  # 看到 Hi Jokey0411! 就成了
```

> 别在这段里加 `<<<y` 之类的自动确认——万一 `github_ed25519` 已经存在，
> 自动确认会把旧钥匙覆盖掉，而旧钥匙可能已经被别的地方引用了。
