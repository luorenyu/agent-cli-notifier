#!/bin/bash

# Agent CLI Notifier
# 功能：桌面通知 + 长提示音 + 自动跳转终端 + 显示工作信息
# 兼容性：支持 terminal-notifier (推荐) 和原生 macOS 通知

TOOL_NAME="${CLAUDE_TOOL_NAME:-未知操作}"

# 获取当前工作目录名称作为项目标识
PROJECT_NAME=$(basename "$PWD")

# 生成唯一 ID，避免通知被合并
UNIQUE_ID="claude-$(date +%s)-$$-$RANDOM"
OS_TYPE=$(uname -s)

# --- 配置加载 ---

# 默认配置
if [[ "$OS_TYPE" == "Darwin" ]]; then
    SOUND_PERMISSION="/System/Library/Sounds/Hero.aiff"
    SOUND_STOP="/System/Library/Sounds/Glass.aiff"
else
    # Linux 常用声音路径 (freedesktop 标准)
    SOUND_PERMISSION="/usr/share/sounds/freedesktop/stereo/dialog-warning.oga"
    SOUND_STOP="/usr/share/sounds/freedesktop/stereo/complete.oga"
fi

ACTIVATE_ON_PERMISSION=true
ACTIVATE_ON_STOP=false
RESPECT_FOCUS_MODE=true
ICON_PATH="$HOME/.claude/assets/logo.png"
TITLE_PERMISSION="⚠️ Claude Code 等待确认"
TITLE_STOP="✅ Claude Code 回复完成"

# 加载用户配置 (如果存在)
CONFIG_FILE="$HOME/.claude/notifier.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# --- 逻辑处理 ---

# 根据事件类型设置不同的通知内容
if [[ "$TOOL_NAME" == "PermissionRequest" ]]; then
    NOTIFICATION_TITLE="$TITLE_PERMISSION"
    NOTIFICATION_MESSAGE="需要你的确认才能继续操作"
    SOUND_FILE="$SOUND_PERMISSION"
    SHOULD_ACTIVATE_TERMINAL="$ACTIVATE_ON_PERMISSION"
elif [[ "$TOOL_NAME" == "Stop" ]]; then
    NOTIFICATION_TITLE="$TITLE_STOP"
    NOTIFICATION_MESSAGE="任务已完成，请查看结果"
    SOUND_FILE="$SOUND_STOP"
    SHOULD_ACTIVATE_TERMINAL="$ACTIVATE_ON_STOP"
else
    NOTIFICATION_TITLE="🔔 Claude Code 通知"
    NOTIFICATION_MESSAGE="操作: $TOOL_NAME"
    SOUND_FILE="$SOUND_PERMISSION"
    SHOULD_ACTIVATE_TERMINAL=false
fi

# 检查声音文件是否存在，如果不存在且是 Linux，尝试回退到默认
if [[ "$OS_TYPE" == "Linux" ]] && [[ ! -f "$SOUND_FILE" ]]; then
    if [[ "$TOOL_NAME" == "PermissionRequest" ]]; then
        SOUND_FILE="/usr/share/sounds/freedesktop/stereo/dialog-warning.oga"
    else
        SOUND_FILE="/usr/share/sounds/freedesktop/stereo/complete.oga"
    fi
fi

# --- 终端检测逻辑 ---

# 获取终端程序名称和显示名称
TERMINAL_APP="${TERM_PROGRAM:-}"
TERMINAL_EMULATOR="${TERMINAL_EMULATOR:-}"
BUNDLE_IDENTIFIER="${__CFBundleIdentifier:-}"

# 识别终端类型
if [[ "$TERMINAL_APP" == "iTerm.app" ]]; then
    APP_NAME="iTerm"
    TERMINAL_NAME="iTerm2"
elif [[ "$TERMINAL_APP" == "Apple_Terminal" ]]; then
    APP_NAME="Terminal"
    TERMINAL_NAME="Terminal"
elif [[ "$TERMINAL_APP" == "vscode" ]]; then
    APP_NAME="Visual Studio Code"
    TERMINAL_NAME="VS Code"
elif [[ "$TERMINAL_APP" == "cursor" ]]; then
    APP_NAME="Cursor"
    TERMINAL_NAME="Cursor"
elif [[ "$TERMINAL_APP" == "Warp" ]]; then
    APP_NAME="Warp"
    TERMINAL_NAME="Warp"
