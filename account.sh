#!/bin/bash
set -e

NAMES_FILE="names.txt"
ACCOUNT_FILE="account.txt"

if [ ! -f "$NAMES_FILE" ]; then
    echo "❌ 错误: $NAMES_FILE 文件不存在！"
    exit 1
fi

# 1. 随机获取姓名并生成纯文本用户名
LINE=$(sed '1d' "$NAMES_FILE" | grep -v '^$' | shuf -n 1)
FIRST_NAME=$(echo "$LINE" | awk '{print (RANDOM%2==0)?$1:$2}')
LAST_NAME=$(echo "$LINE" | awk '{print $3}')
RANDOM_DIGITS=$(shuf -i 100-999999 -n 1)

RAW_USERNAME="${FIRST_NAME,,}${LAST_NAME,,}${RANDOM_DIGITS}"
EMAIL="${RAW_USERNAME}@outlook.com"

# 2. 生成随机密码 (8-12位：1位小写字母开头 + 7-11位小写字母与数字组合)
PASS_LEN=$(shuf -i 8-12 -n 1)
FIRST_CHAR=$(tr -dc 'a-z' < /dev/urandom | head -c 1)
REST_CHAR=$(tr -dc 'a-z0-9' < /dev/urandom | head -c $((PASS_LEN - 1)))
RANDOM_PASS="${FIRST_CHAR}${REST_CHAR}"

# 3. 随机出生年份
BIRTH_YEAR=$(shuf -i 1980-2005 -n 1)

# 4. 按 pyautogui 对应顺序写入文件 (共 5 行)
cat <<EOT > "$ACCOUNT_FILE"
$EMAIL
$RANDOM_PASS
$BIRTH_YEAR
$FIRST_NAME
$LAST_NAME
EOT

echo "✅ 账号数据生成成功！写入内容如下："
cat "$ACCOUNT_FILE"
