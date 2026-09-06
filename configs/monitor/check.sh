#!/bin/sh
# /opt/stack/monitor/check.sh
# launchd から 10 分ごとに _btcnode で実行される。docs/monitoring.md を参照。
# 各チェックの OK/FAIL を state/<name>.status に残し、状態が変わったときだけ notify.sh で通知する。
set -u

# ---- 設定 ----
HOSTTAG="[studio]"
STACK=/opt/stack
DATA="${STACK}/data"
MONITOR="${STACK}/monitor"
STATE="${MONITOR}/state"
LOG="${MONITOR}/monitor.log"
BTC_CLI="${STACK}/bin/bitcoin-cli -datadir=${DATA}/bitcoin"
FULCRUM_HOST=127.0.0.1
FULCRUM_PORT=50001
TOR_HOST=127.0.0.1
TOR_PORT=9050

DISK_MIN_GB=500          # これを下回ったら FAIL
STALL_SEC=7200           # ブロック高がこの秒数進まなければ FAIL（IBD 中は判定しない）
FULCRUM_LAG_MAX=3        # bitcoind との高さの差がこれ以上なら FAIL
DAILY_REPORT=1           # 1 で日次報告を送る（未決 M1）
DAILY_HOUR=9             # この時刻以降の最初の実行で送る（未決 M2）

mkdir -p "${STATE}"
NOW=$(date +%s)
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "${LOG}"; }
notify() { "${MONITOR}/notify.sh" "${HOSTTAG} $1" || log "notify failed: $1"; }

# 前回結果と比べ、変化があったときだけ通知する
# report <name> <OK|FAIL> <異常時の文言> <復旧時の文言>
report() {
    name=$1; status=$2; fail_msg=$3; ok_msg=$4
    file="${STATE}/${name}.status"
    prev=$(cat "${file}" 2>/dev/null || echo "INIT")
    printf '%s\n' "${status}" > "${file}"
    if [ "${prev}" = "INIT" ]; then
        log "${name}: ${status} (initial)"
        return
    fi
    if [ "${prev}" != "${status}" ]; then
        log "${name}: ${prev} -> ${status}"
        if [ "${status}" = "FAIL" ]; then
            notify "異常: ${fail_msg}"
        else
            notify "復旧: ${ok_msg}"
        fi
    fi
}

# ---- 溜まった通知を先に再送 ----
PENDING="${STATE}/pending.txt"
if [ -s "${PENDING}" ]; then
    tmp="${PENDING}.tmp"; mv "${PENDING}" "${tmp}"
    while IFS= read -r line; do
        [ -n "${line}" ] && "${MONITOR}/notify.sh" "${line}" >/dev/null 2>&1 || printf '%s\n' "${line}" >> "${PENDING}"
    done < "${tmp}"
    rm -f "${tmp}"
fi

# ---- tor ----
if nc -z -w 5 "${TOR_HOST}" "${TOR_PORT}" >/dev/null 2>&1; then
    report tor OK "" "Tor"
else
    report tor FAIL "Tor が応答しません" "Tor"
fi

# ---- bitcoind ----
HEIGHT=$(${BTC_CLI} getblockcount 2>/dev/null)
case "${HEIGHT}" in
    ''|*[!0-9]*) HEIGHT=""; report bitcoind FAIL "bitcoind が応答しません" "bitcoind" ;;
    *) report bitcoind OK "" "bitcoind" ;;
esac

# ---- ブロック停滞（IBD 中は判定しない）----
if [ -n "${HEIGHT}" ]; then
    IBD=$(${BTC_CLI} getblockchaininfo 2>/dev/null | grep -o '"initialblockdownload": *[a-z]*' | grep -o '[a-z]*$')
    last_file="${STATE}/height.last"
    read -r last_h last_t < "${last_file}" 2>/dev/null || { last_h=0; last_t=${NOW}; }
    if [ "${HEIGHT}" -gt "${last_h}" ] 2>/dev/null; then
        printf '%s %s\n' "${HEIGHT}" "${NOW}" > "${last_file}"
        report stall OK "" "ブロック高の更新 (height ${HEIGHT})"
    elif [ "${IBD}" != "true" ] && [ $((NOW - last_t)) -ge "${STALL_SEC}" ]; then
        report stall FAIL "ブロック高が $((STALL_SEC / 3600)) 時間以上進んでいません (height ${HEIGHT})" "ブロック高の更新"
    fi
fi

# ---- Fulcrum（Electrum プロトコルで高さを問い合わせる）----
FHEIGHT=$(printf '{"id":1,"method":"blockchain.headers.subscribe","params":[]}\n' \
    | nc -w 10 "${FULCRUM_HOST}" "${FULCRUM_PORT}" 2>/dev/null \
    | grep -o '"height": *[0-9]*' | grep -o '[0-9]*$' | head -n 1)
case "${FHEIGHT}" in
    ''|*[!0-9]*) FHEIGHT=""; report fulcrum FAIL "Fulcrum が応答しません" "Fulcrum" ;;
    *) report fulcrum OK "" "Fulcrum" ;;
esac

if [ -n "${HEIGHT}" ] && [ -n "${FHEIGHT}" ]; then
    if [ $((HEIGHT - FHEIGHT)) -ge "${FULCRUM_LAG_MAX}" ]; then
        report fulcrum_lag FAIL "Fulcrum が $((HEIGHT - FHEIGHT)) ブロック遅れています" "Fulcrum の追随"
    else
        report fulcrum_lag OK "" "Fulcrum の追随"
    fi
fi

# ---- ディスク ----
AVAIL_KB=$(df -k "${DATA}" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "${AVAIL_KB}" ]; then
    AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
    if [ "${AVAIL_GB}" -lt "${DISK_MIN_GB}" ]; then
        report disk FAIL "ディスク残量 ${AVAIL_GB}GB" "ディスク残量 (${AVAIL_GB}GB)"
    else
        report disk OK "" "ディスク残量 (${AVAIL_GB}GB)"
    fi
else
    AVAIL_GB="?"
    report disk FAIL "データボリュームが見えません" "データボリューム"
fi

# ---- 電源 ----
if pmset -g batt 2>/dev/null | grep -q "Battery Power"; then
    POWER=BATT
    report power FAIL "バッテリー駆動（停電の可能性）" "商用電源"
else
    POWER=AC
    report power OK "" "商用電源"
fi

# ---- 日次報告 ----
if [ "${DAILY_REPORT}" = "1" ]; then
    today=$(date +%Y-%m-%d)
    hour=$(date +%H | sed 's/^0//')
    last_daily=$(cat "${STATE}/daily.last" 2>/dev/null || echo "")
    if [ "${hour}" -ge "${DAILY_HOUR}" ] && [ "${last_daily}" != "${today}" ]; then
        if notify "日次: height ${HEIGHT:-?} / fulcrum ${FHEIGHT:-?} / disk ${AVAIL_GB}GB / ${POWER}"; then
            printf '%s\n' "${today}" > "${STATE}/daily.last"
        fi
    fi
fi

exit 0
