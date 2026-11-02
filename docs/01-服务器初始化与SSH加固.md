# SSH 密钥登录与安全加固

> 适用：腾讯云轻量 / OpenCloudOS，手上有私钥文件（.pem 或 id_rsa）
> 目标：密钥登录 → 验证通过 → 禁用密码登录 → 改端口（可选）
>
> ⚠️ **铁律（先看这条，不然后悔莫及）**：
> 改 SSH 配置的整个过程中，**当前这个已连上的终端绝对不能关**。
> 必须**另开一个新终端**测试密钥登录成功了，才允许关掉旧连接。
> 否则配置写错就把自己锁在门外了。真锁了也有救——见文末"把自己锁外面怎么办"。

---

## 一、先判断你是哪种情况

| 情况 | 特征 | 跳到 |
|---|---|---|
| **A** | 自己生成的密钥对，或者**服务器上还没你的公钥** | [第三章](#三情况a服务器上还没有你的公钥) |
| **B** | 腾讯云控制台创建密钥对时**下载的那个私钥文件** | [第四章](#四情况b用腾讯云下载的私钥) |
| **C** | 私钥是 `.ppk` 格式（PuTTY 生成） | [第五章](#五情况cppk-格式转换) |
| **D** | 之前一直用**腾讯云控制台一键登录**（WebShell），本地压根没私钥 | [第三章附](#附情况d用控制台登录现在scp不了) |

不确定就先执行这条，能连通说明服务器已经有你的公钥了，直接跳到第七章做加固：
```powershell
ssh -i C:\Users\34794\.ssh\id_rsa root@你的公网IP
```

---

## 附：情况 D — 用控制台登录的，现在 scp 报 Permission denied

### 典型现场

```powershell
scp ops-portfolio.tar.gz root@111.231.169.180:/root/
# root@111.231.169.180: Permission denied (publickey,gssapi-keyex,gssapi-with-mic).
# C:\Windows\System32\OpenSSH\scp.exe: Connection closed
```

### 怎么读这个报错

- **连接是通的**（22 端口、sshd 都正常），失败发生在认证阶段
- 括号里的 `publickey,gssapi-keyex,gssapi-with-mic` 是**尝试过且失败的方式**
- **里面没有 `password`** → 服务器已经不给密码登录的机会了
  （要么你做过第七章的加固，要么这台机器本来就是纯密钥登录）

### 如果你看到的是这两行，那是**两个不同的问题**

```powershell
Warning: Identity file C:\Users\34794\.ssh\id_rsa not accessible: No such file or directory.
ssh: connect to host 111.231.168.180 port 22: Connection refused
```

| 那一行 | 严重程度 | 含义 |
|---|---|---|
| `Identity file ... not accessible` | **只是 Warning，不是失败原因** | Windows 上没有 `id_rsa` 这个默认私钥。ssh 会继续尝试别的方式，**忽略它看下一行** |
| `Connection refused` | **真正的失败** | 那个地址的 22 端口**没人应答**——跟密钥一点关系都没有 |

`Connection refused` 的三个成因，按概率排：

1. **IP 打错了**（最常见的就是这个）—— 例：`111.231.169.180` 敲成 `111.231.168.180`
2. **端口改过了** —— 做过第七章加固改成 2222，却还在连 22
3. **sshd 没在监听** —— 配置改崩了没起来（改崩的典型就是忘了 `semanage` 放行端口）

**怎么确认**：去控制台 → 实例详情看**真实公网 IP**，同时看防火墙放行的是哪个端口。

> ★ **根治手敲 IP 出错的办法**：配别名，以后再也不用输 IP。
> `C:\Users\34794\.ssh\config`（没有就新建）：
> ```ssh-config
> Host lh
>     HostName 111.231.169.180
>     Port 22
>     User root
>     IdentityFile C:\Users\34794\.ssh\id_ed25519
>     ServerAliveInterval 60
> ```
> 之后 `ssh lh`、`scp ops-portfolio.tar.gz lh:/root/` —— IP 和端口都写死在配置里，不可能再敲错。
> （改过端口就把 `Port 22` 改成 `Port 2222`）

### 根因

你之前进服务器走的是**腾讯云控制台 → 一键登录**（WebShell/VNC），
那是云厂商的带外通道，**不经过 SSH 认证**，所以本地一直不需要私钥。
现在从 Windows 直接 scp，走的是真 SSH，服务器上没有你 Windows 的公钥 → 被拒。

### 最小三步（赶时间就照这个走）

| # | 在哪 | 做什么 |
|---|---|---|
| 1 | **Windows PowerShell** | `ssh-keygen -t ed25519`，然后 `type ~\.ssh\id_ed25519.pub` 复制整行 |
| 2 | **控制台一键登录**（进服务器） | `echo "粘贴那一行" >> ~/.ssh/authorized_keys` + `chmod 600` + `restorecon -R -v ~/.ssh` |
| 3 | **Windows PowerShell** | `icacls` 修私钥权限两步 → `ssh -i ~\.ssh\id_ed25519 root@IP` |

> 顺序不能反：**私钥留在 Windows，公钥送去服务器**。
> 别把私钥往服务器上拷，那是反的。

### ⚠️ 第一步：先确认自己还能进服务器

控制台 → 实例详情 → **一键登录**。能进去就万事大吉，按下面任一方案走。
**进不去的话**：控制台 → 重置密码 → 用 VNC 登录后改回配置。

### 解法 1（正统）：Windows 生成密钥对，公钥塞进服务器

```powershell
# ① 本地生成（一路回车）
ssh-keygen -t ed25519 -C "win-laptop"
# 生成 C:\Users\34794\.ssh\id_ed25519 和 id_ed25519.pub

# ② 看公钥，整行复制
type C:\Users\34794\.ssh\id_ed25519.pub
```

然后**用控制台一键登录**进服务器，把那一行追加进去：
```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "粘贴刚才复制的整行" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
getenforce && restorecon -R -v ~/.ssh      # OpenCloudOS 的 SELinux 步骤，别漏
```

回 Windows 测试：
```powershell
ssh -i C:\Users\34794\.ssh\id_ed25519 root@111.231.169.180
```

### 解法 2（最快）：复用服务器上已有的那把钥匙

你刚才在服务器上生成过 `/root/.ssh/id_ed25519`，它是一对**现成的密钥对**——
只要把它的公钥追加进 `authorized_keys`、私钥拿回 Windows，就能直接登。

```bash
# 服务器上（用控制台登录进去执行）
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
restorecon -R -v ~/.ssh
cat ~/.ssh/id_ed25519          # 把这段私钥内容整段复制出来
```

Windows 上存成 `C:\Users\34794\.ssh\id_ed25519`（**不能有 .txt 后缀**），然后：
```powershell
icacls C:\Users\34794\.ssh\id_ed25519 /inheritance:r
icacls C:\Users\34794\.ssh\id_ed25519 /grant:r "$($env:USERNAME):(R)"
scp -i C:\Users\34794\.ssh\id_ed25519 ops-portfolio.tar.gz root@111.231.169.180:/root/
```

> 严格说私钥应该「本地生成、公钥上传」，私钥不该从服务器往回搬。
> 但你这是单人实验机，图省事完全够用；解法 1 才是规范做法。

### ⚠️ scp 跑在哪台机器上？（最常见的低级失误）

`scp` 是**在发起方（你本地 Windows）执行**的，不是登录到服务器之后再敲。

如果你在服务器终端里敲 `scp -i C:\Users\...`，会看到这一串：

```
Warning: Identity file C:Users34794.sshid_ed25519 not accessible: No such file or directory.
The authenticity of host '111.231.169.180 (111.231.169.180)' can't be established.
root@111.231.169.180: Permission denied (publickey,gssapi-keyex,gssapi-with-mic).
```

两个特征一眼就能认出来：

1. **`C:Users34794.sshid_ed25519`** —— 反斜杠被 Linux 当成转义符吃掉了，
   说明这条命令跑在了 Linux 上，Windows 路径在那里没有意义
2. **指纹提示 `The authenticity of host ... can't be established`** ——
   服务器在连它自己，它当然没登过自己

**scp / ssh 一律在你自己的 PowerShell 里跑；服务器上只跑 `ls`、`tar`、`git` 这类本地命令。**

### 排错：用 -v 看它到底拿了哪把钥匙

```powershell
scp -v -i C:\Users\34794\.ssh\id_ed25519 ops-portfolio.tar.gz root@111.231.169.180:/root/ 2>&1 | Select-String "Offering|Trying|Authenticated|Permission denied"
```
- 出现 `Offering public key: ... id_ed25519 ED25519` → 钥匙送出去了，服务器上没登记这个公钥
- 连 `Offering` 都没有 → 私钥路径不对 / 权限太松被拒绝加载
- 出现 `Authenticated to ...` → 成了

---

## 二、Windows 端私钥权限修复（★ 不做必报错）

Windows 上的 OpenSSH 会**强制检查私钥文件权限**，权限太松直接拒绝使用：

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@         WARNING: UNPROTECTED PRIVATE KEY FILE!          @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Permissions for 'key.pem' are too open.
It is required that your private key files are NOT accessible by others.
```

### 修复（PowerShell，一行一行敲）

```powershell
# 1) 进到私钥所在目录
cd C:\Users\34794\.ssh

# 2) 移除继承权限（不删继承权限的话，下面那步会被覆盖，很多人卡在这）
icacls .\id_rsa /inheritance:r

# 3) 只给当前用户读权限
icacls .\id_rsa /grant:r "$($env:USERNAME):(R)"

# 4) 确认结果：应该只剩一行 NT AUTHORITY\SYSTEM 和你自己的用户名
icacls .\id_rsa
```

**预期输出**：
```
id_rsa NT AUTHORITY\SYSTEM:(I)(F)
       DESKTOP-XXX\34794:(R)
已成功处理 1 个文件
```

> 文件名换成你自己的（可能是 `key.pem`、`Tencent-Key.pem` 等）。
> 如果是 .pem 后缀，把命令里的 `id_rsa` 全换成你的文件名。

### 顺便建议：给私钥建个固定家

```powershell
mkdir C:\Users\34794\.ssh
# 把私钥挪进来，之后所有命令都用 C:\Users\34794\.ssh\id_rsa 这个路径
```

---

## 三、情况A：服务器上还没有你的公钥

### 步骤 1：生成密钥对（在你电脑上）

```powershell
# 推荐 ed25519（更短更安全）
ssh-keygen -t ed25519 -C "wangjiyun@ops"

# 如果要兼容老系统/腾讯云控制台，用 RSA
ssh-keygen -t rsa -b 4096 -C "wangjiyun@ops"
```

一路回车（**passphrase 可以直接回车留空**，不然每次登录都要输密码）：
```
Generating public/private ed25519 key pair.
Enter file in which to save the key (C:\Users\34794/.ssh/id_ed25519):   ← 回车
Enter passphrase (empty for no passphrase):                              ← 回车
Enter same passphrase again:                                             ← 回车
Your public key has been saved in C:\Users\34794/.ssh/id_ed25519.pub
```

生成两个文件：
- `id_ed25519` → **私钥**，打死不能给人
- `id_ed25519.pub` → **公钥**，要放到服务器上

```powershell
# 看公钥内容（整串都要复制）
type C:\Users\34794\.ssh\id_ed25519.pub
```
输出类似：
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx wangjiyun@ops
```

### 步骤 2：把公钥放到服务器上（选一种）

**方法 1：先 scp 上传公钥文件，再在服务器上追加（★ 最可靠，推荐）**
```powershell
scp C:\Users\34794\.ssh\id_ed25519.pub root@你的公网IP:/tmp/pubkey.pub

# 登录上去追加（会输一次密码，之后就不用了）
ssh root@你的公网IP "mkdir -p ~/.ssh && cat /tmp/pubkey.pub >> ~/.ssh/authorized_keys && rm -f /tmp/pubkey.pub && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys && echo done"
```
看到 `done` 就成了。

**方法 2：`ssh-copy-id`（Linux / Mac / 部分 Git Bash 才有）**
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@你的公网IP
```
> ⚠️ Windows 自带的 OpenSSH 客户端**不包含** `ssh-copy-id`，PowerShell 里敲会报
> "无法将 ssh-copy-id 识别为 cmdlet"——遇到就用方法 1。

**方法 3：管道一行流（PowerShell 里可能出幺蛾子，不推荐但能用）**
```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@你的公网IP "cat >> ~/.ssh/authorized_keys"
```
> PowerShell 5.1 往原生命令传字符串可能夹杂编码/换行问题，
> 表现为 `authorized_keys` 里的公钥被换行截断 —— 用方法 1 就完全避开这个坑。

**方法 4：手动登上去编辑**
```bash
# 先用密码登录服务器
mkdir -p ~/.ssh
chmod 700 ~/.ssh
vim ~/.ssh/authorized_keys
# 按 i，把公钥整行粘贴进去（一行一个公钥，中间不能断开换行）
# Esc → :wq 保存
chmod 600 ~/.ssh/authorized_keys
```

### 步骤 3：★ 修服务器上 .ssh 的权限（不做照样登不上）

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
chown -R root:root ~/.ssh
ls -la ~/.ssh
```

**预期**：
```
drwx------. 2 root root 4096 ... .
-rw-------. 1 root root  398 ... authorized_keys
```

### 步骤 4：SELinux 开着的话还要修上下文（OpenCloudOS 特有）

```bash
getenforce
# 如果是 Enforcing，执行：
restorecon -R -v ~/.ssh
```
> 不修的话，现象是**一切权限都对的但就是登不上**，日志里却只有一句 Permission denied (publickey)。
> 这个坑能卡人一整天。

### 步骤 5：测试

```powershell
ssh -i C:\Users\34794\.ssh\id_ed25519 root@你的公网IP
```
不用输密码就进去了 = 成功。

---

## 四、情况B：用腾讯云下载的私钥

腾讯云轻量控制台 → **密钥** → 创建密钥 → 会自动下载一个 `.pem` 私钥文件。

### 绑定方式

轻量服务器的密钥**只能在创建实例或重装系统时绑定**，运行中无法直接挂载：
- 控制台 → 实例 → 重装系统 → 选择"使用已有密钥"/绑定密钥
- 或者走情况A的方式：**自己把公钥粘进 `authorized_keys`**，效果完全一样

### 登录

```powershell
cd C:\Users\34794\.ssh
icacls .\你的私钥.pem /inheritance:r
icacls .\你的私钥.pem /grant:r "$($env:USERNAME):(R)"

ssh -i C:\Users\34794\.ssh\你的私钥.pem root@你的公网IP
```

> 腾讯云轻量用 root 登录时，登录用户名是 `root`（部分镜像可能是 `lighthouse`，
> 试不出来就在控制台看一下镜像说明）。

---

## 五、情况C：.ppk 格式转换

PuTTY 生成的 `.ppk` 不能被 OpenSSH 直接用。

**转成 OpenSSH 格式**（用 PuTTYgen）：
1. 打开 PuTTYgen → Load → 选你的 `.ppk`
2. Conversions → Export OpenSSH key → 存成 `id_rsa`
3. 按第二章修权限后使用

**反过来（OpenSSH → .ppk）**：
1. PuTTYgen → Load → 文件类型选 "All Files" → 选 `id_rsa`
2. Save private key → 存成 `.ppk`

> **不推荐转换器方案**：直接用 PuTTY 的话就用 .ppk，用 PowerShell/Xshell/FinalShell 就用 OpenSSH 格式，别来回折腾。

---

## 六、Xshell / FinalShell 图形化配置（不想敲命令就用这个）

**FinalShell**（推荐给新手，能直接拖文件上传）：
1. 新建连接 → SSH 连接
2. 主机：公网 IP，端口：22，用户名：root
3. 认证方式选「公钥」→ 私钥文件 → 浏览选中你的私钥文件
4. 确定 → 直接连上

**Xshell**：
1. 文件 → 新建 → 连接，主机填 IP
2. 左侧「用户身份验证」→ 方法选 Public Key
3. 浏览 → 导入你的私钥文件 → 确定

---

## 七、安全加固：禁用密码登录 + 改端口

> 这一步做完，简历上那条"配置 firewall 安全策略"才算有真材实料。
> **前提是密钥登录已经验证成功**。

### ⚠️ 前置：先在控制台放行新端口

如果打算改端口（比如 2222），**必须先在腾讯云控制台防火墙放通 2222**，
否则改完 sshd 直接连不上。

控制台 → 服务器详情 → 防火墙 → 添加规则 → 自定义 → TCP → 2222

### 步骤 1：备份配置（改崩了能救回来）

```bash
STAMP=$(date '+%F-%H%M')     # ← + 号不能丢，格式串建议用引号包住
cp -a /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$STAMP
ls -l /etc/ssh/sshd_config.bak.$STAMP
```

### 步骤 2：改配置

```bash
vim /etc/ssh/sshd_config
```

> ⚠️ **最大的坑：sshd_config 是"先出现的配置生效"**
> 你默认那份 147 行的文件里，有一行是**没有 `#` 注释、直接生效**的：
> `PasswordAuthentication yes`（在 `# To disable tunneled clear text passwords, change to no here!` 下面）。
> 如果你只是在文件末尾追加 `PasswordAuthentication no`，**它不会生效**——前面那行 `yes` 优先。
> 所以别图省事直接追加，按下面方法 A 做。

**方法 A：一键脚本改（推荐，不用手翻 147 行）**

先 `:q!` 退出 vim，执行：

```bash
cd /etc/ssh
STAMP=$(date '+%F-%H%M')     # ★ + 号不能丢，格式串用引号包住（丢掉 + 就报 invalid option -- '%'）
cp -a sshd_config sshd_config.bak.$STAMP
echo "备份文件：sshd_config.bak.$STAMP"
```

> **如果 `%` 在你这边还是被吃掉（比如粘贴时 + 号丢了、或在别的环境里执行）**，
> 换成不带 `%` 的写法，效果一样：
> ```bash
> STAMP=$(date -I)             # 只要日期：2026-10-18
> # 或
> STAMP=$(date -Iseconds)      # 精确到秒：2026-10-18T19:30:29+08:00
> ```
> 验证一下你这条命令本身没坏：
> ```bash
> date '+%F-%H%M' ; date -I
> # 预期类似：2026-10-18-1930  和  2026-10-18
> ```
>
> **为什么 `%` 会在某些地方出问题**：`%` 在不同环境里有特殊含义
> - **crontab**：`%` 被当成换行符，必须写成 `\%`（这是脚本手动跑成功、挂 cron 失败的原因之一）
> - **PowerShell**：`%` 是 `ForEach-Object` 的别名，别在 PowerShell 里直接敲 bash 命令
> - **Makefile / docker-compose**：`%` 要写成 `$$` / `%%`

# ① 把文件里"已经生效"的同名旧行全部注释掉（只动没被注释的，注释行不碰）
sed -i -E 's/^([[:space:]]*)(Port|PasswordAuthentication|PubkeyAuthentication|PermitRootLogin|PermitEmptyPasswords|KbdInteractiveAuthentication|ChallengeResponseAuthentication|GSSAPIAuthentication|UseDNS|X11Forwarding|MaxAuthTries|LoginGraceTime|ClientAliveInterval|ClientAliveCountMax|AuthorizedKeysFile)([[:space:]])/#\1\2\3/' sshd_config

# ② 追加我们自己的配置块（此时它才是这些项的第一条，必然生效）
cat >> sshd_config <<EOF

# ===== 安全加固 ${STAMP} =====
# 改端口，挡掉绝大多数扫描爆破
Port 2222
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
# 禁用密码登录
PasswordAuthentication no
# 别漏这条，否则仍能通过键盘交互方式输密码
KbdInteractiveAuthentication no
# root 允许登录，但只能用密钥
PermitRootLogin prohibit-password
PermitEmptyPasswords no
GSSAPIAuthentication no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
# 关 DNS 反解，登录会明显变快
UseDNS no
# ===== 加固结束 =====
EOF
```

> **注意：注释必须独占一行。** 写 `Port 2222 # 改端口` 这种行尾注释，
> 某些版本 `sshd -t` 会报 `garbage at end of line`，别冒这个险。

验证改动落在了正确位置：

```bash
# 列出所有"未注释"的目标项，应该只剩末尾那几行，且没有重复
grep -nE '^(Port|PasswordAuthentication|PubkeyAuthentication|KbdInteractive|PermitRootLogin|UseDNS)' /etc/ssh/sshd_config
```

预期输出（行号接近文件末尾 148~160，且没有重复项）：

```
148:Port 2222
149:PubkeyAuthentication yes
150:AuthorizedKeysFile .ssh/authorized_keys
151:PasswordAuthentication no
152:KbdInteractiveAuthentication no
153:PermitRootLogin prohibit-password
```

> 如果这里看到 60 行左右还残存一条 `PasswordAuthentication yes`（没被注释掉），
> 说明 sed 没匹配上，手工改它：vim 里 `:%s/^PasswordAuthentication yes/PasswordAuthentication no/`。

**方法 B：纯 vim 手工改（想逐条看清楚就用这个）**

在你的 vim 里，按 `Esc` 然后：

```vim
:set nu                                  " 显示行号
/^PasswordAuthentication                 " 回车，跳到那条生效的 yes
```
光标落在 `PasswordAuthentication yes` 上，依次敲：
```
cw no<Esc>          " 把 yes 改成 no
```
> 想更省事：`:%s/^PasswordAuthentication yes/PasswordAuthentication no/` 一条搞定。

然后跳到文件末尾追加其余项：
```vim
Go                                       " G 跳到末行，o 在下面新开一行并进入插入
```
粘贴上面的配置块（去掉里面已经改过的 PasswordAuthentication 那行也行，留着重复无害）。
`Esc` → `:wq` 保存退出。

> 快捷搜索词备忘：`/^Port` `/^PubkeyAuth` `/^PermitRootLogin` `/^UseDNS`
> 按 `n` 跳下一个匹配。`u` 撤销，`Ctrl+r` 重做。

### 步骤 3：★ 语法检查（不检查就直接重启 = 自杀）

```bash
sshd -t && echo "配置语法 OK"
```
> 有错误会明确告诉你第几行: `line 123: Bad configuration option: xxx`
> **只要这里报错，就绝对不要重启 sshd。**

**怎么读这个报错**（先搞清楚"伤在哪、伤多大"）：

```bash
sshd -t
# /etc/ssh/sshd_config: line 1: Bad configuration option: $OpenBSD:
# /etc/ssh/sshd_config: terminating, 1 bad configuration options
```

- `line N` = 出错的行号；`Bad configuration option: xxx` = 那个位置的第一个词被当成配置项了
- **末尾那个数字是错误总数**。sshd 会扫完整份文件再一次性报出来，
  所以写 `1 bad configuration options` 就说明**只有那一处**坏了，别慌着整份重来。
- 常见成因：注释行开头的 `#` 被删了（sed 误伤 / vim 里误操作）。

**修复（只修坏的那一行）**：

```bash
# ① 先看第 1 行现在到底长什么样（cat -A 会连行尾符号一起显示）
sed -n '1p' /etc/ssh/sshd_config | cat -A
#   正常：#       $OpenBSD: sshd_config,v 1.103 2018/04/09 20:41:22 tj Exp $$
#   异常：       $OpenBSD: sshd_config,v 1.103 2018/04/09 20:41:22 tj Exp $$   ← 开头没有 #

# ② 把 # 补回去（只动第 1 行）
sed -i '1s/^/#/' /etc/ssh/sshd_config

# ③ 复查
sshd -t && echo "配置语法 OK"
```

> 想一步到位恢复原样（含那串前导空格）：
> `sed -i '1s/^[[:space:]]*\(\$OpenBSD\)/#       \1/' /etc/ssh/sshd_config`
>
> 如果不止一行坏了、或说不清改过什么，直接从备份重来最干净：
> ```bash
> ls -l /etc/ssh/sshd_config.bak.*        # 找到刚才的备份
> cp -a /etc/ssh/sshd_config.bak.2026-10-18-1930 /etc/ssh/sshd_config
> sshd -t && echo "OK，改回来继续执行 ① ② ③"
> ```

**最终验收：看"实际生效的配置"**（比 `sshd -t` 更有说服力）

```bash
sshd -T | grep -iE '^(port|passwordauthentication|kbdinteractiveauthentication|permitrootlogin|pubkeyauthentication|usedns)'
```
预期输出（`-T` 打印的是 sshd 真正采用的最终值）：
```
port 2222
passwordauthentication no
kbdinteractiveauthentication no
permitrootlogin prohibit-password
pubkeyauthentication yes
usedns no
```
> 这一条**必须确认**：前面做的全部改动有没有真的生效，看这里一眼见分晓。
> 如果 `passwordauthentication` 还是 `yes`，说明前面还有一条生效的旧配置没清掉（回到步骤 2 的坑）。

### 步骤 4：放行新端口（三层，一层都不能少）

**4-1 腾讯云控制台防火墙**（前面已做，这里再确认一次）
```bash
# 在服务器上是查不到的，只能去控制台看：防火墙规则里要有 TCP:2222
```

**4-2 系统 firewalld**
```bash
firewall-cmd --permanent --add-port=2222/tcp
firewall-cmd --reload
firewall-cmd --list-ports
# 预期：2222/tcp 在列表里
```

**4-3 SELinux（OpenCloudOS 默认开着，不做的话 sshd 起不来）**

你那份配置文件的开头就写着这一句：
`# If you want to change the port on a SELinux system, you have to tell SELinux about this change.`

```bash
getenforce
# 输出 Enforcing 才需要下面两步

# 装 semanage 工具（没有 semanage 命令时先装）
dnf provides semanage 2>/dev/null | head -3
dnf install -y policycoreutils-python-utils

# 告诉 SELinux：2222 也是 ssh 端口
semanage port -a -t ssh_port_t -p tcp 2222
# 如果报 "already defined"，换成修改：
# semanage port -m -t ssh_port_t -p tcp 2222

# 确认
semanage port -l | grep ssh
# 预期：ssh_port_t  tcp  2222, 22
```

> 不做 4-3 的典型表现：`systemctl restart sshd` 报
> `Job for sshd.service failed ... SELinux is preventing /usr/sbin/sshd ...`
> 用 `journalctl -xe | grep -i avc` 能看到 `denied` 记录。
> 快速验证是不是 SELinux 的锅：`setenforce 0` 后再重启，能起来就确认了（**测完记得 `setenforce 1`**）。

> 图省事的替代方案：直接用 `semanage` 允许范围内的现成端口 `2222` 其实不在默认列表里，
> 所以必须显式加。不想折腾的话就不改端口，只做禁密码（收益的 80%）。

### 步骤 5：重启 sshd

```bash
systemctl restart sshd
systemctl status sshd
```

### 步骤 6：★ 另开终端测试（原终端保持别动！）

```powershell
# 开一个全新的 PowerShell 窗口
ssh -p 2222 -i C:\Users\34794\.ssh\id_ed25519 root@你的公网IP
```

**成功了再关旧窗口。** 失败就立刻回到旧窗口把配置改回去：
```bash
cp /etc/ssh/sshd_config.bak.2026-10-18 /etc/ssh/sshd_config
systemctl restart sshd
```

### 步骤 7：验证密码登录确实被禁了

```powershell
# 用一个没有私钥的终端试（应该直接拒绝）
ssh -o PubkeyAuthentication=no -p 2222 root@你的公网IP
# 预期：Permission denied (publickey).
```

### 步骤 8：看日志确认没人在爆破你

```bash
lastb | head -20                    # 失败的登录尝试
grep "Failed password" /var/log/secure | tail -20
# 更狠的做法：
journalctl -u sshd --since today | grep -c Failed
```
> 把这个数字记下来，一周后再看一次对比——
> 改端口 + 禁密码前后差异会非常夸张，是个能讲的数据点。

---

## 八、改动之后要同步更新的地方

改了端口，之前方案里的命令都得带上 `-P 端口`：

```powershell
# 上传文件
scp -P 2222 -i C:\Users\34794\.ssh\id_ed25519 ops-portfolio.tar.gz root@IP:/root/

# 免密小技巧：写进 ~/.ssh/config，以后直接 ssh lh 就能连
```

**配置 SSH 别名（强烈建议，省得每次敲一堆）**

`$HOME\.ssh\config`（Windows 上路径是 `C:\Users\34794\.ssh\config`，没有就新建）：

```ssh-config
Host lh
    HostName 你的公网IP
    Port 2222
    User root
    IdentityFile C:\Users\34794\.ssh\id_ed25519
    ServerAliveInterval 60
```

之后：
```powershell
ssh lh
scp -P 2222 file root@IP:/tmp/     # scp 用不了别名的话还是写全
scp file lh:/tmp/                   # 实际上 scp 也认别名，这样就行
```

---

## 九、排错表

| 报错 / 现象 | 原因 | 处理 |
|---|---|---|
| `Permissions for 'xxx' are too open` | Windows 私钥权限太松 | 第二章的 icacls 两步 |
| `Permission denied (publickey)` | 服务器上没你的公钥 / 权限不对 / SELinux | 检查 `~/.ssh/authorized_keys` 权限 600，跑 `restorecon -R -v ~/.ssh` |
| scp 报 `Permission denied (publickey,gssapi-keyex,...)` | 一直用控制台一键登录，本地没私钥；或 scp 没指定 `-i` | 见「情况 D」：`ssh-keygen` 生成后把公钥写进服务器 `authorized_keys` |
| `Connection closed`（scp 结尾那行） | 只是上一条认证失败的连带输出 | 别管它，看上面那行才是原因 |
| `Identity file xxx not accessible` | 只是 Warning，说明默认私钥不存在 | 不是失败原因，看紧跟其后的那行 |
| `Connection refused` | IP 打错 / 端口改过 / sshd 没监听 | 控制台核对公网 IP 与放行端口；配 `~/.ssh/config` 别名根治手误 |
| `Connection timed out` / 一直卡住 | **控制台防火墙没放行**（被丢包，不是拒绝） | 控制台 → 防火墙 → 加规则；与 refused 的区别：refused 是到了主机没人接，超时是包被丢 |
| 卡住不动直到超时 | **控制台防火墙没放行端口**（最常见） | 控制台 → 防火墙 → 加规则 |
| `Connection refused` | sshd 没监听该端口 | `ss -tlnp \| grep sshd`；检查 Port 行有没有 `#` |
| `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` | 重装系统后主机指纹变了 | `ssh-keygen -R 你的公网IP` 清掉旧指纹 |
| `no matching host key type found` | 老客户端连新服务器 | 加参数 `-o HostKeyAlgorithms=+ssh-rsa` |
| `Bad configuration option` | sshd_config 写错 | `sshd -t` 定位行号，恢复 `.bak` |
| `line 1: Bad configuration option: $OpenBSD:` | 第 1 行的 `#` 被删了，被当成配置项 | `sed -i '1s/^/#/' sshd_config` |
| `date: invalid option -- '%'` | `date` 后面的 `+` 丢了 / 格式串没加引号 | `date '+%F-%H%M'`；还不行就用 `date -I` |
| `garbage at end of line` | 写了行尾注释 `Port 2222 # 注释` | 注释改成独占一行 |
| 改完密码还能登进去 | 只改了 `PasswordAuthentication no`，没改 `KbdInteractiveAuthentication` | 两条都设 `no` |
| 改完配置像没生效 | 前面还有一条生效的旧配置（先匹配者赢） | `grep -nE '^关键字' /etc/ssh/sshd_config` 查重复 |
| 重启报 `Job for sshd.service failed` | SELinux 没放行端口 | 4-3 的 `semanage port -a` |
| 登录后立刻断开 | `PermitRootLogin` 设成 no 了 | 改成 `prohibit-password` |

**万能排查法（服务器端）**：一边 SSH 一边看日志
```bash
journalctl -u sshd -f
# 或者
tail -f /var/log/secure
```
客户端用 `-v` 看详细过程：
```powershell
ssh -vvv -i key.pem root@IP
```
> 服务端日志 + 客户端 -vvv 两边对着看，99% 的问题都能定位。

---

## 十、把自己锁在外面怎么办

腾讯云轻量给了两条后路，**不会真的没救**：

1. **控制台 → 一键登录（VNC/WebShell）**：不走 SSH，直接进系统，改回配置即可
2. **控制台 → 重置密码**：会强制停机重置 root 密码，然后可以用密码登录（前提是没禁密码）

> 所以：**改 SSH 配置前先把"当前终端不关"这条铁律守住**，真出事了还有控制台兜底。

---

## 十一、简历怎么表述这段

> "在服务器上启用 SSH 密钥登录替代密码认证：
> 生成 ed25519 密钥对，公钥写入 `authorized_keys` 并收敛目录权限（700/600），
> 关闭 `PasswordAuthentication` 与 root 密码登录，SSH 端口改为非标准端口，
> 配合 firewalld 和云平台安全组放行。
> 上线一周后 `/var/log/secure` 里的失败登录记录从每天 X 条降到 0 条。"

面试官大概率追问的两个点，提前想好：
- **为什么不直接关 root 登录？** → 单人维护的小机器禁止 root 会很不方便，
  合理做法是 `PermitRootLogin prohibit-password`（只能密钥），既保留便利性又堵死密码爆破。
- **改了 Port 就一定安全吗？** → 不算安全，只是**防扫描**。端口扫描器通常只扫 22，
  改端口能挡掉绝大部分自动化脚本；真正的防护靠密钥 + fail2ban + 只放行必要 IP。
