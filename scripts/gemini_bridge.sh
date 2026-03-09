#!/bin/bash

# Bridge script for Gemini CLI to Agent CLI Notifier
# Used to adapt Gemini hook events to the environment variables expected by notify.sh

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
NOTIFY_SCRIPT="$SCRIPT_DIR/notify.sh"

if [ ! -f "$NOTIFY_SCRIPT" ]; then
    echo "Error: notify.sh not found at $NOTIFY_SCRIPT"
    exit 1
fi

# The first argument is the event type passed from the hook configuration
# Usage: ./gemini_bridge.sh "PermissionRequest"
# Usage: ./gemini_bridge.sh "Stop"

EVENT_TYPE="$1"

if [ -z "$EVENT_TYPE" ]; then
    EVENT_TYPE="Notification"
fi

# Export the variable expected by notify.sh
export CLAUDE_TOOL_NAME="$EVENT_TYPE"

# Execute the notification script
"$NOTIFY_SCRIPT"
