#!/bin/bash

# HAProxy Monitor - Script de Instalação Automática
# Uso: curl -sSL https://raw.githubusercontent.com/seu-repo/haproxy-monitor/main/install.sh | sudo bash
# Ou: wget -qO- https://raw.githubusercontent.com/seu-repo/haproxy-monitor/main/install.sh | sudo bash

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações
SERVICE_NAME="haproxy-monitor"
INSTALL_DIR="/opt/haproxy-monitor"
SERVICE_USER="haproxy-monitor"
PYTHON_SCRIPT="haproxy_monitor.py"

# Função para imprimir com cores
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

# Verificar se está rodando como root
if [[ $EUID -ne 0 ]]; then
   print_error "Este script deve ser executado como root (use sudo)"
   exit 1
fi

print_status "Iniciando instalação do HAProxy Monitor..."

# Detectar distribuição Linux
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    print_error "Não foi possível detectar a distribuição Linux"
    exit 1
fi

print_status "Detectado: $PRETTY_NAME"

# Atualizar repositórios e instalar dependências
print_status "Instalando dependências..."
case $DISTRO in
    ubuntu|debian)
        apt update
        apt install -y python3 python3-pip python3-venv
        ;;
    fedora|rhel|centos|rocky|alma)
        if command -v dnf &> /dev/null; then
            dnf install -y python3 python3-pip python3-virtualenv
        else
            yum install -y python3 python3-pip python3-virtualenv
        fi
        ;;
    arch|manjaro)
        pacman -Sy --noconfirm python python-pip python-virtualenv
        ;;
    *)
        print_warning "Distribuição não reconhecida. Tentando instalar Python3 e pip..."
        if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null; then
            print_error "Por favor, instale Python3 e pip3 manualmente"
            exit 1
        fi
        ;;
esac

# Criar usuário do serviço
print_status "Criando usuário do serviço..."
if ! id "$SERVICE_USER" &>/dev/null; then
    useradd --system --home-dir $INSTALL_DIR --shell /bin/false $SERVICE_USER
    print_success "Usuário $SERVICE_USER criado"
else
    print_warning "Usuário $SERVICE_USER já existe"
fi

# Criar diretório de instalação
print_status "Criando diretório de instalação..."
mkdir -p $INSTALL_DIR
chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR

# Criar ambiente virtual Python
print_status "Configurando ambiente virtual Python..."
su - $SERVICE_USER -s /bin/bash -c "python3 -m venv $INSTALL_DIR/venv"

# Instalar dependências Python
print_status "Instalando dependências Python..."
su - $SERVICE_USER -s /bin/bash -c "$INSTALL_DIR/venv/bin/pip install rich"

# Criar script Python
print_status "Criando script do HAProxy Monitor..."
cat > $INSTALL_DIR/$PYTHON_SCRIPT << 'EOF'
import socket, threading, select, time, sys
from collections import defaultdict
from rich.console import Console
from rich.table import Table
from rich.live import Live
from rich.panel import Panel
from rich.layout import Layout
from rich.text import Text
from datetime import datetime

DST_HOST = None
stats = {'tcp_connections': 0, 'udp_sessions': 0, 'total_bytes': 0, 'java_players': set(), 'bedrock_players': set(), 'voice_chat_users': set(), 'start_time': time.time()}
clients = {}
tcp_clients = {}
console = Console()

def resolve_dns(hostname): return socket.gethostbyname(hostname) if hostname else hostname

def dns_refresh_thread(hostname):
    global DST_HOST
    while True:
        time.sleep(30); new_ip = resolve_dns(hostname); DST_HOST = new_ip if new_ip != DST_HOST and new_ip != hostname else DST_HOST

def create_dashboard():
    layout = Layout(); layout.split_column(Layout(name="header", size=3), Layout(name="body")); layout["body"].split_row(Layout(name="stats"), Layout(name="info"))
    uptime = int(time.time() - stats['start_time']); hours, remainder = divmod(uptime, 3600); minutes, seconds = divmod(remainder, 60)
    
    header = Panel(Text(f"HAProxy Monitor - Uptime: {hours:02d}:{minutes:02d}:{seconds:02d}", style="bold cyan", justify="center"), style="blue")
    
    table = Table(title="Player Stats", style="cyan"); table.add_column("Type", style="magenta"); table.add_column("Count", justify="right", style="green")
    table.add_row("Java Players", str(len(stats['java_players'])))
    table.add_row("Bedrock Players", str(len(stats['bedrock_players'])))
    table.add_row("Voice Chat Users", str(len(stats['voice_chat_users'])))
    
    info_table = Table(title="Connection Stats", style="cyan"); info_table.add_column("Metric", style="magenta"); info_table.add_column("Value", justify="right", style="green")
    info_table.add_row("TCP Connections", str(len(tcp_clients))); info_table.add_row("UDP Sessions", str(len(clients))); info_table.add_row("Total Bytes", f"{stats['total_bytes']:,}")
    info_table.add_row("Target Host", DST_HOST or "Resolving...")
    
    layout["header"].update(header); layout["stats"].update(Panel(table, border_style="blue")); layout["info"].update(Panel(info_table, border_style="green"))
    return layout

