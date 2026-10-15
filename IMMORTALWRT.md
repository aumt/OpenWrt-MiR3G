# ImmortalWrt 线（分支 `r3g-imm`）

小米路由器 3G（`ramips/mt7621`）的第二套构建体系。**和 `main` / `r3g-fix` 上的 Lean LEDE 线完全独立**：不同 upstream、不同配置、不同编译方式、不同包格式。

|                  | Lean 线（`main` / `r3g-fix`）      | ImmortalWrt 线（`r3g-imm`，本文件）        |
| ---------------- | ---------------------------------- | ------------------------------------------ |
| 源码             | `coolsnowwolf/lede` master         | `immortalwrt/immortalwrt` **v25.12.2**     |
| 配置             | `configs/R3G.config`（完整 .config）| `configs/R3G-Immortal.config`（种子+注释） |
| 包管理           | opkg / `.ipk`                      | **apk / `.apk`**（`CONFIG_USE_APK=y`）     |
| 云编译           | `.github/workflows/R3G.yml`        | `.github/workflows/R3G-Immortal.yml`       |
| 本地编译         | 没做过                             | `scripts/build-r3g.sh`（WSL）              |

两边唯一的共同点是目标设备 `xiaomi_mi-router-3g`。**固件不通用，包也不通用。**

## 文件

| 文件                                | 作用                                                                                              |
| ----------------------------------- | ------------------------------------------------------------------------------------------------- |
| `configs/R3G-Immortal.config`       | 种子配置（3.4 KB，分节注释）。CI 和本地脚本都把它 `cp` 成 `.config` 再 `make defconfig`           |
| `configs/R3G-Immortal.lock.config`  | 2026-10-15 实测编译输出的完整 `.config`（316 KB）。用于审计与精确复现，**不参与编译**             |
| `scripts/build-r3g.sh`              | WSL 本地全量编译                                                                                  |
| `.github/workflows/R3G-Immortal.yml`| GitHub Actions 云编译                                                                             |

种子配置里写死了两条原则，改配置时别丢：

- 内核模块 / 编译期开关**必须内置**——自编内核的 vermagic/CRC 跟官方 kmods 源不匹配，事后 `apk add` 装不上
- 用户态包**能 apk 装的一律不内置**

## 本地编译（WSL）

```bash
scripts/build-r3g.sh
# 覆盖默认路径：
SRC=~/iw2512 CFG=~/staging/R3G-Immortal.config LOG=~/build-r3g.log scripts/build-r3g.sh
```

默认 `SRC=~/iw2512`；配置优先取仓库里的 `configs/R3G-Immortal.config`，仓库里没有才退回 `~/staging/R3G-Immortal.config`。

日志 `~/build-r3g.log`。`-j16` 沉默失败时脚本自动退回 `-j1 V=s`，详细输出写到 `~/verbose.log`。

2026-10-15 实测：16 核 `-j16`，从零全量（`build_dir` 空的）**34 分钟**编完，一次过。

## 云编译

Actions → `R3G-Immortal` → Run workflow（也支持 `repository_dispatch`）。产物走 release。

## 产物（2026-10-15 实测）

`bin/targets/ramips/mt7621/`：

| 文件                                    | 大小              | 用途                     |
| --------------------------------------- | ----------------- | ------------------------ |
| `...-squashfs-sysupgrade.bin`           | 14,029,420 B      | 日常升级                 |
| `...-squashfs-kernel1.bin`              | 3,445,338 B (3.29 MiB) | kernel 分区，**< 4 MiB 上限** |
| `...-squashfs-rootfs0.bin`              | 11,927,552 B      | rootfs 分区              |
| `...-initramfs-kernel.bin`              | 13,636,390 B      | 首次刷机 / 救援          |

清单核对：kernel `6.12.103`，`.config` 里 `CONFIG_PACKAGE_*=y` **273** 个，最终 manifest **254** 个包，含 `kmod-batman-adv 2025.4-r7` + `batctl-default 2025.4-r4` + `wpad-openssl 2025.08.26`。

`feeds.conf` 与官方 `feeds.conf.default` 逐字节相同，不需要自定义 feed。

## 已知坑（都踩过了）

1. **WSL 的 PATH 必须消毒**。`build-r3g.sh` 开头那句 `export PATH=...` 就是干这个的。不消毒 → host `find` 拒绝执行 `-execdir` → `package/install` 报 Error 1 → 整个 `world` 挂掉，而日志上完全看不出跟 PATH 有关。ImmortalWrt README 也点名了这条，并且要求 PATH 和工作目录里不能有空格或非 ASCII 字符。
2. **OpenWrt 的 `-j` 模式不记录子 make 报错**。失败时日志里只剩 `make -r world: build failed`，是一具沉默的尸体。所以脚本失败会自动退回 `-j1 V=s`。
3. **kernel 分区上限 4 MiB**。`squashfs-kernel1.bin` 必须小于它。
4. **apk ≠ ipk**。25.12 全面转 apk，Lean 那边编出来的 ipk 拿过来装不上。
5. **种子配置依赖上游默认值**。所以 CI 固定 tag `v25.12.2` 而不是 master——上游默认值一漂移，产物就不是同一个固件了。改 tag 时 CI 和本地脚本要一起改。
6. **`build_dir` + `staging_dir` 约 11 GB**。本地磁盘不够时先 `make clean`；CI 上靠 `sudo rm -rf /usr/share/dotnet ...` 腾空间。

## eBPF 现状

内核侧齐全（2026-10-15 产物内核 `.config` 实测）：

```
CONFIG_BPF=y
CONFIG_HAVE_EBPF_JIT=y        ← MIPS 可用：arch/mips/Kconfig 里 select HAVE_EBPF_JIT if !CPU_MICROMIPS
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_CGROUP_BPF=y
```

未开：`CONFIG_NET_CLS_BPF`、`CONFIG_NET_ACT_BPF`（tc 侧）、`CONFIG_LWTUNNEL_BPF`、`CONFIG_BPF_STREAM_PARSER`。

用户态 **没有内置 `libbpf` / `bpftool`**，要用就 `apk add`，或者加进种子配置。

## 待办

- [ ] 出厂默认 IP：Lean 线是 `192.168.123.1`，这条线还是 ImmortalWrt 默认的 `192.168.1.1`
- [ ] `luci-app-easymesh` / `dawn` 未内置（按「能 apk 装的一律不内置」的原则）
- [ ] 云编译首次跑通需要实测依赖清单，清单来源见 workflow 里的注释
- [ ] 可选：给 `dl/` 加 `actions/cache`，重复构建能省掉一次全量下载
