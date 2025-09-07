#!/bin/bash

# Script de instalação e configuração do HAProxy
# Domínio: hm.cnq.wtf
# Portas: 25565, 24454, 19232 (TCP e UDP)

set -e  # Parar em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis
DOMAIN="hm.cnq.wtf"
PORTS="25565 24454 19232"
LOG_FILE="/var/log/haproxy_install.log"
CONFIG_FILE="/etc/haproxy/haproxy.cfg"
BACKUP_CONFIG="/etc/haproxy/haproxy.cfg.backup.$(date +%Y%m%d_%H%M%S)"

# Função para log
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

# Função para log de erro
log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERRO:${NC} $1" | tee -a "$LOG_FILE"
}

# Função para log de sucesso
log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCESSO:${NC} $1" | tee -a "$LOG_FILE"
}

# Função para log de warning
log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] AVISO:${NC} $1" | tee -a "$LOG_FILE"
}

# Verificar se é executado como root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Este script deve ser executado como root ou com sudo"
        exit 1
    fi
}

# Detectar distribuição Linux
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    else
        log_error "Não foi possível detectar a distribuição Linux"
        exit 1
    fi
    log "Distribuição detectada: $DISTRO $VERSION"
}

# Instalar HAProxy
install_haproxy() {
    log "Iniciando instalação do HAProxy..."
    
    case $DISTRO in
        ubuntu|debian)
            apt update
            apt install -y haproxy
            ;;
        centos|rhel|rocky|almalinux)
            yum install -y epel-release
            yum install -y haproxy
            ;;
        fedora)
            dnf install -y haproxy
            ;;
        *)
            log_error "Distribuição não suportada: $DISTRO"
            exit 1
            ;;
    esac
    
    log_success "HAProxy instalado com sucesso"
}

# Fazer backup da configuração atual
backup_config() {
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$BACKUP_CONFIG"
        log "Backup da configuração criado: $BACKUP_CONFIG"
    fi
}

# Criar configuração do HAProxy
create_config() {
    log "Criando configuração do HAProxy..."
    
    cat > "$CONFIG_FILE" << EOF
# Configuração HAProxy para $DOMAIN
# Gerado em: $(date)

global
    log stdout local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    mode tcp
    log global
    option tcplog
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

# Frontend para porta 25565 (TCP)
frontend minecraft_tcp_25565
    bind *:25565
    mode tcp
    default_backend minecraft_backend_25565

# Backend para porta 25565 (TCP)
backend minecraft_backend_25565
    mode tcp
    balance roundrobin
    # Adicione seus servidores backend aqui
    # server server1 192.168.1.100:25565 check
    # server server2 192.168.1.101:25565 check

# Frontend para porta 24454 (TCP)
frontend service_tcp_24454
    bind *:24454
    mode tcp
    default_backend service_backend_24454

# Backend para porta 24454 (TCP)
backend service_backend_24454
    mode tcp
    balance roundrobin
    # Adicione seus servidores backend aqui
    # server server1 192.168.1.100:24454 check
    # server server2 192.168.1.101:24454 check

# Frontend para porta 19232 (TCP)
frontend service_tcp_19232
    bind *:19232
    mode tcp
    default_backend service_backend_19232

# Backend para porta 19232 (TCP)
backend service_backend_19232
    mode tcp
    balance roundrobin
    # Adicione seus servidores backend aqui
    # server server1 192.168.1.100:19232 check
    # server server2 192.168.1.101:19232 check

# Página de estatísticas
listen stats
    bind *:8080
    mode http
    stats enable
    stats uri /stats
    stats refresh 5s
    stats realm HAProxy\ Statistics
    stats auth admin:admin
    stats admin if TRUE

EOF

    log_success "Configuração do HAProxy criada"
}

# Configurar firewall
configure_firewall() {
    log "Configurando firewall..."
    
    # Detectar firewall
    if command -v ufw >/dev/null 2>&1; then
        # Ubuntu/Debian UFW
        ufw allow 25565/tcp
        ufw allow 25565/udp
        ufw allow 24454/tcp
        ufw allow 24454/udp
        ufw allow 19232/tcp
        ufw allow 19232/udp
        ufw allow 8080/tcp  # Para estatísticas
        log "Regras UFW configuradas"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        # CentOS/RHEL/Fedora firewalld
        firewall-cmd --permanent --add-port=25565/tcp
        firewall-cmd --permanent --add-port=25565/udp
        firewall-cmd --permanent --add-port=24454/tcp
        firewall-cmd --permanent --add-port=24454/udp
        firewall-cmd --permanent --add-port=19232/tcp
        firewall-cmd --permanent --add-port=19232/udp
        firewall-cmd --permanent --add-port=8080/tcp
        firewall-cmd --reload
        log "Regras firewalld configuradas"
    else
        log_warning "Nenhum firewall detectado (UFW ou firewalld). Configure manualmente se necessário."
    fi
}

