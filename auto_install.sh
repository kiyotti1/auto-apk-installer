#!/system/bin/sh

LOG="/sdcard/install_log.txt"
LAST=""
LOCK="/data/local/tmp/auto_install.lock"

echo "MODULE START $(date)" > "$LOG"

# 多重起動防止
if [ -f "$LOCK" ]; then
  echo "LOCK EXISTS" >> "$LOG"
  exit 1
fi

touch "$LOCK"

cleanup() {
  rm -f "$LOCK"
}
trap cleanup EXIT

# logcat初期化
logcat -c
sleep 0.3

# packageinstaller関連だけ監視
logcat -v brief | grep --line-buffered packageinstaller | while read -r line
do
  case "$line" in
    *no_backup/package*.apk*)
      # APKパス抽出
      APK=$(echo "$line" | grep -oE '/[^ ]+\.apk' | head -n 1)

      [ -z "$APK" ] && continue
      [ "$APK" = "$LAST" ] && continue

      LAST="$APK"

      echo "Detected: $APK" >> "$LOG"

      # APK出現待ち
      COUNT=0
      while [ ! -f "$APK" ]
      do
        sleep 0.1
        COUNT=$((COUNT+1))

        if [ "$COUNT" -gt 50 ]; then
          echo "FILE TIMEOUT" >> "$LOG"
          continue 2
        fi
      done

      # PackageInstaller描画前に即殺
      am force-stop com.google.android.packageinstaller >/dev/null 2>&1
      am force-stop com.android.packageinstaller >/dev/null 2>&1

      # 書き込み安定待ち
      OLD=0
      SAME=0

      while true
      do
        SIZE=$(stat -c%s "$APK" 2>/dev/null)

        [ -z "$SIZE" ] && sleep 0.1 && continue

        if [ "$SIZE" = "$OLD" ]; then
          SAME=$((SAME+1))
        else
          SAME=0
        fi

        OLD="$SIZE"

        [ "$SAME" -ge 3 ] && break

        sleep 0.2
      done

      echo "SIZE=$SIZE" >> "$LOG"

      TMP="/data/local/tmp/install_$$.apk"

      cp "$APK" "$TMP"

      if [ ! -f "$TMP" ]; then
        echo "COPY FAILED" >> "$LOG"
        continue
      fi

      sync

      # データ消失対策
      settings put global force_allow_on_external 0

      echo "INSTALLING..." >> "$LOG"

      # Transaction recovery待ち
      sleep 1.5

      # 一瞬Permissive
      setenforce 0

      pm install -r "$TMP" >> "$LOG" 2>&1

      RET=$?

      setenforce 1

      echo "RESULT=$RET" >> "$LOG"
      echo "DONE $(date)" >> "$LOG"

      rm -f "$TMP"
    ;;
  esac
done