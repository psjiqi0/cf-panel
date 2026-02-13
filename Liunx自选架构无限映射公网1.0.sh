#!/bin/bash

# =========================================================
# Cloudflare Tunnel + Xray Linux (v3.2 修复版)
# 修复: 1. Token保存逻辑错误 2. 启动命令缺失 run 参数
# =========================================================

# --- 路径定义 ---
MAIN_DIR="/etc/cf_pro"
LOG_DIR="$MAIN_DIR/logs"
API_CONFIG_DIR="$MAIN_DIR/configs"
CREDS_DIR="$MAIN_DIR/creds"
YML_DIR="$MAIN_DIR/yml"
XRAY_DIR="$MAIN_DIR/xray"
CF_BIN="$MAIN_DIR/cloudflared"
XR_BIN="$XRAY_DIR/xray"

# --- 权限检查 ---
if [ "$EUID" -ne 0 ]; then echo "错误：必须使用 sudo 或 root 权限"; exit 1; fi

# --- 初始化环境 ---
mkdir -p "$LOG_DIR" "$XRAY_DIR" "$API_CONFIG_DIR" "$CREDS_DIR" "$YML_DIR"

# --- 依赖安装 ---
install_deps() {
    if ! command -v jq &>/dev/null || ! command -v curl &>/dev/null; then
        echo "安装必要依赖..."
        if command -v apt &>/dev/null; then apt update && apt install -y curl jq unzip ca-certificates;
        elif command -v dnf &>/dev/null; then dnf install -y curl jq unzip ca-certificates;
        elif command -v yum &>/dev/null; then yum install -y curl jq unzip ca-certificates; fi
    fi
}

# --- 核心下载 ---
download_cores() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64) CF="cloudflared-linux-amd64"; XR="Xray-linux-64.zip" ;;
        aarch64|arm64) CF="cloudflared-linux-arm64"; XR="Xray-linux-arm64-v8a.zip" ;;
        *) echo "不支持架构: $ARCH"; exit 1 ;;
    esac
    
    if [ ! -f "$CF_BIN" ]; then 
        echo "下载 cloudflared..."
        curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/$CF" -o "$CF_BIN" 
        chmod +x "$CF_BIN"
    fi
    if [ ! -f "$XR_BIN" ]; then 
        echo "下载 Xray..."
        curl -L "https://github.com/XTLS/Xray-core/releases/latest/download/$XR" -o "$MAIN_DIR/x.zip" 
        unzip -o "$MAIN_DIR/x.zip" -d "$XRAY_DIR" 
        chmod +x "$XR_BIN" 
        rm "$MAIN_DIR/x.zip"
    fi
}
ensure_bins() { if [ ! -f "$CF_BIN" ] || [ ! -f "$XR_BIN" ]; then download_cores; fi; }

# --- 功能 1: 临时隧道 (TryCloudflare) ---
start_temp_tunnel() {
    ensure_bins
    read -p "请输入要转发的本地端口: " port
    [ -z "$port" ] && port="8080"
    
    echo "正在启动临时隧道..."
    # 强制清理旧的临时日志
    rm -f "$LOG_DIR/temp.log"
    # 这里也加上 run 参数以防万一，虽然 trycloudflare 有时支持旧语法，但新版建议加上
    nohup "$CF_BIN" tunnel --url "http://localhost:$port" > "$LOG_DIR/temp.log" 2>&1 &
    
    echo "正在获取临时域名，请稍候..."
    sleep 8
    local u=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" "$LOG_DIR/temp.log" | tail -n 1)
    
    if [ -n "$u" ]; then
        echo -e "\033[32m[成功] 临时域名: $u\033[0m"
        LAST_TEMP=$u
    else
        echo -e "\033[31m[失败] 未能获取域名，请检查网络或查看日志: $LOG_DIR/temp.log\033[0m"
    fi
}

