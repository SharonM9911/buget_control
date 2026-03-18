#!/bin/bash
# 在 cap add android 之后运行，添加文件读写权限
MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ]; then
  if ! grep -q "WRITE_EXTERNAL_STORAGE" "$MANIFEST"; then
    sed -i 's|<uses-permission android:name="android.permission.INTERNET" />|<uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />|' "$MANIFEST"
    echo "Permissions added"
  else
    echo "Permissions already exist"
  fi
else
  echo "Manifest not found, run after cap add android"
fi
