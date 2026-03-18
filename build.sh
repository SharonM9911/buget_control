#!/bin/bash
# 一键打包脚本 - 在 budget-app 目录下运行
# 前提：已安装 Node.js、Android Studio、配置好 ANDROID_HOME

set -e
echo "====== 预算追踪 App 打包脚本 ======"

# 1. 安装依赖
echo "[1/4] 安装依赖..."
npm install

# 2. 添加 Android 平台（首次运行）
if [ ! -d "android" ]; then
  echo "[2/4] 初始化 Android 平台..."
  npx cap add android
else
  echo "[2/4] Android 平台已存在，跳过"
fi

# 3. 同步 web 文件到 Android 项目
echo "[3/4] 同步文件..."
npx cap sync android

# 4. 构建 APK
echo "[4/4] 构建 APK..."
cd android
./gradlew assembleDebug

echo ""
echo "====== 完成！======"
echo "APK 路径："
find . -name "*.apk" -path "*/debug/*" | head -5
