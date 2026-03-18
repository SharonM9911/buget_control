# 预算追踪 App 打包说明

## 需要提前安装的东西

1. **Node.js** https://nodejs.org  下载 LTS 版本安装
2. **Android Studio** https://developer.android.com/studio  安装后打开一次，让它下载 SDK
3. **Java JDK 17**  Android Studio 安装时会自带，一般不需要额外装

---

## 打包步骤（Mac / Linux）

```bash
# 进入项目目录
cd budget-app

# 给脚本执行权限（只需要第一次）
chmod +x build.sh

# 运行一键打包
./build.sh
```

## 打包步骤（Windows）

用命令提示符（cmd）或 PowerShell：

```cmd
cd budget-app
npm install
npx cap add android
npx cap sync android
cd android
gradlew.bat assembleDebug
```

---

## APK 在哪里

打包完成后，APK 文件在：

```
budget-app/android/app/build/outputs/apk/debug/app-debug.apk
```

把这个文件传到手机，点击安装即可。

> 安装时手机会提示"来自未知来源"，在设置里允许即可，这是正常的（没有上架应用商店的 App 都会这样提示）。

---

## 常见问题

**提示找不到 ANDROID_HOME**

在终端运行：
```bash
export ANDROID_HOME=$HOME/Library/Android/sdk   # Mac
export ANDROID_HOME=$HOME/Android/Sdk           # Linux
export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools
```

**Windows 设置环境变量**

控制面板 → 系统 → 高级系统设置 → 环境变量，新建：
- 变量名：`ANDROID_HOME`
- 变量值：`C:\Users\你的用户名\AppData\Local\Android\Sdk`

**gradlew 构建很慢**

第一次构建需要下载 Gradle，可能需要 10-20 分钟，后续会快很多。

---

## 更新 App 内容

如果以后修改了 `www/index.html`，只需要重新运行：

```bash
npx cap sync android
cd android && ./gradlew assembleDebug
```

不需要重新 `npm install` 或 `cap add android`。
