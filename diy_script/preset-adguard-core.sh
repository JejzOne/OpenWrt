#!/bin/bash

[ -d files/usr/bin/AdGuardHome ] || mkdir -p files/usr/bin/AdGuardHome

LATEST_TAG=$(curl -sL https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest | grep '"tag_name"' | awk -F '"' '{print $4}')

if echo "$LATEST_TAG" | grep -Eq '^v[0-9]+(\.[0-9]+)*$'; then
  echo "📌 最新版本号: $LATEST_TAG"
else
  LATEST_TAG="v0.107.77"
  echo "⚠️ 无法获取最新版本号，使用备用版本: ${LATEST_TAG}"
  AGH_CORE="https://github.com/AdguardTeam/AdGuardHome/releases/download/${LATEST_TAG}/AdGuardHome_linux_${1}.tar.gz"
  echo "✅ 已启用备用下载地址"
fi

echo "📥 下载地址: $AGH_CORE"

wget -qO- $AGH_CORE | tar xOvz > files/usr/bin/AdGuardHome/AdGuardHome

chmod +x files/usr/bin/AdGuardHome/AdGuardHome