def tcp_proxy(src_port, dst_host_func, dst_port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM); sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); sock.bind(('0.0.0.0', src_port)); sock.listen(5)
    while True: client, addr = sock.accept(); stats['tcp_connections'] += 1; tcp_clients[addr] = {'socket': client, 'connected': time.time()}; threading.Thread(target=lambda: handle_tcp_mc(client, addr, dst_host_func, dst_port), daemon=True).start()

def handle_tcp_mc(client, client_addr, dst_host_func, dst_port):
    try: dst_host = dst_host_func(); server = socket.socket(socket.AF_INET, socket.SOCK_STREAM); server.connect((dst_host, dst_port)); server.send(f"PROXY TCP4 {client_addr[0]} {dst_host} {client_addr[1]} {dst_port}\r\n".encode()); stats['java_players'].add(client_addr[0]); threading.Thread(target=lambda: forward_data(client, server, client_addr), daemon=True).start(); threading.Thread(target=lambda: forward_data(server, client, client_addr), daemon=True).start()
    except: client.close(); cleanup_client(client_addr)

def udp_proxy(src_port, dst_host_func, dst_port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); sock.bind(('0.0.0.0', src_port))
    while True:
        try: data, addr = sock.recvfrom(65536); stats['total_bytes'] += len(data); dst_host = dst_host_func(); (handle_bedrock_traffic if src_port == 19132 else handle_voice_chat if src_port == 24454 else handle_generic_udp)(sock, addr, dst_host, dst_port, data)
        except: pass

def handle_bedrock_traffic(proxy_sock, client_addr, dst_host, dst_port, data): (handle_bedrock_ping if len(data) >= 1 and data[0] == 0x01 else lambda *args: (stats['bedrock_players'].add(client_addr[0]), handle_generic_udp(*args)))(proxy_sock, client_addr, dst_host, dst_port, data)

def handle_voice_chat(proxy_sock, client_addr, dst_host, dst_port, data): stats['voice_chat_users'].add(client_addr[0]); handle_generic_udp(proxy_sock, client_addr, dst_host, dst_port, data)

def handle_generic_udp(proxy_sock, client_addr, dst_host, dst_port, data):
    if client_addr not in clients: clients[client_addr] = {'socket': socket.socket(socket.AF_INET, socket.SOCK_DGRAM), 'last_seen': time.time()}; stats['udp_sessions'] += 1; threading.Thread(target=lambda: udp_response(clients[client_addr]['socket'], proxy_sock, client_addr), daemon=True).start()
    clients[client_addr]['socket'].sendto(data, (dst_host, dst_port)); clients[client_addr]['last_seen'] = time.time()

def handle_bedrock_ping(proxy_sock, client_addr, dst_host, dst_port, data):
    try: server_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); server_sock.settimeout(2); server_sock.sendto(data, (dst_host, dst_port)); response, _ = server_sock.recvfrom(65536); proxy_sock.sendto(response, client_addr); server_sock.close()
    except: pass

def udp_response(client_sock, proxy_sock, client_addr):
    while True:
        try: data, _ = client_sock.recvfrom(65536); stats['total_bytes'] += len(data); proxy_sock.sendto(data, client_addr)
        except: break

def forward_data(src, dst, client_addr):
    try:
        while True: ready, _, _ = select.select([src], [], [], 1); (lambda: (stats.__setitem__('total_bytes', stats['total_bytes'] + len(data)), dst.sendall(data)) if (data := src.recv(4096)) else (_ for _ in ()).throw(StopIteration))() if ready else None
    except: pass
    finally: src.close(); dst.close(); cleanup_client(client_addr)

def cleanup_client(addr): tcp_clients.pop(addr, None); stats['java_players'].discard(addr[0])

def cleanup_old_connections():
    while True: current = time.time(); [clients[addr]['socket'].close() or clients.pop(addr) or stats['bedrock_players'].discard(addr[0]) or stats['voice_chat_users'].discard(addr[0]) for addr in list(clients.keys()) if current - clients[addr]['last_seen'] > 60]; time.sleep(30)

if __name__ == '__main__':
    HOSTNAME = 'hm.cnq.wtf'; DST_HOST = resolve_dns(HOSTNAME)
    threading.Thread(target=dns_refresh_thread, args=(HOSTNAME,), daemon=True).start()
    threading.Thread(target=tcp_proxy, args=(25565, lambda: DST_HOST, 25565), daemon=True).start()
    threading.Thread(target=udp_proxy, args=(24454, lambda: DST_HOST, 24454), daemon=True).start()
    threading.Thread(target=udp_proxy, args=(19132, lambda: DST_HOST, 19132), daemon=True).start()
    threading.Thread(target=cleanup_old_connections, daemon=True).start()
    
    try:
        with Live(create_dashboard(), refresh_per_second=2, screen=True) as live:
            while True: live.update(create_dashboard()); time.sleep(0.5)
    except KeyboardInterrupt: console.print("\n[red]Parando servidor...[/red]")
