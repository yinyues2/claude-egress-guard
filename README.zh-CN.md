# claude-egress-guard（中文说明）

**给 Linux 上的 Claude Code 加一道「出口不对就不许启动」的闸门，打包成 agent 可用的 skill。**

在 VPS 上跑 Claude Code，最容易出问题的不是安装，而是**出口泄漏**：写在
`/etc/profile.d` 里的 `claude()` 函数只覆盖交互式 shell，Python、`sh -c`、
cron、systemd 和任何直接调用 `/usr/bin/claude` 的路径都会绕过去；代理中途挂掉时，
客户端还会悄悄从机房 IP 直连出去。

这个项目做三件事：

1. 每次启动前先核验代理的真实出口地址与国家，不符就**拒绝启动**（退出码 77）；
2. 把代理变量注入给 Claude 及其所有子进程；
3. 可选（默认开启）用 systemd 的 `IPAddressDeny=any` 把整个 Claude 进程树关进
   内核级网络白名单，只放行回环、代理上游、DNS 解析器和你显式允许的网段。

```
claude（任意入口）
  └─ /usr/local/bin/claude      闸门：核验出口 -> 注入代理 -> 内核白名单
       ├─ /usr/bin/claude       同一份闸门（npm 更新会改回符号链接，闸门会自愈）
       └─ /opt/claude-real/claude   真身（符号链接，跟随包更新）
            └─ 你的代理          127.0.0.1:1080 -> 预期的出口地址
```

## 不做什么

- 不创建、不配置、不监控代理本身，你提供已经能在目标地区落地的 HTTP/mixed 入口；
- 不是 VPN，不影响主机上其他服务，只管 Claude Code；
- 不保证账号安全，也不提供任何绕过服务商条款的功能；注册、付款、身份核验都由账号本人完成；
- 不做 IP 轮换、不重试、不回落直连。

## 快速开始

```bash
git clone https://github.com/yinyues2/claude-egress-guard.git
cd claude-egress-guard/skills/claude-egress-guard/scripts

sudo ./claude-egress-guard install \
  --proxy http://127.0.0.1:1080 \
  --exit-ip 203.0.113.10 \
  --country JP \
  --dry-run          # 先看计划，不写任何东西

sudo ./claude-egress-guard install \
  --proxy http://127.0.0.1:1080 \
  --exit-ip 203.0.113.10 \
  --country JP

sudo claude-egress-guard verify --deep
```

`203.0.113.10` 是文档专用地址（RFC 5737），请换成你代理实际报告的地址。
代理上游或内网需要保持可达时，用 `--allow 100.64.0.0/10,192.0.2.0/24` 显式放行；
回环和主机 IPv4 DNS 解析器会自动加入白名单。

## 常用命令

```bash
sudo claude-egress-guard verify          # 静态检查 + 实时出口核验
sudo claude-egress-guard verify --deep   # 额外验证「白名单确实挡住了直连」
sudo claude-egress-guard status          # 查看当前策略（代理凭据打码）
sudo claude-egress-guard drill --service my-proxy.service   # 故障演练
sudo claude-egress-guard uninstall       # 从备份恢复并移除
```

`drill` 会停掉代理单元、证明闸门拒绝启动、再拉起并等待恢复；名字里带 ssh、
tailscale、docker 的单元一律拒绝操作，中途失败也会把单元拉回运行状态。

退出码：`0` 成功，`1` 校验失败，`2` 用法错误，`77` 闸门拒绝启动。

## 包更新之后

Claude Code 自更新会重建 `/usr/bin/claude` 符号链接。闸门会在下一次 PATH 调用时
自动补回；手动 `npm i -g` 之后跑一次 `verify --deep` 即可。

## 策略文件

所有策略都在 `/etc/claude-egress-guard.conf`（权限 0600）：`PROXY`、`EXPECTED_IP`、
`EXPECTED_COUNTRY`、`STRICT_NET`、`ALLOW_IPS`、`REAL_BIN`、`CHECK_BIN`、`ALT_PATH`。
只想要出口核验、不要内核白名单：

```bash
sudo sed -i 's/^STRICT_NET=1/STRICT_NET=0/' /etc/claude-egress-guard.conf
```

## 作为 agent skill 使用

`skills/claude-egress-guard/SKILL.md` 是写给 agent 看的：如何只问 4 个必要事实、
如何按 A/B/C 三档授权推进、如何安装、验证、演练、留证，以及哪些操作绝对不碰。
把整个目录复制到你的 skills 目录即可（Hermes 用 `~/.hermes/skills/`，
Codex 用 `~/.codex/skills/`）。

## 开发与测试

```bash
bash skills/claude-egress-guard/scripts/selftest.sh   # 沙箱内 31 项自测，不需要 root 和网络
shellcheck -x -S warning skills/claude-egress-guard/scripts/*
python3 tools/leak-scan.py                                  # 提交前查隐私/凭据泄漏
```

## 许可

Apache-2.0，见 [LICENSE](LICENSE)。安全模型见 [SECURITY.md](SECURITY.md)，
数据收集见 [PRIVACY.md](PRIVACY.md)（简短版：不收集任何东西）。
