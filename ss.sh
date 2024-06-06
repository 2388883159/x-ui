DEFAULT_START_PORT=20000                         # 默认起始端口
DEFAULT_SOCKS_USERNAME="userb"                   # 默认socks账号
DEFAULT_SOCKS_PASSWORD="passwordb"               # 默认socks密码
DEFAULT_WS_PATH="/ws"                            # 默认ws路径
DEFAULT_UUID=$(cat /proc/sys/kernel/random/uuid) # 默认随机UUID
DEFAULT_SHADOWSOCKS_PASSWORD="8888"               # 默认shadowsocks密码
DEFAULT_SHADOWSOCKS_METHOD="aes-256-gcm"         # 默认shadowsocks加密方法

IP_ADDRESSES=($(hostname -I))
MAIN_IP=${IP_ADDRESSES[0]}

install_xray() {
	echo "安装 Xray..."

	if command -v apt-get > /dev/null; then
		apt-get update
		apt-get install unzip -y
	elif command -v yum > /dev/null; then
		yum install unzip -y
	else
		echo "未找到合适的包管理工具 (apt-get 或 yum)，请手动安装 unzip."
		exit 1
	fi

	wget https://github.com/XTLS/Xray-core/releases/download/v1.8.3/Xray-linux-64.zip
	unzip Xray-linux-64.zip
	mv xray /usr/local/bin/xrayL
	chmod +x /usr/local/bin/xrayL
	echo "Xray 安装完成."
}

generate_config() {
	config_type=$1
	port=$2
	ip=$3

	mkdir -p /etc/xrayL

	if [ "$config_type" == "socks" ]; then
		cat <<EOF > /etc/xrayL/config_${ip}.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "udp": true,
        "accounts": [
          {
            "user": "${DEFAULT_SOCKS_USERNAME}",
            "pass": "${DEFAULT_SOCKS_PASSWORD}"
          }
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "sendThrough": "${ip}"
    }
  ]
}
EOF
	elif [ "$config_type" == "vmess" ]; then
		cat <<EOF > /etc/xrayL/config_${ip}.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${DEFAULT_UUID}"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${DEFAULT_WS_PATH}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "sendThrough": "${ip}"
    }
  ]
}
EOF
	elif [ "$config_type" == "shadowsocks" ]; then
		cat <<EOF > /etc/xrayL/config_${ip}.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "protocol": "shadowsocks",
      "settings": {
        "method": "${DEFAULT_SHADOWSOCKS_METHOD}",
        "password": "${DEFAULT_SHADOWSOCKS_PASSWORD}",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "sendThrough": "${ip}"
    }
  ]
}
EOF
	fi
}

generate_service() {
	ip=$1

	cat <<EOF > /etc/systemd/system/xrayL_${ip}.service
[Unit]
Description=XrayL Service for IP ${ip}
After=network.target

[Service]
ExecStart=/usr/local/bin/xrayL -c /etc/xrayL/config_${ip}.json
Restart=on-failure
User=nobody
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

	systemctl daemon-reload
	systemctl enable xrayL_${ip}.service
	systemctl start xrayL_${ip}.service
}

config_xray() {
	config_type=$1
	read -p "起始端口 (默认 $DEFAULT_START_PORT): " START_PORT
	START_PORT=${START_PORT:-$DEFAULT_START_PORT}

	for ((i = 0; i < ${#IP_ADDRESSES[@]}; i++)); do
		PORT=$((START_PORT + i))
		IP=${IP_ADDRESSES[i]}
		generate_config $config_type $PORT $IP
		generate_service $IP
	done

	echo "生成 $config_type 配置完成"
	echo "起始端口:$START_PORT"
	echo "结束端口:$(($START_PORT + ${#IP_ADDRESSES[@]} - 1))"
	if [ "$config_type" == "socks" ]; then
		echo "socks账号:$DEFAULT_SOCKS_USERNAME"
		echo "socks密码:$DEFAULT_SOCKS_PASSWORD"
	elif [ "$config_type" == "vmess" ]; then
		echo "UUID:$DEFAULT_UUID"
		echo "ws路径:$DEFAULT_WS_PATH"
	elif [ "$config_type" == "shadowsocks" ]; then
		echo "Shadowsocks密码:$DEFAULT_SHADOWSOCKS_PASSWORD"
		echo "Shadowsocks加密方法:$DEFAULT_SHADOWSOCKS_METHOD"
	fi
}

main() {
	[ -x "$(command -v xrayL)" ] || install_xray
	if [ $# -eq 1 ]; then
		config_type="$1"
	else
		read -p "选择生成的节点类型 (socks/vmess/shadowsocks): " config_type
	fi
	if [ "$config_type" == "vmess" ]; then
		config_xray "vmess"
	elif [ "$config_type" == "socks" ]; then
		config_xray "socks"
	elif [ "$config_type" == "shadowsocks" ]; then
		config_xray "shadowsocks"
	else
		echo "未正确选择类型，使用默认socks配置."
		config_xray "socks"
	fi
}

main "$@"
