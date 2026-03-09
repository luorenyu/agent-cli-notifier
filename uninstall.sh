#!/bin/bash

# Agent CLI Notifier 卸载脚本
# 功能：移除 settings.json 中的 hooks 配置，并删除安装的文件

set -e

# 定义颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

UNINSTALL_CLAUDE=false
UNINSTALL_CODEX=false
UNINSTALL_GEMINI=false
AUTO_CONFIRM=false
NON_INTERACTIVE=false
TARGETS_CSV=""
CODEX_LEGACY=false

function print_help() {
    cat <<'EOF'
Agent CLI Notifier 卸载脚本

用法:
  ./uninstall.sh
  ./uninstall.sh --targets claude,codex --yes
  ./uninstall.sh --targets gemini --auto

参数:
  --targets <list>  要卸载的平台，逗号分隔: claude,codex,gemini
  --yes, --auto     非交互模式，跳过确认
  -h, --help        显示帮助
EOF
}

function set_targets_from_csv() {
    local csv="$1"
    local normalized="${csv,,}"
    IFS=',' read -r -a targets <<< "$normalized"

    UNINSTALL_CLAUDE=false
    UNINSTALL_CODEX=false
    UNINSTALL_GEMINI=false

    for target in "${targets[@]}"; do
        case "${target// /}" in
            claude)
                UNINSTALL_CLAUDE=true
                ;;
            codex)
                UNINSTALL_CODEX=true
                ;;
            gemini)
                UNINSTALL_GEMINI=true
                ;;
            "")
                ;;
            *)
                echo "错误: 不支持的平台 '$target'"
                exit 1
                ;;
        esac
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --targets)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "错误: --targets 需要一个逗号分隔的值。"
                exit 1
            fi
            TARGETS_CSV="$2"
            NON_INTERACTIVE=true
            shift 2
            ;;
        --yes|--auto)
            AUTO_CONFIRM=true
            NON_INTERACTIVE=true
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "错误: 未知参数 '$1'"
            print_help
            exit 1
            ;;
    esac
done

printf "${BLUE}=== Agent CLI Notifier 卸载脚本 ===${NC}\n"

# 检测已安装的平台
CLAUDE_INSTALLED=false
CODEX_INSTALLED=false
GEMINI_INSTALLED=false

if [ -f "$HOME/.claude/scripts/notify.sh" ]; then
    CLAUDE_INSTALLED=true
fi

# 检查 .codex 目录 (新版)
if [ -d "$HOME/.codex/scripts" ]; then
    CODEX_INSTALLED=true
fi

if [ -f "$HOME/.gemini/scripts/notify.sh" ] || [ -f "$HOME/.gemini/scripts/gemini_bridge.sh" ]; then
    GEMINI_INSTALLED=true
fi

# 检查旧版 Codex 安装 (作为兼容性检测)
if [ -f "$HOME/.claude/scripts/codex-notify" ]; then
    CODEX_LEGACY=true
fi

if [[ "$CLAUDE_INSTALLED" == "false" ]] && [[ "$CODEX_INSTALLED" == "false" ]] && [[ "$CODEX_LEGACY" == "false" ]] && [[ "$GEMINI_INSTALLED" == "false" ]]; then
    printf "${YELLOW}未检测到已安装的通知系统。${NC}\n"
    exit 0
fi

