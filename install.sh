#!/bin/bash

set -e

# 定义颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

INSTALL_CLAUDE=false
INSTALL_CODEX=false
INSTALL_GEMINI=false
AUTO_CONFIRM=false
NON_INTERACTIVE=false
TARGETS_CSV=""

function print_help() {
    cat <<'EOF'
Agent CLI Notifier 安装脚本

用法:
  ./install.sh
  ./install.sh --targets claude,codex --yes
  ./install.sh --targets gemini --auto

参数:
  --targets <list>  要安装的平台，逗号分隔: claude,codex,gemini
  --yes, --auto     非交互模式，跳过安装确认和 Codex alias 提示
  -h, --help        显示帮助
EOF
}

function set_targets_from_csv() {
    local csv="$1"
    local normalized="${csv,,}"
    IFS=',' read -r -a targets <<< "$normalized"

    INSTALL_CLAUDE=false
    INSTALL_CODEX=false
    INSTALL_GEMINI=false

    for target in "${targets[@]}"; do
        case "${target// /}" in
            claude)
                INSTALL_CLAUDE=true
                ;;
            codex)
                INSTALL_CODEX=true
                ;;
            gemini)
                INSTALL_GEMINI=true
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

if [[ -n "$TARGETS_CSV" ]]; then
    set_targets_from_csv "$TARGETS_CSV"
fi

printf "${BLUE}=== Agent CLI Notifier 安装脚本 ===${NC}\n"

