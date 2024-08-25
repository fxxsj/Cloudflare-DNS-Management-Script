#!/bin/bash

# 预设的Cloudflare API密钥和邮箱
DEFAULT_CF_API_KEY="YOUR_API_KEY"
DEFAULT_CF_EMAIL="YOUR_EMAIL"

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[1;37m'
WHITE='\033[1;37m'
NC='\033[0m' # 没有颜色

# 检查并安装必要的软件包 (jq 和 curl)
for pkg in jq curl; do
    if ! command -v $pkg &> /dev/null; then
        echo -e "${RED}$pkg 未安装，正在安装...${NC}"
        if [ -f /etc/debian_version ]; then
            sudo apt-get update
            sudo apt-get install -y $pkg
        elif [ -f /etc/redhat-release ]; then
            sudo yum install -y $pkg
        elif [ -f /etc/fedora-release ]; then
            sudo dnf install -y $pkg
        elif [ -f /etc/alpine-release ]; then
            sudo apk add $pkg
        else
            echo -e "${RED}无法确定系统类型，请手动安装 $pkg${NC}"
            exit 1
        fi
    fi
done

# 提示用户输入API密钥和邮箱
echo -e "${BLUE}请输入Cloudflare API密钥 (按回车键使用预设值 ${GREEN}${DEFAULT_CF_API_KEY}):${NC}"
read -r CF_API_KEY_INPUT

echo -e "${BLUE}请输入Cloudflare邮箱地址 (按回车键使用预设值 ${GREEN}${DEFAULT_CF_EMAIL}):${NC}"
read -r CF_EMAIL_INPUT

# 如果用户没有输入，则使用默认值
CF_API_KEY=${CF_API_KEY_INPUT:-$DEFAULT_CF_API_KEY}
CF_EMAIL=${CF_EMAIL_INPUT:-$DEFAULT_CF_EMAIL}

# 输出使用中的API密钥和邮箱，以便用户确认
echo -e "${BLUE}使用的Cloudflare API密钥: ${YELLOW}$CF_API_KEY${NC}"
echo -e "${BLUE}使用的Cloudflare邮箱地址: ${YELLOW}$CF_EMAIL${NC}"

# 当用户输入的内容与预设值不一致时，提示是否保存为预设值
if [[ "$CF_API_KEY" != "$DEFAULT_CF_API_KEY" || "$CF_EMAIL" != "$DEFAULT_CF_EMAIL" ]]; then
    # 提示用户是否要保存为预设值
    echo -e "${BLUE}是否要将这些值保存为预设值？ (y/n):${NC}"
    read -r SAVE_DEFAULTS

    if [[ $SAVE_DEFAULTS == "y" || $SAVE_DEFAULTS == "Y" ]]; then
        # 更新脚本中的预设值
        sed -i "s/DEFAULT_CF_API_KEY=\"[^\"]*\"/DEFAULT_CF_API_KEY=\"$CF_API_KEY\"/" "$0"
        sed -i "s/DEFAULT_CF_EMAIL=\"[^\"]*\"/DEFAULT_CF_EMAIL=\"$CF_EMAIL\"/" "$0"
        echo -e "${GREEN}预设值已更新并保存。${NC}"
    else
        echo -e "${YELLOW}预设值未更改。${NC}"
    fi
else
    echo -e "${YELLOW}当前使用预设值，跳过保存步骤。${NC}"
fi

# 获取所有域名
echo -e "${BLUE}正在获取所有域名...${NC}"
DOMAIN_LIST=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
    -H "X-Auth-Email: ${CF_EMAIL}" \
    -H "X-Auth-Key: ${CF_API_KEY}" \
    -H "Content-Type: application/json" | jq -r '.result[] | "\(.id) \(.name)"')

if [ -z "$DOMAIN_LIST" ]; then
    echo -e "${RED}未能获取域名列表。请检查 API 密钥和邮箱是否正确。${NC}"
    exit 1
fi

# 构建选择菜单
declare -A DOMAIN_MAP
index=1
while IFS= read -r line; do
    ZONE_ID=$(echo "$line" | awk '{print $1}')
    DOMAIN_NAME=$(echo "$line" | awk '{print $2}')
    DOMAIN_MAP[$index]="$ZONE_ID $DOMAIN_NAME"
    echo -e "${GREEN}$index) ${YELLOW}$DOMAIN_NAME${NC}"
    ((index++))
done <<< "$DOMAIN_LIST"