elif [[ "$TERMINAL_EMULATOR" == "JetBrains-JediTerm" ]]; then
    # JetBrains 系列 IDE 粗略匹配
    if [[ "$BUNDLE_IDENTIFIER" == *"android"* ]]; then
        APP_NAME="Android Studio"
    elif [[ "$BUNDLE_IDENTIFIER" == *"intellij"* ]]; then
        APP_NAME="IntelliJ IDEA"
    elif [[ "$BUNDLE_IDENTIFIER" == *"pycharm"* ]]; then
        APP_NAME="PyCharm"
    elif [[ "$BUNDLE_IDENTIFIER" == *"webstorm"* ]]; then
        APP_NAME="WebStorm"
    elif [[ "$BUNDLE_IDENTIFIER" == *"goland"* ]]; then
        APP_NAME="GoLand"
    else
        APP_NAME="JetBrains IDE"
    fi
    TERMINAL_NAME="$APP_NAME"
else
    APP_NAME="${TERMINAL_APP:-Terminal}"
    TERMINAL_NAME="${TERMINAL_APP:-未知终端}"
fi

# --- 通知发送逻辑 ---

TITLE="$NOTIFICATION_TITLE"
SUBTITLE="终端: $TERMINAL_NAME | 项目: $PROJECT_NAME"
MESSAGE="$NOTIFICATION_MESSAGE"
# ICON_PATH 已在配置部分定义

send_notification() {
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        # macOS 逻辑
        # 检查是否安装了 terminal-notifier
        if command -v terminal-notifier >/dev/null 2>&1; then
            # 准备声音名称 (去除路径和扩展名)
            SOUND_NAME=$(basename "$SOUND_FILE")
            SOUND_NAME="${SOUND_NAME%.*}"

            # 构建基础命令
            CMD="terminal-notifier -title \"$TITLE\" -subtitle \"$SUBTITLE\" -message \"$MESSAGE\" -group \"$UNIQUE_ID\" -activate \"$BUNDLE_IDENTIFIER\""

            # 处理 Focus Mode / DND
            if [[ "$RESPECT_FOCUS_MODE" != "true" ]]; then
                CMD="$CMD -ignoreDnD"
            fi

            # 添加声音 (由 terminal-notifier 统一管理，以遵循 DND 设置)
            if [[ -n "$SOUND_NAME" ]]; then
                CMD="$CMD -sound \"$SOUND_NAME\""
            fi

            # 如果存在自定义图标，添加图标参数
            if [[ -f "$ICON_PATH" ]]; then
                CMD="$CMD -appIcon \"$ICON_PATH\""
            fi

            eval "$CMD" >/dev/null 2>&1
        else
            # 方案 B: 使用原生 AppleScript (零依赖)
            osascript -e "display notification \"$SUBTITLE\n$MESSAGE\" with title \"$TITLE\"" >/dev/null 2>&1
        fi
    elif [[ "$OS_TYPE" == "Linux" ]]; then
        # Linux 逻辑 (使用 notify-send)
        if command -v notify-send >/dev/null 2>&1; then
            # 尝试使用自定义图标
            ICON_ARGS=""
            if [[ -f "$ICON_PATH" ]]; then
                ICON_ARGS="-i \"$ICON_PATH\""
            fi

            # 发送通知
            # 这里的 \"$SUBTITLE\n$MESSAGE\" 可能在某些实现中不换行，但大部分支持
            notify-send -a "Claude Code" "$TITLE" "$SUBTITLE\n$MESSAGE" $ICON_ARGS >/dev/null 2>&1
        else
            # 如果没有 notify-send，尝试 wall (虽然后台运行看不到) 或忽略
            :
        fi
    fi
}

# 1. 发送视觉通知 (后台运行)
send_notification &

# 2. 播放声音 (后台运行)
if [[ -f "$SOUND_FILE" ]]; then
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        # macOS: 如果使用 terminal-notifier，声音已在 send_notification 中处理
        # 只有在没有 terminal-notifier 时才手动播放
        if ! command -v terminal-notifier >/dev/null 2>&1; then
            afplay "$SOUND_FILE" &
        fi
    elif [[ "$OS_TYPE" == "Linux" ]]; then
        if command -v paplay >/dev/null 2>&1; then
            paplay "$SOUND_FILE" &
        elif command -v aplay >/dev/null 2>&1; then
            aplay "$SOUND_FILE" &
        fi
    fi
fi

# 3. 如果需要，自动激活终端窗口
if [[ "$SHOULD_ACTIVATE_TERMINAL" == "true" ]]; then
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        # 尝试激活应用
        osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1 &
    elif [[ "$OS_TYPE" == "Linux" ]]; then
        # Linux 窗口激活非常复杂 (X11 vs Wayland, 不同的 WM)
        # 尝试使用 wmctrl (仅 X11 有效)
        if command -v wmctrl >/dev/null 2>&1; then
            # 这是一个简单的尝试，可能无法准确找到当前窗口
            # 最好是通过 PID 或 WM_CLASS，但 shell 中获取比较困难
            # 这里暂时留空，避免在 Wayland 下报错或不可预测的行为
            :
        fi
    fi
fi
