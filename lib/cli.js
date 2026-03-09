"use strict";

const path = require("path");
const { spawnSync } = require("child_process");
const { autoDetectTargets, resolveTargets } = require("./targets");
const { renderStatus } = require("./status");
const { runDoctor } = require("./doctor");

function printHelp() {
  console.log(`Agent CLI Notifier

Usage:
  agent-notifier init [--targets claude,codex,gemini] [--auto]
  agent-notifier uninstall [--targets claude,codex,gemini] [--yes]
  agent-notifier status
  agent-notifier doctor

Notes:
  --auto on init enables non-interactive installation.
  --yes on uninstall enables non-interactive removal.
  If init is called with --auto and no --targets, the CLI auto-detects available agents.
`);
}

function parseArgs(argv) {
  const result = {
    command: argv[0] || "help",
    targets: [],
    auto: false,
    yes: false,
  };

  for (let index = 1; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--auto") {
      result.auto = true;
      continue;
    }
    if (arg === "--yes") {
      result.yes = true;
      continue;
    }
    if (arg === "--targets") {
      result.targets = argv[index + 1] ? argv[index + 1].split(",") : [];
      index += 1;
      continue;
    }
    if (arg.startsWith("--targets=")) {
      result.targets = arg.slice("--targets=".length).split(",");
      continue;
    }
    if (arg === "-h" || arg === "--help") {
      result.command = "help";
      return result;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  return result;
}

function runScript(scriptName, args) {
  const scriptPath = path.join(__dirname, "..", scriptName);
  const result = spawnSync("bash", [scriptPath, ...args], { stdio: "inherit" });
  process.exit(result.status ?? 1);
}

function normalizeTargets(parsed) {
  if (parsed.targets.length > 0) {
    return resolveTargets(parsed.targets);
  }
  if (parsed.auto) {
    return autoDetectTargets();
  }
  return [];
}

function main() {
  let parsed;
  try {
    parsed = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    printHelp();
    process.exit(1);
  }

  if (parsed.command === "help" || parsed.command === "--help" || parsed.command === "-h") {
    printHelp();
    return;
  }

  if (parsed.command === "status") {
    console.log(renderStatus());
    return;
  }

  if (parsed.command === "doctor") {
    const result = runDoctor();
    console.log(result.output);
    process.exit(result.ok ? 0 : 1);
  }

  if (parsed.command === "init") {
    const targets = normalizeTargets(parsed);
    if (parsed.auto && targets.length === 0) {
      console.error("No supported agents detected. Pass --targets explicitly.");
      process.exit(1);
    }

    const args = [];
    if (targets.length > 0) {
      args.push("--targets", targets.join(","));
    }
    if (parsed.auto) {
      args.push("--yes");
    }
    runScript("install.sh", args);
    return;
  }

  if (parsed.command === "uninstall") {
    const targets = parsed.targets.length > 0 ? resolveTargets(parsed.targets) : [];
    const args = [];
    if (targets.length > 0) {
      args.push("--targets", targets.join(","));
    }
    if (parsed.yes || parsed.auto) {
      args.push("--yes");
    }
    runScript("uninstall.sh", args);
    return;
  }

  console.error(`Unknown command: ${parsed.command}`);
  printHelp();
  process.exit(1);
}

module.exports = {
  main,
};