# 提示用户选择
echo -e "${BLUE}请输入域名编号 (1-${#DOMAIN_MAP[@]}):${NC} "
read -r USER_INPUT

# 验证用户输入
if [[ $USER_INPUT =~ ^[0-9]+$ && $USER_INPUT -ge 1 && $USER_INPUT -le ${#DOMAIN_MAP[@]} ]]; then
    ZONE_ID=$(echo "${DOMAIN_MAP[$USER_INPUT]}" | awk '{print $1}')
    DOMAIN=$(echo "${DOMAIN_MAP[$USER_INPUT]}" | awk '{print $2}')
    echo -e "${BLUE}您选择的域名是: ${YELLOW}$DOMAIN${NC}"
else
    echo -e "${RED}无效的选择，请重新运行脚本并输入有效的编号。${NC}"
    exit 1
fi

# 选择 DNS 记录类型
echo -e "${BLUE}选择要查看的DNS记录类型:${NC}"
RECORD_TYPES=("A" "AAAA" "CNAME" "MX" "TXT" "查看全部")
index=1
for type in "${RECORD_TYPES[@]}"; do
    echo -e "${GREEN}$index) ${YELLOW}$type${NC}"
    ((index++))
done

# 提示用户选择记录类型
echo -e "${BLUE}请输入记录类型编号 (1-${#RECORD_TYPES[@]}，默认为 1):${NC} "
read -r TYPE_INPUT

# 如果输入无效或为空，则默认为 1
if [[ -z $TYPE_INPUT || ! $TYPE_INPUT =~ ^[0-9]+$ || $TYPE_INPUT -lt 1 || $TYPE_INPUT -gt ${#RECORD_TYPES[@]} ]]; then
    TYPE_INPUT=1
fi

# 设置记录类型
RECORD_TYPE="${RECORD_TYPES[$((TYPE_INPUT - 1))]}"

# 获取所选类型的 DNS 记录
echo -e "${BLUE}正在获取 ${DOMAIN} 的 ${RECORD_TYPE} 类型 DNS 记录...${NC}"
if [[ $RECORD_TYPE == "查看全部" ]]; then
    DNS_RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
        -H "X-Auth-Email: ${CF_EMAIL}" \
        -H "X-Auth-Key: ${CF_API_KEY}" \
        -H "Content-Type: application/json")
else
    DNS_RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=${RECORD_TYPE}" \
        -H "X-Auth-Email: ${CF_EMAIL}" \
        -H "X-Auth-Key: ${CF_API_KEY}" \
        -H "Content-Type: application/json")
fi

# 提取记录信息，并仅保留名称和内容
RECORDS=$(echo "$DNS_RECORDS" | jq -r '.result[] | "\(.id) \(.name) -> \(.content)"')

# 获取外网IPv4地址
DEFAULT_IP=$(curl -s ipinfo.io/ip)

if [[ -z "$RECORDS" ]]; then
    echo -e "${RED}未找到 ${YELLOW}$RECORD_TYPE${RED} 类型的 DNS 记录。${NC}"
    # 没有找到记录，允许用户添加新记录
    echo -e "${BLUE}没有找到现有的 ${YELLOW}$RECORD_TYPE${BLUE} 类型的 DNS 记录。${NC}"
    RECORD_ID=""
else
    # 显示记录并选择要操作的记录
    echo -e "${BLUE}选择要操作的记录编号:${NC}"
    index=1
    while IFS= read -r record; do
        # 仅显示记录的名称和内容部分
        DISPLAY_RECORD=$(echo "$record" | awk '{print $2 " -> " $4}')
        echo -e "${GREEN}$index) ${YELLOW}$DISPLAY_RECORD${NC}"
        RECORD_LIST[$index]="$record"
        ((index++))
    done <<< "$RECORDS"

    # 提示用户选择要操作的记录
    echo -e "${BLUE}请输入记录编号 (1-${#RECORD_LIST[@]})，或按回车键添加新记录:${NC} "
    read -r RECORD_INPUT

    if [[ $RECORD_INPUT =~ ^[0-9]+$ && $RECORD_INPUT -ge 1 && $RECORD_INPUT -le ${#RECORD_LIST[@]} ]]; then
        RECORD_ID=$(echo "${RECORD_LIST[$RECORD_INPUT]}" | awk '{print $1}')
        RECORD_NAME=$(echo "${RECORD_LIST[$RECORD_INPUT]}" | awk '{print $2}')
        echo -e "${BLUE}您选择的记录 ID 是: ${YELLOW}$RECORD_ID${BLUE}，记录名称是: ${YELLOW}$RECORD_NAME${NC}"
        echo -e "${BLUE}请选择操作: ${NC}"
        echo -e "${GREEN}1) 编辑记录${NC}"
        echo -e "${GREEN}2) 删除记录${NC}"
        echo -e "${GREEN}3) 返回主菜单${NC}"
        read -r ACTION_INPUT

        case $ACTION_INPUT in
            1)
                # 编辑记录
                echo -e "${BLUE}请输入 ${RECORD_NAME} 新的记录值 (默认值: ${DEFAULT_IP}):${NC}"
                read -r NEW_CONTENT
                NEW_CONTENT=${NEW_CONTENT:-$DEFAULT_IP}

                echo -e "${BLUE}正在更新 ${RECORD_NAME} DNS 记录...${NC}"
                UPDATE_RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
                    -H "X-Auth-Email: ${CF_EMAIL}" \
                    -H "X-Auth-Key: ${CF_API_KEY}" \
                    -H "Content-Type: application/json" \
                    --data "{\"type\":\"${RECORD_TYPE}\",\"name\":\"${RECORD_NAME}\",\"content\":\"${NEW_CONTENT}\"}")

                if echo "$UPDATE_RESPONSE" | grep -q "\"success\":true"; then
                    echo -e "${GREEN}${RECORD_NAME} 记录更新成功，内容值为 ${NEW_CONTENT}!${NC}"
                else
                    echo -e "${RED}${RECORD_NAME} 记录更新失败，请检查输入或 API 状态。${NC}"
                fi
                ;;
            2)
                # 删除记录
                echo -e "${BLUE}您选择的记录是: ${YELLOW}${RECORD_NAME}${NC}"
			 echo -e "${BLUE}请输入 'delete' 以确认删除 ${RECORD_NAME} 记录，或按回车键取消:${NC}"
			 read -r CONFIRM
			
			 if [[ $CONFIRM == "delete" ]]; then
			    echo -e "${BLUE}正在删除 ${RECORD_NAME} DNS 记录...${NC}"
			    DELETE_RESPONSE=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
			        -H "X-Auth-Email: ${CF_EMAIL}" \
			        -H "X-Auth-Key: ${CF_API_KEY}" \
			        -H "Content-Type: application/json")
			
			    if echo "$DELETE_RESPONSE" | grep -q "\"success\":true"; then
			        echo -e "${GREEN}${RECORD_NAME} 记录删除成功!${NC}"
			    else
			        echo -e "${RED}${RECORD_NAME} 记录删除失败，请检查 API 状态。${NC}"
			    fi
			 else
			    echo -e "${BLUE}删除操作已取消。${NC}"
			 fi
                ;;
            3)
                # 返回主菜单
                echo -e "${BLUE}返回主菜单...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择，请重新运行脚本并输入有效的编号。${NC}"
                exit 1
                ;;
        esac
    elif [[ -z $RECORD_INPUT ]]; then
        # 用户按回车键，表示要添加新记录
        RECORD_ID=""
        RECORD_NAME=""
        # 添加新记录
        echo -e "${BLUE}请输入新记录的名称:${NC}"
        
        read -r NEW_RECORD_NAME
        echo -e "${BLUE}请输入新记录的内容 (默认值: ${DEFAULT_IP}):${NC}"
        read -r NEW_RECORD_CONTENT
        NEW_RECORD_CONTENT=${NEW_RECORD_CONTENT:-$DEFAULT_IP}

        echo -e "${BLUE}正在添加新 DNS 记录...${NC}"
        ADD_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
            -H "X-Auth-Email: ${CF_EMAIL}" \
            -H "X-Auth-Key: ${CF_API_KEY}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"${RECORD_TYPE}\",\"name\":\"${NEW_RECORD_NAME}\",\"content\":\"${NEW_RECORD_CONTENT}\"}")

        if echo "$ADD_RESPONSE" | grep -q "\"success\":true"; then
            echo -e "${GREEN}${RECORD_NAME} 新记录添加成功!${NC}"
        else
            echo -e "${RED}新记录添加失败，请检查输入或 API 状态。${NC}"
        fi
    else
        echo -e "${RED}无效的选择，请重新运行脚本并输入有效的编号。${NC}"
        exit 1
    fi
fi