# 交互式菜单函数
function show_uninstall_menu() {
    local prompt="$1"
    shift
    local options=("$@")
    local cur=0
    local count=${#options[@]}
    local selected=()

    # 初始化选项 (默认全部选中，方便一键卸载)
    for ((i=0; i<count; i++)); do
        selected[i]="true"
    done

    # Print prompt and instructions
    printf "%b\n" "$prompt"
    printf "${YELLOW}操作说明: [↑/↓]移动光标  [空格]选中/取消  [回车]确认${NC}\n"

    # Hide cursor
    tput civis

    while true; do
        # Render menu
        for ((i=0; i<count; i++)); do
            local mark=" "
            if [[ -n "${selected[i]}" ]]; then
                mark="${RED}x${NC}" # 卸载用红色 x 表示
            fi

            if [ $i -eq $cur ]; then
                printf " ${BLUE}>${NC} [%b] %s\n" "$mark" "${options[i]}"
            else
                printf "   [%b] %s\n" "$mark" "${options[i]}"
            fi
        done

        # Handle Input
        IFS= read -rsn1 key 2>/dev/null
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 key 2>/dev/null
            if [[ "$key" == "[A" ]]; then # Up
                ((cur--))
                if [ $cur -lt 0 ]; then cur=$((count-1)); fi
            elif [[ "$key" == "[B" ]]; then # Down
                ((cur++))
                if [ $cur -ge $count ]; then cur=0; fi
            fi
        elif [[ "$key" == " " ]]; then # Space
            if [[ -n "${selected[cur]}" ]]; then
                selected[cur]=""
            else
                selected[cur]="true"
            fi
        elif [[ "$key" == "" ]]; then # Enter
            break
        fi

        # Move cursor back up to redraw
        printf "\033[${count}A"
    done

    # Restore cursor
    tput cnorm

    # Set global variables
    UNINSTALL_CLAUDE=false
    UNINSTALL_CODEX=false
    UNINSTALL_GEMINI=false

    # 映射选项回变量
    local idx=0
    if [[ "$CLAUDE_INSTALLED" == "true" ]]; then
        if [[ -n "${selected[$idx]}" ]]; then UNINSTALL_CLAUDE=true; fi
        ((idx++))
    fi

    if [[ "$CODEX_INSTALLED" == "true" || "$CODEX_LEGACY" == "true" ]]; then
        if [[ -n "${selected[$idx]}" ]]; then UNINSTALL_CODEX=true; fi
        ((idx++))
    fi

    if [[ "$GEMINI_INSTALLED" == "true" ]]; then
        if [[ -n "${selected[$idx]}" ]]; then UNINSTALL_GEMINI=true; fi
        ((idx++))
    fi
}

# 构建动态菜单列表
OPTIONS_LIST=()
[[ "$CLAUDE_INSTALLED" == "true" ]] && OPTIONS_LIST+=("Claude Code (位于 ~/.claude)")
[[ "$CODEX_INSTALLED" == "true" ]] && OPTIONS_LIST+=("OpenAI Codex (位于 ~/.codex)")
[[ "$CODEX_LEGACY" == "true" ]] && OPTIONS_LIST+=("OpenAI Codex (旧版, 位于 ~/.claude)")
[[ "$GEMINI_INSTALLED" == "true" ]] && OPTIONS_LIST+=("Google Gemini CLI (位于 ~/.gemini)")

if [ ${#OPTIONS_LIST[@]} -eq 0 ]; then
    echo "没有发现可卸载的组件。"
    exit 0
fi

if [[ -n "$TARGETS_CSV" ]]; then
    set_targets_from_csv "$TARGETS_CSV"
elif [[ "$NON_INTERACTIVE" != "true" ]]; then
    show_uninstall_menu "请选择要卸载的组件:" "${OPTIONS_LIST[@]}"
else
    echo "错误: 非交互模式下必须通过 --targets 指定至少一个组件。"
    exit 1
fi

if [[ "$UNINSTALL_CLAUDE" == "false" && "$UNINSTALL_CODEX" == "false" && "$UNINSTALL_GEMINI" == "false" ]]; then
    echo "取消卸载。"
    exit 0
fi

echo ""
printf "准备卸载: \n"
if [[ "$UNINSTALL_CLAUDE" == "true" ]]; then printf "  ${RED}x Claude Code${NC}\n"; fi
if [[ "$UNINSTALL_CODEX" == "true" ]]; then printf "  ${RED}x OpenAI Codex${NC}\n"; fi
if [[ "$UNINSTALL_GEMINI" == "true" ]]; then printf "  ${RED}x Google Gemini CLI${NC}\n"; fi
echo ""

if [[ "$AUTO_CONFIRM" == "true" ]]; then
    printf "${BLUE}非交互模式: 自动确认卸载${NC}\n"
else
    read -p "确认执行卸载? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "操作已取消。"
        exit 0
    fi
fi

# ========================================
# Claude Code 卸载
# ========================================

if [[ "$UNINSTALL_CLAUDE" == "true" ]]; then
    printf "${BLUE}正在卸载 Claude Code 通知功能...${NC}\n"

    # 1. 移除 settings.json 中的配置
    SETTINGS_FILE="$HOME/.claude/settings.json"
    SCRIPT_PATH="$HOME/.claude/scripts/notify.sh"

    if [ -f "$SETTINGS_FILE" ]; then
        printf "${BLUE}正在从 ~/.claude/settings.json 中移除 hooks 配置...${NC}\n"

        # 使用 Python 安全地修改 JSON
        python3 -c "
import json
import os
import sys

settings_path = os.path.expanduser('~/.claude/settings.json')
script_path = os.path.expanduser('~/.claude/scripts/notify.sh')

if not os.path.exists(settings_path):
    print('配置文件不存在，跳过。')
    sys.exit(0)

try:
    with open(settings_path, 'r') as f:
        data = json.load(f)
except json.JSONDecodeError:
    print('错误: settings.json 格式无效，无法自动修改。请手动检查。')
    sys.exit(1)

modified = False

# 1. 移除 Hooks
if 'hooks' in data:
    events = ['PermissionRequest', 'Stop']

    for event in events:
        if event in data['hooks']:
            new_hooks = []
            for matcher_group in data['hooks'][event]:
                # 检查该组 hooks 中是否包含我们的脚本
                keep_group = True
                if matcher_group.get('matcher') == '*':
                    filtered_hooks = []
                    for h in matcher_group.get('hooks', []):
                        if script_path in h.get('command', ''):
                            print(f'  - 移除 {event} hook')
                            modified = True
                        else:
                            filtered_hooks.append(h)

                    # 如果过滤后该组还有其他 hook，保留该组
                    if filtered_hooks:
                        matcher_group['hooks'] = filtered_hooks
                        new_hooks.append(matcher_group)
                    # 如果过滤后为空，则不添加到 new_hooks (即删除该组)
                else:
                    new_hooks.append(matcher_group)

            # 如果该事件下还有 hook 组，更新；否则删除该事件键
            if new_hooks:
                data['hooks'][event] = new_hooks
            else:
                del data['hooks'][event]

# 2. 移除 Commands (/notifier)
if 'commands' in data:
    if 'notifier' in data['commands']:
        del data['commands']['notifier']
        print('  - 移除 /notifier 命令')
        modified = True

if modified:
    with open(settings_path, 'w') as f:
        json.dump(data, f, indent=2)
    print('✓ 配置文件已更新')
else:
    print('未找到相关配置，无需移除。')
"
    else
        printf "${YELLOW}未找到配置文件: $SETTINGS_FILE${NC}\n"
    fi

    # 2. 删除文件
    INSTALL_DIR="$HOME/.claude/scripts"
    ASSETS_DIR="$HOME/.claude/assets"
    COMMANDS_DIR="$HOME/.claude/commands"
    CONFIG_FILE="$HOME/.claude/notifier.conf"

    printf "${BLUE}正在删除安装文件...${NC}\n"

    if [ -f "$INSTALL_DIR/notify.sh" ]; then
        rm "$INSTALL_DIR/notify.sh"
        printf "${GREEN}✓ 已删除脚本: $INSTALL_DIR/notify.sh${NC}\n"
    fi

    if [ -f "$INSTALL_DIR/toggle.sh" ]; then
        rm "$INSTALL_DIR/toggle.sh"
        printf "${GREEN}✓ 已删除脚本: $INSTALL_DIR/toggle.sh${NC}\n"
    fi

    if [ -f "$COMMANDS_DIR/notifier.md" ]; then
        rm "$COMMANDS_DIR/notifier.md"
        printf "${GREEN}✓ 已删除命令: $COMMANDS_DIR/notifier.md${NC}\n"
    fi

    if [ -f "$CONFIG_FILE" ]; then
        rm "$CONFIG_FILE"
        printf "${GREEN}✓ 已删除配置文件${NC}\n"
    fi

    if [ -f "$ASSETS_DIR/logo.png" ]; then
        rm "$ASSETS_DIR/logo.png"
        printf "${GREEN}✓ 已删除图标资源${NC}\n"
        # 尝试删除空目录
        rmdir "$ASSETS_DIR" 2>/dev/null || true
    fi

    # 尝试删除脚本目录（如果为空）
    rmdir "$INSTALL_DIR" 2>/dev/null || true

    printf "${GREEN}✓ Claude Code 卸载完成${NC}\n"
fi

# ========================================
# Codex 卸载
# ========================================

if [[ "$UNINSTALL_CODEX" == "true" ]]; then
    printf "${BLUE}正在卸载 Codex 通知功能...${NC}\n"

    # 1. 移除 Alias
    SHELL_CONFIGS=("$HOME/.zshrc" "$HOME/.bashrc")
    for RC_FILE in "${SHELL_CONFIGS[@]}"; do
        if [ -f "$RC_FILE" ]; then
            if grep -q "alias codex=" "$RC_FILE"; then
                printf "${BLUE}正在从 $RC_FILE 中移除 alias...${NC}\n"
                # 创建备份
                cp "$RC_FILE" "${RC_FILE}.bak"

                # 使用 sed 删除别名行和注释行
                if [[ "$(uname -s)" == "Darwin" ]]; then
                    sed -i '' '/Agent CLI Notifier - Codex Wrapper/d' "$RC_FILE"
                    sed -i '' '/Claude Code Notifier - Codex Wrapper/d' "$RC_FILE"
                    sed -i '' '/alias codex=/d' "$RC_FILE"
                else
                    sed -i '/Agent CLI Notifier - Codex Wrapper/d' "$RC_FILE"
                    sed -i '/Claude Code Notifier - Codex Wrapper/d' "$RC_FILE"
                    sed -i '/alias codex=/d' "$RC_FILE"
                fi
                printf "${GREEN}✓ 已移除 alias 配置 (备份已保存至 ${RC_FILE}.bak)${NC}\n"
            fi
        fi
    done

    # 提示用户重载 shell
    printf "${YELLOW}提示: 请运行 'source ~/.zshrc' (或对应的配置文件) 或重启终端以使更改生效。${NC}\n"

    # 2. 删除新版 .codex 目录
    if [ -d "$HOME/.codex" ]; then
        rm -rf "$HOME/.codex"
        printf "${GREEN}✓ 已移除 ~/.codex 目录及其内容${NC}\n"
    fi

    # 3. 清理旧版残留 (兼容性)
    if [ -f "$HOME/.claude/scripts/codex-notify" ]; then
        rm "$HOME/.claude/scripts/codex-notify"
        printf "${GREEN}✓ 已移除旧版启动脚本: ~/.claude/scripts/codex-notify${NC}\n"
    fi

    if [ -f "$HOME/.claude/scripts/codex_wrapper.py" ]; then
        rm "$HOME/.claude/scripts/codex_wrapper.py"
        printf "${GREEN}✓ 已移除旧版 Wrapper: ~/.claude/scripts/codex_wrapper.py${NC}\n"
    fi

    printf "${GREEN}✓ Codex 卸载完成${NC}\n"
fi

if [[ "$UNINSTALL_GEMINI" == "true" ]]; then
    printf "${BLUE}正在卸载 Gemini 通知功能...${NC}\n"

    GEMINI_SETTINGS="$HOME/.gemini/settings.json"
    GEMINI_BRIDGE="$HOME/.gemini/scripts/gemini_bridge.sh"

    if [ -f "$GEMINI_SETTINGS" ]; then
        printf "${BLUE}正在从 ~/.gemini/settings.json 中移除 hooks 配置...${NC}\n"
        python3 -c "
import json
import os
import sys

settings_path = os.path.expanduser('~/.gemini/settings.json')
bridge_path = os.path.expanduser('~/.gemini/scripts/gemini_bridge.sh')

if not os.path.exists(settings_path):
    print('配置文件不存在，跳过。')
    sys.exit(0)

try:
    with open(settings_path, 'r') as f:
        data = json.load(f)
except json.JSONDecodeError:
    print('错误: settings.json 格式无效，无法自动修改。请手动检查。')
    sys.exit(1)

modified = False

if 'hooks' in data:
    for event in ['Notification', 'AfterAgent']:
        if event in data['hooks']:
            new_hooks = []
            for matcher_group in data['hooks'][event]:
                if matcher_group.get('matcher') == '*':
                    filtered_hooks = []
                    for hook in matcher_group.get('hooks', []):
                        if bridge_path in hook.get('command', ''):
                            print(f'  - 移除 {event} hook')
                            modified = True
                        else:
                            filtered_hooks.append(hook)

                    if filtered_hooks:
                        matcher_group['hooks'] = filtered_hooks
                        new_hooks.append(matcher_group)
                else:
                    new_hooks.append(matcher_group)

            if new_hooks:
                data['hooks'][event] = new_hooks
            else:
                del data['hooks'][event]

if modified:
    with open(settings_path, 'w') as f:
        json.dump(data, f, indent=2)
    print('✓ 配置文件已更新')
else:
    print('未找到相关配置，无需移除。')
"
    fi

    if [ -f "$HOME/.gemini/scripts/notify.sh" ]; then
        rm "$HOME/.gemini/scripts/notify.sh"
        printf "${GREEN}✓ 已删除脚本: ~/.gemini/scripts/notify.sh${NC}\n"
    fi

    if [ -f "$HOME/.gemini/scripts/gemini_bridge.sh" ]; then
        rm "$HOME/.gemini/scripts/gemini_bridge.sh"
        printf "${GREEN}✓ 已删除脚本: ~/.gemini/scripts/gemini_bridge.sh${NC}\n"
    fi

    if [ -f "$HOME/.gemini/notifier.conf" ]; then
        rm "$HOME/.gemini/notifier.conf"
        printf "${GREEN}✓ 已删除配置文件: ~/.gemini/notifier.conf${NC}\n"
    fi

    if [ -f "$HOME/.gemini/assets/logo.png" ]; then
        rm "$HOME/.gemini/assets/logo.png"
        printf "${GREEN}✓ 已删除图标资源: ~/.gemini/assets/logo.png${NC}\n"
    fi

    rmdir "$HOME/.gemini/assets" 2>/dev/null || true
    rmdir "$HOME/.gemini/scripts" 2>/dev/null || true
    printf "${GREEN}✓ Gemini 卸载完成${NC}\n"
fi

printf "${BLUE}=== Agent CLI Notifier 卸载操作结束 ===${NC}\n"
