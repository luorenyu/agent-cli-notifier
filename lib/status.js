"use strict";

const { getAllStates } = require("./targets");

function renderStatus() {
  const states = getAllStates();
  const lines = ["Agent CLI Notifier status", ""];

  for (const target of states) {
    const status = target.installed ? "installed" : "not installed";
    const availability = target.available ? "detected" : "not detected";
    lines.push(`- ${target.label}: ${status} (${availability})`);
  }

  return lines.join("\n");
}

module.exports = {
  renderStatus,
};
