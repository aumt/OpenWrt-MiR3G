#!/bin/bash
# 本脚本由 workflow 以「可执行文件」方式调用（$GITHUB_WORKSPACE/$PACKS），
# 因此走的是它自己的 shebang，子 bash 默认**不带 -e**：任何一行失败都不会中止，
# 整个脚本会用**最后一行**的退出码收场。2026-10-02 之前这里正是这么翻的车 ——
# 最后一行 luci-app-vssr 的仓库已 404，于是全部 5 行跑完后以一个 128 收场，
# "Load custom configuration" 步骤失败，而日志里看着像只有最后一行有问题。
set -e

# 以下 3 个仓库仍然存在，但它们对应的包在 configs/R3G.config 里都是 no
# （luci-app-oaf / luci-app-pushbot / lua-maxminddb），拉下来并不会编进固件。
# 保留是为了以后想启用时只改 config 即可；不想留就直接删掉这几行。
git clone https://github.com/destan19/OpenAppFilter package/OpenAppFilter
git clone https://github.com/zzsj0928/luci-app-pushbot package/luci-app-pushbot
git clone https://github.com/jerrykuku/lua-maxminddb.git package/lua-maxminddb

# 已删除的两行（仓库不存在，clone 必然失败）：
#   git clone https://github.com/bigbugcc/OpenwrtApp     package/OpenwrtApp
#   git clone https://github.com/jerrykuku/luci-app-vssr package/luci-app-vssr
