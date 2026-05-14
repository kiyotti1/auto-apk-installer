#!/system/bin/sh
# 起動完了まで待機
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 5
done

# スクリプトをバックグラウンドで実行
/system/bin/auto_install.sh &
