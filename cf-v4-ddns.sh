#!/usr/bin/env bash
set -o errexit  # 遇到错误退出脚本
set -o nounset  # 使用未定义变量时报错
set -o pipefail # 管道中的任何命令失败时，整个管道都失败

# Telegram Bot 配置
TELEGRAM_BOT_TOKEN="your_token"
TELEGRAM_CHAT_ID="your_chat_id"

# 默认配置
CFKEY="your_cfkey"  # API 密钥，获取方法见 Cloudflare 账户页面
CFUSER="user@mail.com"  # 用户名，通常是你的邮箱地址
CFZONE_NAME="newzone.top"  # 区域名称
CFRECORD_NAME="newhost.newzone.top"  # 要更新的主机名
CFRECORD_TYPE="AAAA"  # 记录类型，A(IPv4) 或 AAAA(IPv6)

CFTTL=120  # Cloudflare TTL 设置
FORCE=false  # 忽略本地文件，强制更新 IP
WANIPSITE="http://ipv4.icanhazip.com"  # 用于获取公网 IP 的网站

# 根据记录类型选择 IP 获取网站
case "$CFRECORD_TYPE" in
  "AAAA") WANIPSITE="http://ipv6.icanhazip.com" ;;
  "A")    WANIPSITE="http://ipv4.icanhazip.com" ;;
  *)      echo "无效的 CFRECORD_TYPE 值，只能是 A(IPv4) 或 AAAA(IPv6)"; exit 2 ;;
esac

# 获取传入参数
while getopts k:u:h:z:t:f: opts; do
  case ${opts} in
    k) CFKEY=${OPTARG} ;;
    u) CFUSER=${OPTARG} ;;
    h) CFRECORD_NAME=${OPTARG} ;;
    z) CFZONE_NAME=${OPTARG} ;;
    t) CFRECORD_TYPE=${OPTARG} ;;
    f) FORCE=${OPTARG} ;;
  esac
done

# 检查必要的设置是否存在
: "${CFKEY:?缺少 API 密钥，请在脚本中配置或使用 -k 参数传入}"
: "${CFUSER:?缺少用户名，通常是你的邮箱地址}"
: "${CFRECORD_NAME:?缺少主机名，请在脚本中配置或使用 -h 参数传入}"

# 如果主机名不是 FQDN（完全合格的域名），则假设它属于指定的区域
if [[ "$CFRECORD_NAME" != *"$CFZONE_NAME" ]] && [[ "$CFRECORD_NAME" != "$CFZONE_NAME" ]]; then
  CFRECORD_NAME="$CFRECORD_NAME.$CFZONE_NAME"
  echo " => 主机名不是 FQDN，假设为 $CFRECORD_NAME"
fi

# 获取当前和旧的公网 IP
WAN_IP=$(curl -s "$WANIPSITE")
WAN_IP_FILE="$HOME/.cf-wan_ip_$CFRECORD_NAME.txt"
OLD_WAN_IP=$(test -f "$WAN_IP_FILE" && cat "$WAN_IP_FILE" || echo "")

# 如果公网 IP 未改变且未设置强制更新，则退出
if [[ "$WAN_IP" == "$OLD_WAN_IP" ]] && [[ "$FORCE" == false ]]; then
  echo "公网 IP 未改变，如需强制更新请使用 -f true"
  exit 0
fi

# 获取 zone_identifier 和 record_identifier
ID_FILE="$HOME/.cf-id_$CFRECORD_NAME.txt"
if [[ -f "$ID_FILE" ]] && [[ $(wc -l < "$ID_FILE") -eq 4 ]] && \
   [[ "$(sed -n '3p' "$ID_FILE")" == "$CFZONE_NAME" ]] && \
   [[ "$(sed -n '4p' "$ID_FILE")" == "$CFRECORD_NAME" ]]; then
  CFZONE_ID=$(sed -n '1p' "$ID_FILE")
  CFRECORD_ID=$(sed -n '2p' "$ID_FILE")
else
  echo "更新 zone_identifier 和 record_identifier"
  CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" \
              -H "X-Auth-Email: $CFUSER" -H "X-Auth-Key: $CFKEY" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1)
  CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME" \
                -H "X-Auth-Email: $CFUSER" -H "X-Auth-Key: $CFKEY" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1)
  echo "$CFZONE_ID" > $ID_FILE
  echo "$CFRECORD_ID" >> $ID_FILE
  echo "$CFZONE_NAME" >> $ID_FILE
  echo "$CFRECORD_NAME" >> $ID_FILE
fi

# 如果公网 IP 改变，更新 Cloudflare DNS 记录
echo "更新 DNS 到 $WAN_IP"
RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
  -H "X-Auth-Email: $CFUSER" \
  -H "X-Auth-Key: $CFKEY" \
  -H "Content-Type: application/json" \
  --data "{\"id\":\"$CFZONE_ID\",\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$WAN_IP\", \"ttl\":$CFTTL}")

if echo "$RESPONSE" | grep -q "\"success\":true"; then
  echo "更新成功！"
  echo "$WAN_IP" > "$WAN_IP_FILE"
  
  # 发送 Telegram 通知
  MESSAGE="📮 *DNS更新成功！* 
———————————————
域名: \`$CFRECORD_NAME\`    
新IP: \`$WAN_IP\`"
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  -d chat_id="$TELEGRAM_CHAT_ID" \
  -d parse_mode="Markdown" \
  -d text="$MESSAGE" \
  > /dev/null

else
  echo "更新失败 :("
  echo "响应: $RESPONSE"
  exit 1
fi
