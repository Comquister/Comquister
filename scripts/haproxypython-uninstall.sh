#!/bin/bash

# HAProxy Monitor - Script de Desinstalação Completa
# Focado no Ubuntu/Debian
# Uso: curl -sSL https://raw.githubusercontent.com/seu-repo/haproxy-monitor/main/uninstall.sh | sudo bash
# Ou: wget -qO- https://raw.githubusercontent.com/seu-repo/haproxy-monitor/main/uninstall.sh | sudo bash

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
MANAGEMENT_SCRIPT="/usr/local/bin/haproxy-monitor"

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

# Função de confirmação
confirm_removal() {
    echo -e "${YELLOW}⚠️  ATENÇÃO: Este script irá remover completamente o HAProxy Monitor${NC}"
    echo -e "${YELLOW}   Isso inclui:${NC}"
    echo -e "${YELLOW}   - Parar o serviço${NC}"
    echo -e "${YELLOW}   - Remover arquivos de configuração${NC}"
    echo -e "${YELLOW}   - Remover usuário do sistema${NC}"
    echo -e "${YELLOW}   - Remover regras de firewall${NC}"
    echo -e "${YELLOW}   - Limpar logs${NC}"
    echo
    read -p "Tem certeza que deseja continuar? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        print_warning "Desinstalação cancelada pelo usuário"
        exit 0
    fi
}

print_status "Iniciando desinstalação do HAProxy Monitor..."

# Mostrar confirmação
confirm_removal

# 1. Parar o serviço se estiver rodando
print_status "Parando o serviço HAProxy Monitor..."
if systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
    systemctl stop $SERVICE_NAME
    print_success "Serviço parado"
else
    print_warning "Serviço já estava parado ou não existe"
fi

# 2. Desabilitar o serviço
print_status "Desabilitando inicialização automática..."
if systemctl is-enabled --quiet $SERVICE_NAME 2>/dev/null; then
    systemctl disable $SERVICE_NAME
    print_success "Inicialização automática desabilitada"
else
    print_warning "Serviço não estava habilitado para inicialização automática"
fi

# 3. Remover arquivo de serviço systemd
print_status "Removendo arquivo de serviço systemd..."
if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    print_success "Arquivo de serviço removido"
else
    print_warning "Arquivo de serviço não encontrado"
fi

# 4. Recarregar systemd
print_status "Recarregando systemd..."
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true
print_success "Systemd recarregado"

# 5. Remover diretório de instalação
print_status "Removendo diretório de instalação..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    print_success "Diretório $INSTALL_DIR removido"
else
    print_warning "Diretório de instalação não encontrado"
fi

# 6. Remover usuário do sistema
print_status "Removendo usuário do sistema..."
if id "$SERVICE_USER" &>/dev/null; then
    # Matar processos do usuário se existirem
    pkill -u "$SERVICE_USER" 2>/dev/null || true
    sleep 2
    
    # Remover usuário
    userdel "$SERVICE_USER" 2>/dev/null || true
    
    # Remover grupo se ainda existir
    groupdel "$SERVICE_USER" 2>/dev/null || true
    
    print_success "Usuário $SERVICE_USER removido"
else
    print_warning "Usuário $SERVICE_USER não encontrado"
fi

# 7. Remover script de gerenciamento
print_status "Removendo script de gerenciamento..."
if [ -f "$MANAGEMENT_SCRIPT" ]; then
    rm -f "$MANAGEMENT_SCRIPT"
    print_success "Script de gerenciamento removido"
else
    print_warning "Script de gerenciamento não encontrado"
fi

# 8. Remover regras de firewall (UFW)
print_status "Removendo regras de firewall..."
if command -v ufw &> /dev/null; then
    # Verificar se UFW está ativo
    if ufw status | grep -q "Status: active"; then
        # Remover regras específicas do HAProxy Monitor
        ufw --force delete allow 25565/tcp 2>/dev/null || true
        ufw --force delete allow 19132/udp 2>/dev/null || true
        ufw --force delete allow 24454/udp 2>/dev/null || true
        
        # Remover regras com comentários
        ufw --force delete allow "Minecraft Java" 2>/dev/null || true
        ufw --force delete allow "Minecraft Bedrock" 2>/dev/null || true
        ufw --force delete allow "Voice Chat" 2>/dev/null || true
        
        print_success "Regras de firewall removidas"
    else
        print_warning "UFW não está ativo"
    fi