EOF

# Definir permissões
chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR/$PYTHON_SCRIPT
chmod +x $INSTALL_DIR/$PYTHON_SCRIPT

# Criar arquivo de configuração (opcional)
print_status "Criando arquivo de configuração..."
cat > $INSTALL_DIR/config.env << 'EOF'
# Configurações do HAProxy Monitor
HOSTNAME=hm.cnq.wtf
JAVA_PORT=25565
VOICE_PORT=24454
BEDROCK_PORT=19132
EOF

chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR/config.env

# Criar serviço systemd
print_status "Criando serviço systemd..."
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=HAProxy Monitor - Minecraft Proxy Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin
EnvironmentFile=$INSTALL_DIR/config.env
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/$PYTHON_SCRIPT
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

# Configurações de segurança
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# Recarregar systemd
print_status "Recarregando systemd..."
systemctl daemon-reload

# Habilitar serviço para inicialização automática
print_status "Habilitando serviço para inicialização automática..."
systemctl enable $SERVICE_NAME

# Configurar firewall (se necessário)
print_status "Configurando firewall..."
if command -v ufw &> /dev/null; then
    ufw allow 25565/tcp comment "Minecraft Java"
    ufw allow 19132/udp comment "Minecraft Bedrock"
    ufw allow 24454/udp comment "Voice Chat"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=25565/tcp --add-port=19132/udp --add-port=24454/udp
    firewall-cmd --reload
fi

# Iniciar serviço
print_status "Iniciando serviço..."
systemctl start $SERVICE_NAME

# Verificar status
sleep 2
if systemctl is-active --quiet $SERVICE_NAME; then
    print_success "HAProxy Monitor instalado e iniciado com sucesso!"
else
    print_error "Falha ao iniciar o serviço"
    systemctl status $SERVICE_NAME
    exit 1
fi

# Criar scripts de gerenciamento
print_status "Criando scripts de gerenciamento..."
cat > /usr/local/bin/haproxy-monitor << 'EOF'
#!/bin/bash
SERVICE_NAME="haproxy-monitor"

case "$1" in
    start)
        echo "Iniciando HAProxy Monitor..."
        sudo systemctl start $SERVICE_NAME
        ;;
    stop)
        echo "Parando HAProxy Monitor..."
        sudo systemctl stop $SERVICE_NAME
        ;;
    restart)
        echo "Reiniciando HAProxy Monitor..."
        sudo systemctl restart $SERVICE_NAME
        ;;
    status)
        sudo systemctl status $SERVICE_NAME
        ;;
    logs)
        sudo journalctl -u $SERVICE_NAME -f
        ;;
    enable)
        echo "Habilitando inicialização automática..."
        sudo systemctl enable $SERVICE_NAME
        ;;
    disable)
        echo "Desabilitando inicialização automática..."
        sudo systemctl disable $SERVICE_NAME
        ;;
    uninstall)
        echo "Desinstalando HAProxy Monitor..."
        sudo systemctl stop $SERVICE_NAME
        sudo systemctl disable $SERVICE_NAME
        sudo rm -f /etc/systemd/system/${SERVICE_NAME}.service
        sudo rm -rf /opt/haproxy-monitor
        sudo userdel haproxy-monitor 2>/dev/null || true
        sudo rm -f /usr/local/bin/haproxy-monitor
        sudo systemctl daemon-reload
        echo "HAProxy Monitor desinstalado!"
        ;;
    *)
        echo "Uso: $0 {start|stop|restart|status|logs|enable|disable|uninstall}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/haproxy-monitor

print_success "Instalação concluída!"
echo
echo -e "${YELLOW}=== INFORMAÇÕES DE USO ===${NC}"
echo -e "Serviço: ${BLUE}$SERVICE_NAME${NC}"
echo -e "Diretório: ${BLUE}$INSTALL_DIR${NC}"
echo -e "Usuário: ${BLUE}$SERVICE_USER${NC}"
echo
echo -e "${YELLOW}=== COMANDOS ÚTEIS ===${NC}"
echo -e "Status do serviço: ${GREEN}haproxy-monitor status${NC}"
echo -e "Ver logs: ${GREEN}haproxy-monitor logs${NC}"
echo -e "Parar serviço: ${GREEN}haproxy-monitor stop${NC}"
echo -e "Iniciar serviço: ${GREEN}haproxy-monitor start${NC}"
echo -e "Reiniciar serviço: ${GREEN}haproxy-monitor restart${NC}"
echo -e "Desinstalar: ${GREEN}haproxy-monitor uninstall${NC}"
echo
echo -e "${YELLOW}=== PORTAS ABERTAS ===${NC}"
echo -e "Minecraft Java: ${BLUE}25565/tcp${NC}"
echo -e "Minecraft Bedrock: ${BLUE}19132/udp${NC}"
echo -e "Voice Chat: ${BLUE}24454/udp${NC}"
echo
echo -e "${GREEN}HAProxy Monitor está rodando em segundo plano!${NC}"
