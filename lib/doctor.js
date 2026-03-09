"use strict";

const { getAllStates } = require("./targets");

function runDoctor() {
  const states = getAllStates();
  const lines = ["Agent CLI Notifier doctor", ""];
  let hasFailures = false;

  for (const target of states) {
    if (!target.installed) {
      lines.push(`- ${target.label}: skipped (not installed)`);
      continue;
    }

    lines.push(`- ${target.label}: installed`);
    for (const detail of target.details) {
      if (!detail.ok) {
        hasFailures = true;
      }
      lines.push(`  ${detail.ok ? "OK" : "FAIL"} ${detail.label}`);
    }
  }

  if (!states.some((target) => target.installed)) {
    lines.push("- No notifier integrations are currently installed.");
  }

  return {
    ok: !hasFailures,
    output: lines.join("\n"),
  };
}

module.exports = {
  runDoctor,
};