# --- 功能 2: API 注册与自动绑定 ---
register_new_api() {
    ensure_bins
    echo -e "\n\033[36m--- Cloudflare 自动化域名绑定 ---\033[0m"
    
    read -p "请输入 API Token: " CF_TOKEN
    read -p "请输入 Account ID: " CF_ACCOUNT_ID
    
    echo "正在获取您的域名列表..."
    local zones_json=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
        -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type:application/json")
    
    if [[ $(echo "$zones_json" | jq -r '.success') != "true" ]]; then
        echo -e "\033[31m验证失败，请检查 Token 权限！\033[0m"
        return
    fi

    echo -e "\n请选择域名:"
    local zone_count=$(echo "$zones_json" | jq '.result | length')
    for ((i=0; i<zone_count; i++)); do
        echo "$((i+1)). $(echo "$zones_json" | jq -r ".result[$i].name")"
    done
    read -p "选择序号: " z_idx
    [ -z "$z_idx" ] && return
    local DOMAIN_NAME=$(echo "$zones_json" | jq -r ".result[$((z_idx-1))].name")
    local ZONE_ID=$(echo "$zones_json" | jq -r ".result[$((z_idx-1))].id")

    read -p "子域名 (如 www , 留空绑定根域名): " SUB_DOMAIN
    FULL_DOMAIN="$DOMAIN_NAME"
    [ -n "$SUB_DOMAIN" ] && FULL_DOMAIN="$SUB_DOMAIN.$DOMAIN_NAME"

    echo -e "\n服务类型: 1.HTTP 2.HTTPS 3.TCP 4.SSH 5.RDP 6.UNIX 7.UNIX+TLS 8.SMB 9.HTTP_STATUS 10.BASTION"
    read -p "选择序号 (默认1): " s_type
    case $s_type in 2) TYPE="https";; 3) TYPE="tcp";; 4) TYPE="ssh";; 5) TYPE="rdp";; 6) TYPE="unix";; 7) TYPE="unix+tls";; 8) TYPE="smb";; 9) TYPE="http_status";; 10) TYPE="bastion";; *) TYPE="http";; esac

    read -p "本地端口 (Xray 端口): " LOCAL_PORT
    [ -z "$LOCAL_PORT" ] && return

    # 创建隧道
    local t_name="cf-pro-$(date +%s)"
    local create_r=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/tunnels" \
        -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" \
        --data "{\"name\":\"$t_name\"}")
    
    local tid=$(echo "$create_r" | jq -r '.result.id')
    local ttk=$(echo "$create_r" | jq -r '.result.token')
    if [ "$tid" == "null" ]; then echo "失败: $create_r"; return; fi

    # 生成凭证和配置
    echo "$ttk" | base64 -d > "$CREDS_DIR/$tid.json"
    local yml_file="$YML_DIR/$FULL_DOMAIN.yml"
    cat > "$yml_file" <<EOF
tunnel: $tid
credentials-file: $CREDS_DIR/$tid.json
loglevel: info
ingress:
  - hostname: $FULL_DOMAIN
    service: $TYPE://localhost:$LOCAL_PORT
  - service: http_status:404
EOF

    # 同步到远程并配置 DNS
    echo "正在同步配置并设置 DNS..."
    curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$tid/configurations" \
         -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" \
         --data "{\"config\": {\"ingress\": [{\"hostname\": \"$FULL_DOMAIN\", \"service\": \"$TYPE://localhost:$LOCAL_PORT\"}, {\"service\": \"http_status:404\"}]}}" > /dev/null

    local dns_data=$(jq -n --arg n "$FULL_DOMAIN" --arg c "$tid.cfargotunnel.com" '{"type":"CNAME","name":$n,"content":$c,"proxied":true,"ttl":1}')
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" --data "$dns_data" > /dev/null

    # [关键修复] 保存记录时使用 ttk (隧道Token) 而不是 CF_TOKEN (管理Token)
    jq -n --arg t "$ttk" --arg d "$FULL_DOMAIN" --arg p "$LOCAL_PORT" --arg y "$yml_file" \
       '{api_token:$t, domain:$d, local_port:$p, yml_path:$y}' > "$API_CONFIG_DIR/$FULL_DOMAIN.json"

    echo -e "\033[32m[成功] $FULL_DOMAIN 已绑定！\033[0m"
    run_single "$API_CONFIG_DIR/$FULL_DOMAIN.json"
}

# --- 运行逻辑 ---
run_single() {
    local f=$1
    local d=$(jq -r '.domain' "$f")
    local logfile="$LOG_DIR/$d.log"
    local token=$(jq -r '.api_token' "$f")

    pkill -f "cloudflared.*$token"

    echo "启动隧道: $d ..."

    # [关键修复] 增加 'run' 参数
    nohup "$CF_BIN" tunnel run --token "$token" > "$logfile" 2>&1 &

    sleep 3
    if kill -0 $! 2>/dev/null; then
        echo -e "\033[32m运行中\033[0m"
    else
        echo -e "\033[31m启动失败 (查看日志: $logfile)\033[0m"
    fi
}

