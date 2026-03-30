#!/bin/bash
# 在 cap add android 之后运行
set -e

MANIFEST="android/app/src/main/AndroidManifest.xml"
MAIN_ACTIVITY="android/app/src/main/java/com/sharon/budgettracker/MainActivity.java"

# 1. 添加文件权限 + 定位权限
if [ -f "$MANIFEST" ]; then
  if ! grep -q "WRITE_EXTERNAL_STORAGE" "$MANIFEST"; then
    sed -i 's|<uses-permission android:name="android.permission.INTERNET" />|<uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />|' "$MANIFEST"
    echo "[1/3] Storage permissions added"
  else
    echo "[1/3] Storage permissions already exist"
  fi
  if ! grep -q "ACCESS_FINE_LOCATION" "$MANIFEST"; then
    sed -i 's|<uses-permission android:name="android.permission.INTERNET" />|<uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />|' "$MANIFEST"
    echo "[2/3] Location permissions added"
  else
    echo "[2/3] Location permissions already exist"
  fi
fi

# 2. 注入 JavascriptInterface 到 MainActivity
if [ -f "$MAIN_ACTIVITY" ]; then
cat > "$MAIN_ACTIVITY" << 'JAVA'
package com.sharon.budgettracker;

import android.os.Bundle;
import android.os.Environment;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import android.widget.Toast;
import android.content.Intent;
import android.net.Uri;
import androidx.core.content.FileProvider;
import com.getcapacitor.BridgeActivity;
import java.io.File;
import java.io.FileWriter;

public class MainActivity extends BridgeActivity {

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        WebView webView = getBridge().getWebView();
        webView.addJavascriptInterface(new FileBridge(), "AndroidBridge");
    }

    class FileBridge {
        @JavascriptInterface
        public String saveBackup(String json, String fileName) {
            try {
                File dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS);
                if (!dir.exists()) dir.mkdirs();
                File file = new File(dir, fileName);
                FileWriter writer = new FileWriter(file);
                writer.write(json);
                writer.close();

                // 触发系统分享
                runOnUiThread(() -> {
                    try {
                        Uri uri = FileProvider.getUriForFile(
                            MainActivity.this,
                            getPackageName() + ".fileprovider",
                            file
                        );
                        Intent intent = new Intent(Intent.ACTION_SEND);
                        intent.setType("application/json");
                        intent.putExtra(Intent.EXTRA_STREAM, uri);
                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                        startActivity(Intent.createChooser(intent, "保存备份文件"));
                    } catch (Exception e) {
                        Toast.makeText(MainActivity.this, "已保存到 Documents/" + fileName, Toast.LENGTH_LONG).show();
                    }
                });
                return "ok";
            } catch (Exception e) {
                return "error:" + e.getMessage();
            }
        }

        @JavascriptInterface
        public String readBackup(String fileName) {
            try {
                File dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS);
                File file = new File(dir, fileName);
                if (!file.exists()) return "notfound";
                StringBuilder sb = new StringBuilder();
                java.util.Scanner scanner = new java.util.Scanner(file);
                while (scanner.hasNextLine()) sb.append(scanner.nextLine()).append("\n");
                scanner.close();
                return sb.toString();
            } catch (Exception e) {
                return "error:" + e.getMessage();
            }
        }
    }
}
JAVA
echo "[2/2] MainActivity patched"
else
  echo "[2/2] MainActivity not found, skipping"
fi

# 3. 添加 FileProvider 到 AndroidManifest
if ! grep -q "FileProvider" "$MANIFEST"; then
  sed -i 's|</application>|    <provider\n            android:name="androidx.core.content.FileProvider"\n            android:authorities="${applicationId}.fileprovider"\n            android:exported="false"\n            android:grantUriPermissions="true">\n            <meta-data\n                android:name="android.support.FILE_PROVIDER_PATHS"\n                android:resource="@xml/file_paths" />\n        </provider>\n    </application>|' "$MANIFEST"
  echo "[3/3] FileProvider added to manifest"
fi

# 4. 创建 file_paths.xml
mkdir -p android/app/src/main/res/xml
cat > android/app/src/main/res/xml/file_paths.xml << 'XML'
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <external-path name="documents" path="Documents/" />
</paths>
XML
echo "[4/4] file_paths.xml created"

echo "Patch complete"
