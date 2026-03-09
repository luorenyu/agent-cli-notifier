"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const home = os.homedir();

const TARGETS = {
  claude: {
    label: "Claude Code",
    command: "claude",
    installRoot: path.join(home, ".claude"),
    files: [path.join(home, ".claude", "scripts", "notify.sh")],
  },
  codex: {
    label: "OpenAI Codex",
    command: "codex",
    installRoot: path.join(home, ".codex"),
    files: [
      path.join(home, ".codex", "scripts", "notify.sh"),
      path.join(home, ".codex", "scripts", "codex_wrapper.py"),
      path.join(home, ".codex", "scripts", "codex-notify"),
    ],
  },
  gemini: {
    label: "Google Gemini CLI",
    command: "gemini",
    installRoot: path.join(home, ".gemini"),
    files: [
      path.join(home, ".gemini", "scripts", "notify.sh"),
      path.join(home, ".gemini", "scripts", "gemini_bridge.sh"),
    ],
  },
};

function commandExists(command) {
  const result = spawnSync("/bin/sh", ["-lc", `command -v ${command}`], {
    stdio: "ignore",
  });
  return result.status === 0;
}

function readJson(jsonPath) {
  try {
    return JSON.parse(fs.readFileSync(jsonPath, "utf8"));
  } catch {
    return null;
  }
}

function fileExists(filePath) {
  try {
    fs.accessSync(filePath, fs.constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

function hasClaudeHooks() {
  const settings = readJson(path.join(home, ".claude", "settings.json"));
  if (!settings || !settings.hooks) return false;
  return ["PermissionRequest", "Stop"].every((eventName) => {
    const groups = settings.hooks[eventName] || [];
    return groups.some((group) =>
      (group.hooks || []).some((hook) =>
        String(hook.command || "").includes(".claude/scripts/notify.sh")
      )
    );
  });
}

function hasGeminiHooks() {
  const settings = readJson(path.join(home, ".gemini", "settings.json"));
  if (!settings || !settings.hooks) return false;
  return ["Notification", "AfterAgent"].every((eventName) => {
    const groups = settings.hooks[eventName] || [];
    return groups.some((group) =>
      (group.hooks || []).some((hook) =>
        String(hook.command || "").includes(".gemini/scripts/gemini_bridge.sh")
      )
    );
  });
}

function hasCodexAlias() {
  const shellFiles = [".zshrc", ".bashrc"].map((name) => path.join(home, name));
  return shellFiles.some((rcPath) => {
    if (!fileExists(rcPath)) return false;
    const content = fs.readFileSync(rcPath, "utf8");
    return content.includes("alias codex=") && content.includes(".codex/scripts/codex-notify");
  });
}

function getTargetState(targetName) {
  const target = TARGETS[targetName];
  const installed = target.files.every(fileExists);
  const available = commandExists(target.command) || fileExists(target.installRoot);
  const details = [];

  if (targetName === "claude") {
    details.push({ label: "hooks", ok: hasClaudeHooks() });
  }
  if (targetName === "gemini") {
    details.push({ label: "hooks", ok: hasGeminiHooks() });
  }
  if (targetName === "codex") {
    details.push({ label: "alias", ok: hasCodexAlias() });
  }

  return {
    name: targetName,
    label: target.label,
    available,
    installed,
    details,
  };
}

function getAllStates() {
  return Object.keys(TARGETS).map(getTargetState);
}

function resolveTargets(inputTargets) {
  if (!inputTargets || inputTargets.length === 0) {
    return [];
  }

  return inputTargets.map((target) => {
    const normalized = String(target).trim().toLowerCase();
    if (!TARGETS[normalized]) {
      throw new Error(`Unsupported target: ${target}`);
    }
    return normalized;
  });
}

function autoDetectTargets() {
  return getAllStates()
    .filter((target) => target.available)
    .map((target) => target.name);
}

module.exports = {
  TARGETS,
  autoDetectTargets,
  getAllStates,
  getTargetState,
  resolveTargets,
};