# Configurar serviço
configure_service() {
    log "Configurando serviço HAProxy..."
    
    systemctl enable haproxy
    systemctl restart haproxy
    
    if systemctl is-active --quiet haproxy; then
        log_success "HAProxy está rodando corretamente"
    else
        log_error "HAProxy falhou ao iniciar"
        systemctl status haproxy
        exit 1
    fi
}

# Verificar configuração
verify_config() {
    log "Verificando configuração do HAProxy..."
    
    if haproxy -c -f "$CONFIG_FILE"; then
        log_success "Configuração do HAProxy está válida"
    else
        log_error "Configuração do HAProxy contém erros"
        exit 1
    fi
}

# Testar portas
test_ports() {
    log "Testando portas..."
    
    for port in $PORTS; do
        if netstat -tuln | grep -q ":$port "; then
            log_success "Porta $port está em uso (TCP/UDP)"
        else
            log_warning "Porta $port não está sendo usada"
        fi
    done
}

# Gerar relatório final
generate_final_report() {
    log "Gerando relatório final..."
    
    REPORT_FILE="/root/haproxy_installation_report.txt"
    
    cat > "$REPORT_FILE" << EOF
=====================================
RELATÓRIO DE INSTALAÇÃO HAPROXY
=====================================

Data/Hora: $(date)
Domínio: $DOMAIN
Distribuição: $DISTRO $VERSION

PORTAS CONFIGURADAS:
- 25565 (TCP/UDP) - Minecraft
- 24454 (TCP/UDP) - Serviço personalizado
- 19232 (TCP/UDP) - Serviço personalizado
- 8080 (TCP) - Estatísticas HAProxy

ARQUIVOS IMPORTANTES:
- Configuração: $CONFIG_FILE
- Log de instalação: $LOG_FILE
- Backup configuração: $BACKUP_CONFIG

COMANDOS ÚTEIS:
- Verificar status: systemctl status haproxy
- Reiniciar serviço: systemctl restart haproxy
- Verificar config: haproxy -c -f $CONFIG_FILE
- Ver logs: journalctl -u haproxy -f

ACESSO ÀS ESTATÍSTICAS:
URL: http://$(hostname -I | awk '{print $1}'):8080/stats
Usuário: admin
Senha: admin

PRÓXIMOS PASSOS:
1. Edite $CONFIG_FILE e adicione seus servidores backend
2. Configure certificados SSL se necessário
3. Ajuste as configurações conforme sua necessidade
4. Teste a conectividade com seus serviços

EXEMPLO DE SERVIDOR BACKEND:
server server1 192.168.1.100:25565 check
server server2 192.168.1.101:25565 check backup

STATUS DOS SERVIÇOS:
$(systemctl is-active haproxy) - HAProxy

PORTAS EM USO:
$(netstat -tuln | grep -E ':(25565|24454|19232|8080) ')

=====================================
EOF

    log_success "Relatório salvo em: $REPORT_FILE"
    
    # Mostrar relatório na tela
    echo -e "\n${GREEN}==================== RELATÓRIO FINAL ====================${NC}"
    cat "$REPORT_FILE"
    echo -e "${GREEN}=========================================================${NC}\n"
}

# Função principal
main() {
    echo -e "${BLUE}"
    echo "=========================================="
    echo "   INSTALAÇÃO E CONFIGURAÇÃO HAPROXY"
    echo "=========================================="
    echo -e "${NC}"
    
    # Iniciar log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Iniciando instalação HAProxy - $(date)" > "$LOG_FILE"
    
    check_root
    detect_distro
    install_haproxy
    backup_config
    create_config
    verify_config
    configure_firewall
    configure_service
    test_ports
    generate_final_report
    
    log_success "Instalação e configuração do HAProxy concluída!"
    echo -e "${GREEN}Verifique o relatório em /root/haproxy_installation_report.txt${NC}"
}

# Executar função principal
main "$@"