list_and_run_api() {
    local files=("$API_CONFIG_DIR"/*.json)
    if [ ! -e "${files[0]}" ]; then echo "无配置"; return; fi
    echo -e "\n--- 选择域名 ---"
    for i in "${!files[@]}"; do
        local d=$(jq -r '.domain' "${files[$i]}")
        local yml=$(jq -r '.yml_path' "${files[$i]}")
        local s="停止"; ps aux | grep -q "$yml" && s="可启动多个"
        echo "$((i+1)). $d [$s]"
    done
    read -p "序号或 all: " sel
    if [ "$sel" == "all" ]; then for f in "${files[@]}"; do run_single "$f"; done
    else run_single "${files[$((sel-1))]}"; fi
}

# --- 节点生成 ---
start_node() {
    ensure_bins
    local type=$1
    local files=("$API_CONFIG_DIR"/*.json)
    echo -e "\n--- 选择节点域名 ---"
    echo "0. 使用最新生成的临时域名 ($LAST_TEMP)"
    for i in "${!files[@]}"; do echo "$((i+1)). $(jq -r '.domain' "${files[$i]}")"; done
    read -p "选择: " sel
    
    local d=""; local port=""
    if [ "$sel" == "0" ]; then
        [ -z "$LAST_TEMP" ] && { echo "无临时域名记录"; return; }
        d=$(echo "$LAST_TEMP" | sed 's|https://||')
        read -p "输入刚才设置的临时隧道端口: " port
    else
        local f="${files[$((sel-1))]}"
        [ ! -f "$f" ] && return
        d=$(jq -r '.domain' "$f")
        port=$(jq -r '.local_port' "$f")
    fi

    read -p "UUID (回车随机): " uuid; [ -z "$uuid" ] && uuid=$(cat /proc/sys/kernel/random/uuid)
    read -p "路径 (默认 /ws): " path; [ -z "$path" ] && path="/ws"

    local proto=$(echo "$type" | tr 'A-Z' 'a-z')
    cat > "$XRAY_DIR/config.json" <<EOF
{"inbounds":[{"port":$port,"listen":"127.0.0.1","protocol":"$proto","settings":{"clients":[{"id":"$uuid"}]},"streamSettings":{"network":"ws","wsSettings":{"path":"$path"}}}],"outbounds":[{"protocol":"freedom"}]}
EOF
    pkill -f "$XR_BIN"
    nohup "$XR_BIN" run -c "$XRAY_DIR/config.json" >/dev/null 2>&1 &
    
    echo -e "\n\033[32m=== $type 节点已启动 ===\033[0m"
    if [ "$type" == "VMess" ]; then
        local j="{\"v\":\"2\",\"ps\":\"CF-$d\",\"add\":\"$d\",\"port\":\"443\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"path\":\"$path\",\"tls\":\"tls\",\"sni\":\"$d\",\"host\":\"$d\"}"
        echo "vmess://$(echo -n "$j" | base64 -w 0)"
    else
        echo "vless://$uuid@$d:443?encryption=none&type=ws&security=tls&host=$d&sni=$d&path=$path#CF-$d"
    fi
}

# --- 路径说明 ---
show_paths() {
    echo -e "\n\033[33m=== 系统文件路径说明 ===\033[0m"
    echo "程序路径: $CF_BIN"
    echo "凭证目录: $CREDS_DIR  (存放 .json 密钥)"
    echo "配置目录: $YML_DIR    (存放 .yml 启动参数)"
    echo "API 记录: $API_CONFIG_DIR"
    echo "日志目录: $LOG_DIR"
    echo "Xray 配置: $XRAY_DIR/config.json"
    echo "------------------------------------------------"
    read -p "按回车返回..."
}

# --- 主菜单 ---
install_deps
while true; do
    echo -e "\n========================================无限映射====================================================
    
=类型=========================典型用途===============================说明===========================================
=TCP  	              MySQL、Redis、SSH、游戏服务器、自定义协议	   传输层转发，适合非浏览器协议。   	             
=SSH  	              Cloudflare Access 的 SSH 登录	               专为 SSH 设计，提供身份验证与访问控制。           
=RDP 	              Windows 远程桌面   Cloudflare Access 专用     专为 RDP 设计，通过 Zero Trust 控制访问。        
=HTTP  	              Web 服务（Grafana、Prometheus、API）	       Cloudflare 作为反向代理，处理 HTTP 流量。        
=HTTPS 	              本地已是 HTTPS 的服务	                       Cloudflare 不终止 TLS，直接透传 HTTPS。          
=UNIX	              Unix Socket 服务	                           用于本地 socket 文件通信，而非网络协议。          
=UNIX+TLS	      Unix Socket + TLS	                           与 UNIX 类似，但通信加密。                      
=SMB	              Windows 文件共享（445）	                   Cloudflare Access 专用，适合企业文件共享。         
=HTTP_STATUS          返回固定 HTTP 状态码	                       调试用，不代理任何实际服务。                     
=BASTION	      Zero Trust 跳板机（SSH/RDP 多跳访问）          企业级跳板机模式，用于安全访问内部资源。           
==================================================================================================================="
    echo "1. 启动临时隧道 (TryCloudflare)"
    echo "2. API 域名管理 (自动扫描/绑定)"
    echo "3. 运行/重启已存域名"
    echo "4. 启动 VMess 节点"
    echo "5. 启动 VLESS 节点"
    echo "6. 查看系统路径/说明"
    echo "7. 查看进程状态"
    echo "8. 停止所有程序"
    echo "9. 退出"
    read -p "选择: " c
    case $c in
        1) start_temp_tunnel ;;
        2) register_new_api ;;
        3) list_and_run_api ;;
        4) start_node "VMess" ;;
        5) start_node "VLESS" ;;
        6) show_paths ;;
        7) 
           echo -e "\n--- Cloudflared 进程 ---"
           ps aux | grep "cloudflared" | grep -E "config|url|token" | grep -v grep
           echo -e "--- Xray 进程 ---"
           ps aux | grep "xray" | grep "run" | grep -v grep ;;
        8) pkill -f cloudflared; pkill -f xray; echo "已停止" ;;
        9) exit 0 ;;
    esac
done