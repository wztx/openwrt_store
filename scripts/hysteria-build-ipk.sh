#!/bin/bash
# ============================================================
# Hysteria IPK 构建脚本（供 GitHub Actions 调用）
# 环境变量参数：
#   VER           - 版本号（如 2.12.3）
#   TAG           - GitHub release tag（如 app/v2.12.3）
#   IPK           - 输出ipk文件名（如 hysteria_2.12.3-1_x86_64.ipk）
#   ARCHITECTURE  - OpenWrt架构标识（x86_64 / aarch64_generic）
#   BINARY_NAME   - 官方二进制文件名（hysteria-linux-amd64 / hysteria-linux-arm64）
#   TARGET_DIR    - 输出目录（run/x86/hysteria / run/arm64/hysteria）
#   FILE_GLOB     - 旧版本删除匹配模式
# ============================================================
set -e

echo "▶ 开始构建 ${ARCHITECTURE} 架构 Hysteria v${VER}"

# 创建临时构建根目录
BUILD_ROOT=$(mktemp -d)
CTRL_DIR="${BUILD_ROOT}/control"
DATA_DIR="${BUILD_ROOT}/data"
mkdir -p "${CTRL_DIR}" "${DATA_DIR}/usr/bin"

# ---------- 1. 下载官方二进制文件 ----------
DL_URL="https://github.com/HyNetworks/hysteria/releases/download/${TAG}/${BINARY_NAME}"
echo "  下载地址: ${DL_URL}"
curl -fsSL --retry 3 --connect-timeout 30 --max-time 120 \
  -o "${DATA_DIR}/usr/bin/hysteria" "${DL_URL}"
chmod 755 "${DATA_DIR}/usr/bin/hysteria"
BIN_SIZE=$(du -h "${DATA_DIR}/usr/bin/hysteria" | cut -f1)
echo "  二进制下载完成，大小: ${BIN_SIZE}"

# ---------- 2. 生成 control 元数据文件 ----------
INST_SIZE=$(du -sk "${DATA_DIR}/usr/bin/hysteria" | cut -f1)
{
  echo "Package: hysteria"
  echo "Version: ${VER}-1"
  echo "Depends: libc"
  echo "Section: net"
  echo "Priority: optional"
  echo "Architecture: ${ARCHITECTURE}"
  echo "Installed-Size: ${INST_SIZE}"
  echo "Maintainer: HyNetworks <https://github.com/HyNetworks>"
  echo "Description: Hysteria 是一个功能丰富、抗丢包的网络代理工具"
  echo " 基于修改版 QUIC 协议，支持 VPN/转发/SOCKS5/HTTP 等多种模式，"
  echo " 在高延迟、高丢包的恶劣网络环境下性能优异。"
  echo " 本包由 GitHub Actions 自动从官方 Release 构建。"
} > "${CTRL_DIR}/control"

# ---------- 3. 安装后脚本（postinst）----------
cat > "${CTRL_DIR}/postinst" << 'EOF'
#!/bin/sh
# 安装后确保二进制有执行权限
chmod 755 /usr/bin/hysteria 2>/dev/null || true
exit 0
EOF
chmod 755 "${CTRL_DIR}/postinst"

# ---------- 4. 卸载前脚本（prerm）----------
cat > "${CTRL_DIR}/prerm" << 'EOF'
#!/bin/sh
# 卸载前尝试停止正在运行的进程
killall hysteria 2>/dev/null || true
exit 0
EOF
chmod 755 "${CTRL_DIR}/prerm"

# ---------- 5. 写入 debian-binary 版本标识 ----------
echo "2.0" > "${BUILD_ROOT}/debian-binary"

# ---------- 6. 打包 control.tar.gz 和 data.tar.gz ----------
# 使用 tar -C 切换目录，避免 cd 带来的工作目录混乱问题
tar -C "${CTRL_DIR}" -czf "${BUILD_ROOT}/control.tar.gz" control postinst prerm
tar -C "${DATA_DIR}" -czf "${BUILD_ROOT}/data.tar.gz" .

# ---------- 7. 使用 ar 工具打包最终 .ipk 文件 ----------
ar r "${BUILD_ROOT}/${IPK}" \
  "${BUILD_ROOT}/debian-binary" \
  "${BUILD_ROOT}/control.tar.gz" \
  "${BUILD_ROOT}/data.tar.gz"

# ---------- 8. 清理目标目录下的旧版本文件 ----------
mkdir -p "${TARGET_DIR}"
echo "  清理旧版本文件（仅删除匹配 ${FILE_GLOB} 的文件，保留其他文件）..."
# 使用 -maxdepth 1 只清理当前目录，不递归子目录
find "${TARGET_DIR}" -maxdepth 1 -type f -name "${FILE_GLOB}" ! -name "${IPK}" -delete -print || true

# ---------- 9. 将新ipk移动到目标位置 ----------
mv "${BUILD_ROOT}/${IPK}" "${TARGET_DIR}/"
echo "✅ ${ARCHITECTURE} 构建完成: ${TARGET_DIR}/${IPK} ($(du -h "${TARGET_DIR}/${IPK}" | cut -f1))"

# ---------- 10. 清理临时构建目录 ----------
rm -rf "${BUILD_ROOT}"

echo "  临时构建目录已清理"