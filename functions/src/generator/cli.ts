// `node lib/generator/cli.js <rules.json>`: one JSON line with the rules'
// problems and, when they have none, the options they give, for
// tool/import_content.dart and tool/validate_content.dart. Exits 2 when the
// file cannot be read as JSON.
import { readFileSync } from "node:fs";

import { Rules, optionsOf, rulesProblems } from "./rules";

let rules: unknown;
try {
  rules = JSON.parse(readFileSync(process.argv[2], "utf8"));
} catch (error) {
  process.stderr.write(`${error}\n`);
  process.exit(2);
}
const problems = rulesProblems(rules);
process.stdout.write(
  JSON.stringify({
    problems,
    options: problems.length === 0 ? optionsOf(rules as Rules) : null,
  }) + "\n",
);
