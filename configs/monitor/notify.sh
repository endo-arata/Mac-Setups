#!/bin/sh
# /opt/stack/monitor/notify.sh "<メッセージ>"
# Telegram Bot API に Tor 経由でメッセージを送る。送れなければ pending に溜めて 1 を返す。
# 資産に紐づく情報は絶対にメッセージに含めないこと（docs/monitoring.md 3 節）。
set -u

MONITOR_DIR=/opt/stack/monitor
ENV_FILE="${MONITOR_DIR}/secrets/telegram.env"
PENDING="${MONITOR_DIR}/state/pending.txt"
SOCKS=127.0.0.1:9050

MSG="${1:-}"
[ -n "${MSG}" ] || { echo "usage: notify.sh <message>" >&2; exit 2; }

if [ ! -r "${ENV_FILE}" ]; then
    echo "notify: ${ENV_FILE} not readable" >&2
    exit 2
fi
# shellcheck disable=SC1090
. "${ENV_FILE}"

send() {
    curl --silent --show-error --max-time 60 \
        --socks5-hostname "${SOCKS}" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=$1" \
        "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        | grep -q '"ok":true'
}

if send "${MSG}"; then
    exit 0
fi

mkdir -p "$(dirname "${PENDING}")"
printf '%s\n' "${MSG}" >> "${PENDING}"
echo "notify: queued to pending (tor or network down?)" >&2
exit 1
