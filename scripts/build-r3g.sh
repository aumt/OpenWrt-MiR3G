#!/bin/bash
# R3G ImmortalWrt 25.12.2 mesh 子设备版 —— 完整编译
#
# 用法（默认值就是本机 WSL 的布局，不传参数即可）：
#   scripts/build-r3g.sh
# 覆盖默认值：
#   SRC=~/iw2512 CFG=~/staging/R3G-Immortal.config LOG=~/build-r3g.log scripts/build-r3g.sh
#
# 配置的源真相在仓库里：configs/R3G-Immortal.config（种子配置 + 分节注释）。
# 参考：IMMORTALWRT.md
set -u

# ★★★ 必须最先做：消毒 PATH ★★★
# WSL interop 会把 Windows 的 PATH 整条注入 Linux（实测 50 条里 41 条是 /mnt/c/...）。
# 其中 `C:\Program Files\Git\ucrt64\bin` 这类项会被构建过程中重新导出的 PATH 切成
# `Files/Git/ucrt64/bin` 这种「相对路径」，OpenWrt 自带的 host find (GNU findutils 4.10.0)
# 判定其不安全，于是拒绝执行 -execdir，导致 package/install 收尾这一步
#   find <rootfs> -mindepth 1 -execdir touch -hcd "@<epoch>" "{}" +
# 以 Error 1 失败，整个 world 目标跟着挂。
# —— 这是 2026-10-02 第一次构建失败的真因（跟内核/802.11s/batman-adv 无关）。
# ImmortalWrt README 也点名了同一件事：「If you're using WSL, removing Windows folders
# from PATH is required」，并且要求 PATH 和工作目录里不能有空格或非 ASCII 字符。
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ROOT=$(cd "$(dirname "$0")/.." && pwd)

SRC=${SRC:-$HOME/iw2512}
# 配置优先取仓库里的（版本控制的源真相），仓库里没有才退回 staging 那份裸文件
if [ -z "${CFG:-}" ]; then
  if [ -f "$ROOT/configs/R3G-Immortal.config" ]; then
    CFG="$ROOT/configs/R3G-Immortal.config"
  else
    CFG="$HOME/staging/R3G-Immortal.config"
  fi
fi
LOG=${LOG:-$HOME/build-r3g.log}
VERBOSE=${VERBOSE:-$HOME/verbose.log}

cd "$SRC" || { echo "进不去 $SRC"; exit 1; }

: > "$LOG"
say() { echo "$*" | tee -a "$LOG"; }

say "=== 开始 $(date '+%F %T') ==="
say "  源码: $(git describe --tags 2>/dev/null) @ $(git rev-parse --short HEAD)"
say "  配置: $CFG"

cp "$CFG" .config
make defconfig >> "$LOG" 2>&1 || { say "★ defconfig 失败"; exit 1; }

say ""
say "=== 编译前断言：802.11s + batman-adv 必须在 ==="
FAIL=0
for s in \
  CONFIG_PACKAGE_MAC80211_MESH=y \
  CONFIG_PACKAGE_wpad-openssl=y \
  CONFIG_PACKAGE_kmod-batman-adv=y \
  CONFIG_PACKAGE_batctl-default=y \
  CONFIG_BATMAN_ADV_BATMAN_V=y \
  CONFIG_BATMAN_ADV_BLA=y \
  CONFIG_BATMAN_ADV_DAT=y \
  CONFIG_BATMAN_ADV_MCAST=y \
  CONFIG_TARGET_ramips_mt7621_DEVICE_xiaomi_mi-router-3g=y ; do
  if grep -qx "$s" .config ; then say "  ✓ $s" ; else say "  ★ 缺失 $s" ; FAIL=1 ; fi
done
[ "$FAIL" -eq 0 ] || { say "★ 断言失败，不编"; exit 1 ; }

say ""
say "  包总数 PACKAGE=y: $(grep -cE '^CONFIG_PACKAGE_[A-Za-z0-9_.+-]+=y' .config)"
say "  LuCI 应用: $(grep -oE '^CONFIG_PACKAGE_luci-app-[A-Za-z0-9_.+-]+=y' .config | wc -l) 个"
say ""

say "=== make download -j16  $(date '+%T') ==="
make download -j16 >> "$LOG" 2>&1
say "  download 退出码 $? （非 0 不影响，make 会自行重下）"

say ""
say "=== make -j16  $(date '+%T') ==="
START=$(date +%s)
make -j16 >> "$LOG" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
  # ★ OpenWrt 的 -j 模式【不把子 make 的输出写进日志】，所以失败常常是一具沉默的尸体：
  #   日志里只剩一行 "make -r world: build failed"，看不到任何原因。
  #   实测 -j16 会在 package/install 处偶发失败（同一棵树 -j1 就过）。
  #   遇到就按官方提示退回 -j1 V=s，并把详细输出留到 verbose.log 供事后定位。
  say "★ make -j16 失败（RC=$RC）。OpenWrt -j 模式不记录子 make 报错，属沉默失败。"
  say "  改用 -j1 V=s 重试，详细输出 → $VERBOSE"
  make -j1 V=s > "$VERBOSE" 2>&1
  RC=$?
  say "  -j1 V=s 退出码 $RC"
  [ "$RC" -ne 0 ] && say "  ★ 仍然失败，看 $VERBOSE 末尾 60 行"
fi
END=$(date +%s)
say "=== MAKE EXIT=$RC  用时 $(( (END-START)/60 )) 分 $(date '+%F %T') ==="
exit $RC