else
    print_warning "UFW não encontrado"
fi

# 9. Limpar logs do systemd
print_status "Limpando logs do sistema..."
journalctl --vacuum-time=1d 2>/dev/null || true
journalctl --rotate 2>/dev/null || true
print_success "Logs limpos"

# 10. Remover processos órfãos (se existirem)
print_status "Verificando processos relacionados..."
PIDS=$(pgrep -f "haproxy.monitor\|$INSTALL_DIR" 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    echo "$PIDS" | xargs kill -9 2>/dev/null || true
    print_success "Processos relacionados finalizados"
else
    print_success "Nenhum processo relacionado encontrado"
fi

# 11. Verificar e remover dependências Python órfãs (opcional)
print_status "Verificando dependências Python..."
if command -v pip3 &> /dev/null; then
    # Listar pacotes instalados relacionados ao rich (usado pelo monitor)
    RICH_INSTALLED=$(pip3 list | grep -i rich || true)
    if [ -n "$RICH_INSTALLED" ]; then
        read -p "Deseja remover a biblioteca Python 'rich' que foi instalada para o HAProxy Monitor? (s/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            pip3 uninstall -y rich 2>/dev/null || true
            print_success "Biblioteca 'rich' removida"
        else
            print_warning "Biblioteca 'rich' mantida (pode estar sendo usada por outros programas)"
        fi
    fi
fi

# 12. Verificação final
print_status "Executando verificação final..."

# Verificar se o serviço ainda existe
if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
    print_error "Serviço ainda encontrado no sistema"
else
    print_success "Serviço completamente removido"
fi

# Verificar se o diretório ainda existe
if [ -d "$INSTALL_DIR" ]; then
    print_error "Diretório de instalação ainda existe"
else
    print_success "Diretório de instalação removido"
fi

# Verificar se o usuário ainda existe
if id "$SERVICE_USER" &>/dev/null; then
    print_error "Usuário do serviço ainda existe"
else
    print_success "Usuário do serviço removido"
fi

# 13. Relatório final
echo
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}    DESINSTALAÇÃO CONCLUÍDA!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo
echo -e "${YELLOW}Itens removidos:${NC}"
echo -e "✓ Serviço systemd: ${BLUE}$SERVICE_NAME${NC}"
echo -e "✓ Diretório: ${BLUE}$INSTALL_DIR${NC}"
echo -e "✓ Usuário: ${BLUE}$SERVICE_USER${NC}"
echo -e "✓ Script de gerenciamento: ${BLUE}$MANAGEMENT_SCRIPT${NC}"
echo -e "✓ Regras de firewall para portas: ${BLUE}25565/tcp, 19132/udp, 24454/udp${NC}"
echo -e "✓ Logs do sistema limpos"
echo
echo -e "${YELLOW}Portas liberadas:${NC}"
echo -e "• Minecraft Java: ${BLUE}25565/tcp${NC}"
echo -e "• Minecraft Bedrock: ${BLUE}19132/udp${NC}"
echo -e "• Voice Chat: ${BLUE}24454/udp${NC}"
echo
echo -e "${GREEN}O HAProxy Monitor foi completamente removido do sistema!${NC}"
echo
echo -e "${BLUE}Nota:${NC} Se você instalou dependências Python globalmente,"
echo -e "pode querer verificar manualmente com: ${YELLOW}pip3 list${NC}"
echo

# 14. Oferecer reinicialização
read -p "Deseja reinicializar o sistema para garantir limpeza completa? (s/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    print_status "Reinicializando sistema em 10 segundos..."
    print_warning "Pressione Ctrl+C para cancelar"
    sleep 10
    reboot
else
    print_success "Desinstalação finalizada. Sistema pronto para uso!"
fi
