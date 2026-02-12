#!/usr/bin/env python3
import os
import sys
import pty
import select
import subprocess
import re
import time
import fcntl
import termios
import struct
import signal
import errno
import tty
import threading

# Configuration
NOTIFY_SCRIPT = os.path.expanduser("~/.claude/scripts/notify.sh")

# Global state for notification timer management
notification_timer = None
notification_lock = threading.Lock()

# Regex patterns to match in screen output
PATTERNS = {
    r"(?i)(waiting for user|permission required|confirmation needed|user input required|awaiting approval|Would you like to)": "PermissionRequest",
    r"(?i)(task complete|execution finished|done\.|completed successfully)": "Stop",
    # Match bullet point • which may be preceded by ANSI color codes, newlines, or start of string
    # But EXCLUDE if followed by common tool action verbs (Running, Reading, etc.) or status updates (Edited, Updated, etc.)
    r"(?:(?:\x1b\[[0-9;]*m)+|^|\n)\s*•\s+(?!(?:Running|Reading|Writing|Editing|Creating|Updating|Deleting|Listing|Searching|Working|Edited|Created|Updated|Deleted|Renamed|Moved|Ran|Added|\w+ing)\b)": "Stop"
}

def get_terminal_size(fd):
    """Get the current size of the terminal."""
    try:
        size = fcntl.ioctl(fd, termios.TIOCGWINSZ, struct.pack('HHHH', 0, 0, 0, 0))
        return struct.unpack('HHHH', size)
    except Exception:
        return None

def set_terminal_size(fd, size):
    """Set the size of the terminal (pty master)."""
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', *size))
    except Exception:
        pass

def send_notification_delayed(event_type, delay=0):
    """
    延迟发送通知，支持自动重置计时器

    Args:
        event_type: "PermissionRequest" 或 "Stop"
        delay: 延迟秒数（0 = 立即，3 = 等待空闲）
    """
    global notification_timer, notification_lock

    with notification_lock:
        # 1. 取消旧的计时器（如果存在）
        if notification_timer is not None:
            notification_timer.cancel()

        # 2. 定义实际发送通知的函数
        def _do_send():
            if os.path.exists(NOTIFY_SCRIPT):
                env = os.environ.copy()
                env["CLAUDE_TOOL_NAME"] = event_type
                subprocess.Popen([NOTIFY_SCRIPT], env=env)

        # 3. 根据延迟时间创建计时器
        if delay == 0:
            # 立即发送（PermissionRequest）
            _do_send()
            notification_timer = None
        else:
            # 延迟发送（Stop），在后台线程等待
            notification_timer = threading.Timer(delay, _do_send)
            notification_timer.start()

def analyze_output(data):
    """分析输出并触发通知（带智能延迟）"""
    try:
        text = data.decode('utf-8', errors='ignore')
        for pattern, event_type in PATTERNS.items():
            if re.search(pattern, text):
                # 根据事件类型设置延迟
                if event_type == "PermissionRequest":
                    send_notification_delayed(event_type, delay=0)  # 立即
                elif event_type == "Stop":
                    send_notification_delayed(event_type, delay=3.0)  # 3秒空闲
    except Exception:
        pass

def cleanup_timers():
    """清理所有未完成的计时器（退出时调用）"""
    global notification_timer, notification_lock
    with notification_lock:
        if notification_timer is not None:
            notification_timer.cancel()
            notification_timer = None

def robust_spawn(argv):
    """
    A robust version of pty.spawn that handles window resizing and output analysis.
    """
    # Fork the pty
    pid, master_fd = pty.fork()

    # Child process: Execute the command
    if pid == 0:
        os.execlp(argv[0], *argv)

    # Parent process
    try:
        # 1. Set initial size
        initial_size = get_terminal_size(sys.stdout.fileno())
        if initial_size:
            set_terminal_size(master_fd, initial_size)

        # 2. Define SIGWINCH handler
        def _sigwinch_handler(signum, frame):
            new_size = get_terminal_size(sys.stdout.fileno())
            if new_size:
                set_terminal_size(master_fd, new_size)

        # 3. Register signal handler
        signal.signal(signal.SIGWINCH, _sigwinch_handler)

        # 4. Main IO Loop
        mode = termios.tcgetattr(sys.stdin.fileno())
        tty.setraw(sys.stdin.fileno())

        try:
            while True:
                try:
                    # Wait for data from either stdin (user input) or master_fd (program output)
                    r, w, x = select.select([sys.stdin, master_fd], [], [])
                except select.error as e:
                    if e.args[0] == errno.EINTR:
                        continue # Interrupted by SIGWINCH, ignore and loop
                    raise

                # User input -> Program
                if sys.stdin in r:
                    data = os.read(sys.stdin.fileno(), 1024)
                    if not data: break
                    os.write(master_fd, data)

                # Program output -> Screen (and Analysis)
                if master_fd in r:
                    data = os.read(master_fd, 1024)
                    if not data: break

                    # 1. Write to screen immediately
                    os.write(sys.stdout.fileno(), data)

                    # 2. Analyze for notifications (non-blocking)
                    analyze_output(data)

        except OSError:
            pass # End of file (child exited)

    finally:
        # 退出前清理计时器
        cleanup_timers()

        # Restore terminal attributes and close fd
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSAFLUSH, mode)
        os.close(master_fd)
        os.waitpid(pid, 0)
        # Restore default signal handler
        signal.signal(signal.SIGWINCH, signal.SIG_DFL)

def main():
    real_codex = os.environ.get("REAL_CODEX_PATH")
    if not real_codex:
        print("Error: REAL_CODEX_PATH environment variable not set.")
        sys.exit(1)

    args = [real_codex] + sys.argv[1:]

    try:
        robust_spawn(args)
    except FileNotFoundError:
        print(f"Error: Could not execute command: {real_codex}")
        sys.exit(1)
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