# 0. 交互式菜单函数
function show_menu() {
    local prompt="$1"
    shift
    local options=("$@")
    local cur=0
    local count=${#options[@]}
    local selected=()

    # Initialize selection (default empty)
    for ((i=0; i<count; i++)); do
        selected[i]=""
    done

    # Print prompt and instructions
    printf "%b\n" "$prompt"
    printf "${YELLOW}操作说明: [↑/↓]移动光标  [空格]选中/取消  [回车]确认${NC}\n"

    # Save cursor position logic is tricky with just bash,
    # so we'll just clear lines before redrawing

    # Hide cursor
    tput civis

    while true; do
        # Render menu
        for ((i=0; i<count; i++)); do
            local mark=" "
            if [[ -n "${selected[i]}" ]]; then
                mark="${GREEN}x${NC}"
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
        # \033[NA moves cursor up N lines
        printf "\033[${count}A"
    done

    # Restore cursor
    tput cnorm

    # Set global variables
    if [[ -n "${selected[0]}" ]]; then INSTALL_CLAUDE=true; else INSTALL_CLAUDE=false; fi
    if [[ -n "${selected[1]}" ]]; then INSTALL_CODEX=true; else INSTALL_CODEX=false; fi
    if [[ -n "${selected[2]}" ]]; then INSTALL_GEMINI=true; else INSTALL_GEMINI=false; fi
}

# 执行菜单
if [[ "$NON_INTERACTIVE" != "true" ]]; then
    OPTIONS_LIST=("Claude Code" "OpenAI Codex" "Google Gemini CLI")
    show_menu "请选择要安装的组件:" "${OPTIONS_LIST[@]}"
elif [[ "$INSTALL_CLAUDE" == "false" && "$INSTALL_CODEX" == "false" && "$INSTALL_GEMINI" == "false" ]]; then
    echo "错误: 非交互模式下必须通过 --targets 指定至少一个组件。"
    exit 1
fi

if [[ "$INSTALL_CLAUDE" == "false" && "$INSTALL_CODEX" == "false" && "$INSTALL_GEMINI" == "false" ]]; then
    echo "未选择任何组件，退出安装。"
    exit 0
fi

echo ""
printf "准备安装: \n"
if [[ "$INSTALL_CLAUDE" == "true" ]]; then printf "  ${GREEN}✓ Claude Code${NC}\n"; fi
if [[ "$INSTALL_CODEX" == "true" ]]; then printf "  ${GREEN}✓ OpenAI Codex${NC}\n"; fi
if [[ "$INSTALL_GEMINI" == "true" ]]; then printf "  ${GREEN}✓ Google Gemini CLI${NC}\n"; fi
echo ""

# 源文件路径定义
BASE_DIR="$(dirname "$0")"
SCRIPT_SOURCE="$BASE_DIR/scripts/notify.sh"
WRAPPER_SOURCE="$BASE_DIR/scripts/codex_wrapper.py"
BRIDGE_SOURCE="$BASE_DIR/scripts/gemini_bridge.sh"
TOGGLE_SOURCE="$BASE_DIR/scripts/toggle.sh"
CONF_SOURCE="$BASE_DIR/scripts/notifier.conf"
LOGO_SOURCE="$BASE_DIR/assets/logo.png"

# 简单的源文件检查
if [ ! -f "$SCRIPT_SOURCE" ]; then
    printf "${YELLOW}正在从当前目录查找 scripts/notify.sh...${NC}\n"
    if [ -f "./scripts/notify.sh" ]; then
        BASE_DIR="."
        SCRIPT_SOURCE="./scripts/notify.sh"
        WRAPPER_SOURCE="./scripts/codex_wrapper.py"
        BRIDGE_SOURCE="./scripts/gemini_bridge.sh"
        TOGGLE_SOURCE="./scripts/toggle.sh"
        CONF_SOURCE="./scripts/notifier.conf"
        LOGO_SOURCE="./assets/logo.png"
    else
        echo "错误: 找不到 scripts/notify.sh"
        exit 1
    fi
fi

# ========================================
# 函数定义
# ========================================

install_gemini_notifications() {
    printf "${BLUE}=== 正在为 Google Gemini CLI 安装通知功能 ===${NC}\n"

    GEMINI_ROOT="$HOME/.gemini"
    GEMINI_SCRIPTS="$GEMINI_ROOT/scripts"
    GEMINI_ASSETS="$GEMINI_ROOT/assets"

    mkdir -p "$GEMINI_SCRIPTS"
    mkdir -p "$GEMINI_ASSETS"
    printf "${GREEN}✓ 创建 Gemini 安装目录: $GEMINI_ROOT${NC}\n"

    # 1. 安装并配置 Bridge Script
    BRIDGE_DEST="$GEMINI_SCRIPTS/gemini_bridge.sh"

    if [ ! -f "$BRIDGE_SOURCE" ]; then
         echo "错误: 找不到 scripts/gemini_bridge.sh"
         exit 1
    fi

    cp "$BRIDGE_SOURCE" "$BRIDGE_DEST"
    chmod +x "$BRIDGE_DEST"
    printf "${GREEN}✓ Bridge 脚本已安装: $BRIDGE_DEST${NC}\n"

    # 2. 安装并配置 notify.sh (独立副本)
    NOTIFY_DEST="$GEMINI_SCRIPTS/notify.sh"
    cp "$SCRIPT_SOURCE" "$NOTIFY_DEST"
    chmod +x "$NOTIFY_DEST"

    # 修改 notify.sh 中的路径指向 .gemini
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' "s|\.claude/assets|\.gemini/assets|g" "$NOTIFY_DEST"
        sed -i '' "s|\.claude/notifier.conf|\.gemini/notifier.conf|g" "$NOTIFY_DEST"
    else
        sed -i "s|\.claude/assets|\.gemini/assets|g" "$NOTIFY_DEST"
        sed -i "s|\.claude/notifier.conf|\.gemini/notifier.conf|g" "$NOTIFY_DEST"
    fi
    printf "${GREEN}✓ 通知脚本已安装到 Gemini 目录: $NOTIFY_DEST${NC}\n"

    # 3. 安装配置文件 (独立副本)
    CONF_DEST="$GEMINI_ROOT/notifier.conf"
    if [ ! -f "$CONF_DEST" ]; then
        if [ -f "$CONF_SOURCE" ]; then
            cp "$CONF_SOURCE" "$CONF_DEST"
            # 修改配置中的图标路径和标题
            if [[ "$(uname -s)" == "Darwin" ]]; then
                sed -i '' "s|\.claude/assets|\.gemini/assets|g" "$CONF_DEST"
                sed -i '' 's|TITLE_PERMISSION="⚠️ Claude Code 等待确认"|TITLE_PERMISSION="⚠️ Gemini CLI 等待确认"|g' "$CONF_DEST"
                sed -i '' 's|TITLE_STOP="✅ Claude Code 任务完成"|TITLE_STOP="✅ Gemini CLI 任务完成"|g' "$CONF_DEST"
            else
                sed -i "s|\.claude/assets|\.gemini/assets|g" "$CONF_DEST"
                sed -i 's|TITLE_PERMISSION="⚠️ Claude Code 等待确认"|TITLE_PERMISSION="⚠️ Gemini CLI 等待确认"|g' "$CONF_DEST"
                sed -i 's|TITLE_STOP="✅ Claude Code 任务完成"|TITLE_STOP="✅ Gemini CLI 任务完成"|g' "$CONF_DEST"
            fi
            printf "${GREEN}✓ Gemini 配置文件已安装: $CONF_DEST${NC}\n"
        fi
    else
        printf "${YELLOW}提示: Gemini 配置文件已存在，跳过覆盖。${NC}\n"
    fi

    # 4. 安装资源
    if [ -f "$LOGO_SOURCE" ]; then
        cp "$LOGO_SOURCE" "$GEMINI_ASSETS/logo.png"
    fi

    # 5. 自动修改配置文件 (settings.json)
    echo ""
    printf "${YELLOW}=== 配置 Gemini CLI Hooks (直接修改 settings.json) ===${NC}\n"

    GEMINI_SETTINGS="$HOME/.gemini/settings.json"

    # 确保 settings.json 存在
    if [ ! -f "$GEMINI_SETTINGS" ]; then
        echo "{}" > "$GEMINI_SETTINGS"
    fi

    printf "${BLUE}正在配置 ~/.gemini/settings.json ...${NC}\n"

    python3 -c "
import json
import os
import sys

settings_path = os.path.expanduser('~/.gemini/settings.json')
bridge_path = os.path.expanduser('~/.gemini/scripts/gemini_bridge.sh')

if not os.path.exists(settings_path):
    print(f'创建新的配置文件: {settings_path}')
    data = {}
else:
    try:
        with open(settings_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        print('错误: settings.json 格式无效')
        data = {}

if 'hooks' not in data:
    data['hooks'] = {}

# 定义 Gemini 的 Hooks
# Notification: 系统通知 (如权限请求) -> 映射为 PermissionRequest
# AfterAgent: Agent 任务结束 -> 映射为 Stop
target_hooks = {
    'Notification': {
        'command': f'{bridge_path} PermissionRequest',
        'type': 'command'
    },
    'AfterAgent': {
        'command': f'{bridge_path} Stop',
        'type': 'command'
    }
}

updated = False
for event, hook_config in target_hooks.items():
    if event not in data['hooks']:
        data['hooks'][event] = []

    exists = False
    # 检查是否已经存在相同的 command
    for matcher_group in data['hooks'][event]:
        if matcher_group.get('matcher') == '*':
            for h in matcher_group.get('hooks', []):
                if bridge_path in h.get('command', ''):
                    exists = True
                    break
        if exists: break

    if not exists:
        new_entry = {
            'matcher': '*',
            'hooks': [hook_config]
        }
        data['hooks'][event].append(new_entry)
        print(f'  - 已添加 {event} hook')
        updated = True
    else:
        print(f'  - {event} hook 已存在，跳过')

if updated:
    with open(settings_path, 'w') as f:
        json.dump(data, f, indent=2)
    print('配置文件更新成功。')
else:
    print('配置文件无需更新。')
"

    printf "${GREEN}✓ Gemini 配置文件更新完成${NC}\n"

    # 移除旧的手动命令提示，因为现在是自动写入
    echo "现在 Gemini CLI 应该可以自动触发通知了。"
}

install_codex_notifications() {
    printf "${BLUE}=== 正在为 OpenAI Codex 安装通知功能 (Wrapper模式) ===${NC}\n"

    # Codex 独立安装路径
    CODEX_ROOT="$HOME/.codex"
    CODEX_SCRIPTS="$CODEX_ROOT/scripts"
    CODEX_ASSETS="$CODEX_ROOT/assets"

    mkdir -p "$CODEX_SCRIPTS"
    mkdir -p "$CODEX_ASSETS"
    printf "${GREEN}✓ 创建 Codex 安装目录: $CODEX_ROOT${NC}\n"

    # 1. 查找真实的 Codex 二进制文件
    REAL_CODEX_PATH=""
    if command -v codex &> /dev/null; then
        # 获取所有 codex 路径列表
        ALL_PATHS=$(type -aP codex)

        # 逐行遍历路径
        while IFS= read -r path; do
            # 排除包含 .claude/scripts 或 .codex/scripts 的路径
            if [[ "$path" != *".claude/scripts"* && "$path" != *".codex/scripts"* && "$path" != *"/codex-notify"* ]]; then
                REAL_CODEX_PATH="$path"
                break
            fi
        done <<< "$ALL_PATHS"
    fi

    if [[ -z "$REAL_CODEX_PATH" ]]; then
        printf "${YELLOW}警告: 未找到 'codex' 原始命令。${NC}\n"
        echo "可能原因：未安装 Codex CLI，或者它被我们的别名/脚本覆盖且不在其他 PATH 中。"
        echo "请先安装 OpenAI Codex CLI。"
        return 1
    fi

    printf "检测到 Codex 真实路径: ${BLUE}$REAL_CODEX_PATH${NC}\n"

    # 2. 安装并配置 Python Wrapper
    WRAPPER_DEST="$CODEX_SCRIPTS/codex_wrapper.py"

    if [ ! -f "$WRAPPER_SOURCE" ]; then
        echo "错误: 找不到 scripts/codex_wrapper.py"
        exit 1
    fi

    cp "$WRAPPER_SOURCE" "$WRAPPER_DEST"
    chmod +x "$WRAPPER_DEST"

    # 修改 Wrapper 中的路径指向 .codex
    # 使用 sed 替换 ~/.claude 为 ~/.codex
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' "s|\.claude/scripts|\.codex/scripts|g" "$WRAPPER_DEST"
    else
        sed -i "s|\.claude/scripts|\.codex/scripts|g" "$WRAPPER_DEST"
    fi

    printf "${GREEN}✓ Python Wrapper 已安装并配置: $WRAPPER_DEST${NC}\n"

    # 3. 安装并配置 notify.sh (独立副本)
    NOTIFY_DEST="$CODEX_SCRIPTS/notify.sh"
    cp "$SCRIPT_SOURCE" "$NOTIFY_DEST"
    chmod +x "$NOTIFY_DEST"

    # 修改 notify.sh 中的路径指向 .codex
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' "s|\.claude/assets|\.codex/assets|g" "$NOTIFY_DEST"
        sed -i '' "s|\.claude/notifier.conf|\.codex/notifier.conf|g" "$NOTIFY_DEST"
    else
        sed -i "s|\.claude/assets|\.codex/assets|g" "$NOTIFY_DEST"
        sed -i "s|\.claude/notifier.conf|\.codex/notifier.conf|g" "$NOTIFY_DEST"
    fi
    printf "${GREEN}✓ 通知脚本已安装到 Codex 目录: $NOTIFY_DEST${NC}\n"

    # 4. 安装配置文件 (独立副本)
    CONF_DEST="$CODEX_ROOT/notifier.conf"
    if [ ! -f "$CONF_DEST" ]; then
        if [ -f "$CONF_SOURCE" ]; then
            cp "$CONF_SOURCE" "$CONF_DEST"
            # 修改配置中的图标路径
            if [[ "$(uname -s)" == "Darwin" ]]; then
                sed -i '' "s|\.claude/assets|\.codex/assets|g" "$CONF_DEST"
                # 修改标题为 OpenAI Codex
                sed -i '' 's|TITLE_PERMISSION="⚠️ Claude Code 等待确认"|TITLE_PERMISSION="⚠️ OpenAI Codex 等待确认"|g' "$CONF_DEST"
                sed -i '' 's|TITLE_STOP="✅ Claude Code 任务完成"|TITLE_STOP="✅ OpenAI Codex 任务完成"|g' "$CONF_DEST"
            else
                sed -i "s|\.claude/assets|\.codex/assets|g" "$CONF_DEST"
                # 修改标题为 OpenAI Codex
                sed -i 's|TITLE_PERMISSION="⚠️ Claude Code 等待确认"|TITLE_PERMISSION="⚠️ OpenAI Codex 等待确认"|g' "$CONF_DEST"
                sed -i 's|TITLE_STOP="✅ Claude Code 任务完成"|TITLE_STOP="✅ OpenAI Codex 任务完成"|g' "$CONF_DEST"
            fi
            printf "${GREEN}✓ Codex 配置文件已安装: $CONF_DEST${NC}\n"
        fi
    else
        printf "${YELLOW}提示: Codex 配置文件已存在，跳过覆盖。${NC}\n"
    fi

    # 5. 安装资源
    if [ -f "$LOGO_SOURCE" ]; then
        cp "$LOGO_SOURCE" "$CODEX_ASSETS/logo.png"
    fi

    # 6. 创建 Shim 脚本 (codex-notify)
    SHIM_DEST="$CODEX_SCRIPTS/codex-notify"

    cat > "$SHIM_DEST" <<EOF
#!/bin/bash
export REAL_CODEX_PATH="$REAL_CODEX_PATH"
exec python3 "$WRAPPER_DEST" "\$@"
EOF

    chmod +x "$SHIM_DEST"
    printf "${GREEN}✓ 启动脚本已创建: $SHIM_DEST${NC}\n"

    # 7. 配置 Alias
    echo ""
    printf "${YELLOW}=== ⚠️  重要步骤: 启用 Codex 通知 ===${NC}\n"

    SHELL_CONFIG=""
    if [[ "$SHELL" == *"zsh"* ]]; then
        SHELL_CONFIG="$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        SHELL_CONFIG="$HOME/.bashrc"
    fi

    ALIAS_CMD="alias codex='$SHIM_DEST'"

    if [[ -n "$SHELL_CONFIG" && -f "$SHELL_CONFIG" ]]; then
        echo "检测到 Shell 配置文件: $SHELL_CONFIG"
        confirm="n"
        if [[ "$AUTO_CONFIRM" == "true" ]]; then
            confirm="y"
            printf "${BLUE}非交互模式: 自动写入 Codex alias 到 $SHELL_CONFIG${NC}\n"
        else
            read -p "是否自动添加 alias 到配置文件? [y/N]: " confirm
        fi

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            if grep -q "alias codex=" "$SHELL_CONFIG"; then
                printf "${YELLOW}提示: $SHELL_CONFIG 中已存在 'alias codex'，跳过自动添加。${NC}\n"
                echo "请手动检查并确保其指向: $SHIM_DEST"
            else
                echo "" >> "$SHELL_CONFIG"
                echo "# Agent CLI Notifier - Codex Wrapper" >> "$SHELL_CONFIG"
                echo "$ALIAS_CMD" >> "$SHELL_CONFIG"
                printf "${GREEN}✓ 已成功添加 alias 到 $SHELL_CONFIG${NC}\n"

                RELOAD_CMD="source $SHELL_CONFIG"
                if [[ "$(uname -s)" == "Darwin" ]] && command -v pbcopy &> /dev/null; then
                    echo -n "$RELOAD_CMD" | pbcopy
                    printf "${YELLOW}⚡️ 命令已复制到剪贴板！请按 Cmd+V 粘贴并回车使配置生效：${NC}\n"
                else
                    echo -e "请手动运行以下命令使配置生效："
                fi
                printf "${BLUE}$RELOAD_CMD${NC}\n"
                return 0
            fi
        fi
    fi

    echo ""
    echo "为了让通知生效，你需要配置别名(Alias)，让 'codex' 命令指向我们的 Wrapper。"
    echo "请将以下行添加到你的 Shell 配置文件 (~/.zshrc 或 ~/.bashrc):"
    echo ""
    printf "${BLUE}$ALIAS_CMD${NC}\n"
    echo ""
}

# ========================================
# Claude Code 安装
# ========================================

if [[ "$INSTALL_CLAUDE" == "true" ]]; then
    printf "${BLUE}=== 正在为 Claude Code 安装通知功能 ===${NC}\n"

    CLAUDE_ROOT="$HOME/.claude"
    CLAUDE_SCRIPTS="$CLAUDE_ROOT/scripts"
    CLAUDE_ASSETS="$CLAUDE_ROOT/assets"

    mkdir -p "$CLAUDE_SCRIPTS"
    mkdir -p "$CLAUDE_ASSETS"
    printf "${GREEN}✓ 创建 Claude 安装目录: $CLAUDE_SCRIPTS${NC}\n"

    # 复制脚本
    cp "$SCRIPT_SOURCE" "$CLAUDE_SCRIPTS/notify.sh"
    chmod +x "$CLAUDE_SCRIPTS/notify.sh"

    if [ -f "$TOGGLE_SOURCE" ]; then
        cp "$TOGGLE_SOURCE" "$CLAUDE_SCRIPTS/toggle.sh"
        chmod +x "$CLAUDE_SCRIPTS/toggle.sh"
        printf "${GREEN}✓ 开关脚本 (toggle.sh) 已安装${NC}\n"
    fi

    # 安装配置文件
    CONF_DEST="$CLAUDE_ROOT/notifier.conf"
    if [ ! -f "$CONF_DEST" ]; then
        if [ -f "$CONF_SOURCE" ]; then
            cp "$CONF_SOURCE" "$CONF_DEST"
            printf "${GREEN}✓ 配置文件已安装到: $CONF_DEST${NC}\n"
        fi
    else
        printf "${YELLOW}提示: 配置文件已存在，跳过覆盖。${NC}\n"
    fi

    # 复制 Logo
    if [ -f "$LOGO_SOURCE" ]; then
        cp "$LOGO_SOURCE" "$CLAUDE_ASSETS/logo.png"
        printf "${GREEN}✓ Logo 图标已安装${NC}\n"
    fi

    # 检查依赖 (Terminal Notifier / Libnotify)
    OS_TYPE=$(uname -s)
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        if ! command -v terminal-notifier &> /dev/null; then
            if command -v brew &> /dev/null; then
                printf "${YELLOW}未检测到 terminal-notifier，正在尝试通过 Homebrew 自动安装...${NC}\n"
                if brew install terminal-notifier; then
                    printf "${GREEN}✓ terminal-notifier 安装成功${NC}\n"
                else
                    printf "${YELLOW}自动安装失败，将使用原生通知。${NC}\n"
                fi
            else
                printf "${YELLOW}提示: 未检测到 terminal-notifier，将使用原生通知。${NC}\n"
            fi
        else
            printf "${GREEN}✓ 检测到 terminal-notifier${NC}\n"
        fi
    elif [[ "$OS_TYPE" == "Linux" ]]; then
         if ! command -v notify-send &> /dev/null; then
            printf "${YELLOW}提示: 未检测到 notify-send。建议安装 libnotify-bin。${NC}\n"
         else
            printf "${GREEN}✓ 检测到 notify-send${NC}\n"
         fi
    fi

    # 修改 settings.json
    SETTINGS_FILE="$HOME/.claude/settings.json"
    printf "${BLUE}正在配置 ~/.claude/settings.json ...${NC}\n"

    python3 -c "
import json
import os
import sys

settings_path = os.path.expanduser('~/.claude/settings.json')
script_path = os.path.expanduser('~/.claude/scripts/notify.sh')

if not os.path.exists(settings_path):
    print(f'创建新的配置文件: {settings_path}')
    data = {}
else:
    try:
        with open(settings_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        print('错误: settings.json 格式无效')
        data = {}

if 'hooks' not in data:
    data['hooks'] = {}

target_hooks = {
    'PermissionRequest': {
        'command': f'CLAUDE_TOOL_NAME=\"PermissionRequest\" {script_path}',
        'type': 'command'
    },
    'Stop': {
        'command': f'CLAUDE_TOOL_NAME=\"Stop\" {script_path}',
        'type': 'command'
    }
}

for event, hook_config in target_hooks.items():
    if event not in data['hooks']:
        data['hooks'][event] = []

    exists = False
    for matcher_group in data['hooks'][event]:
        if matcher_group.get('matcher') == '*':
            for h in matcher_group.get('hooks', []):
                if script_path in h.get('command', ''):
                    exists = True
                    break
        if exists: break

    if not exists:
        new_entry = {
            'matcher': '*',
            'hooks': [hook_config]
        }
        data['hooks'][event].append(new_entry)
        print(f'  - 已添加 {event} hook')

with open(settings_path, 'w') as f:
    json.dump(data, f, indent=2)
"

    # 配置 Slash Command
    COMMANDS_DIR="$HOME/.claude/commands"
    mkdir -p "$COMMANDS_DIR"
    NOTIFIER_MD="$COMMANDS_DIR/notifier.md"

    cat > "$NOTIFIER_MD" <<EOF
---
description: Control Claude Code desktop notifications
---

# Notifier Control

此命令用于管理 Claude Code 的桌面通知设置。

## Usage

\`\`\`bash
$CLAUDE_SCRIPTS/toggle.sh [on|off|status]
\`\`\`
EOF
    printf "${GREEN}✓ 命令定义已创建: $NOTIFIER_MD${NC}\n"
    printf "${GREEN}✓ Claude Code 集成完成${NC}\n"

fi # End Claude Code installation

# ========================================
# Codex 安装
# ========================================

if [[ "$INSTALL_CODEX" == "true" ]]; then
    install_codex_notifications
fi

# ========================================
# Gemini 安装
# ========================================

if [[ "$INSTALL_GEMINI" == "true" ]]; then
    install_gemini_notifications
fi

# 最终消息
printf "${BLUE}=== Agent CLI Notifier 安装成功 ===${NC}\n"
if [[ "$INSTALL_CLAUDE" == "true" ]]; then
    echo -e "Claude Code: 安装于 ~/.claude/scripts"
fi
if [[ "$INSTALL_CODEX" == "true" ]]; then
    echo -e "OpenAI Codex: 安装于 ~/.codex/scripts (独立运行)"
fi
if [[ "$INSTALL_GEMINI" == "true" ]]; then
    echo -e "Google Gemini: 安装于 ~/.gemini/scripts"
fi
