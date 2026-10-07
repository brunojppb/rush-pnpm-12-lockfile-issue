#!/usr/bin/env bash
# Shows a Rush bug with pnpm 12. `rush update` can keep the old committed lockfile.
# The committed lockfile then does not match the temp lockfile or node_modules.
set -euo pipefail

cd "$(dirname "$0")"

# Runs the Rush version that rush.json pins. You do not need a global rush command.
rush() { node common/scripts/install-run-rush.js "$@"; }

# The steps change these files. The script puts back the saved copies when it stops.
SAVED="$(mktemp -d)"
cp rush.json "$SAVED/rush.json"
cp packages/app/package.json "$SAVED/app-package.json"
trap 'cp "$SAVED/rush.json" rush.json; cp "$SAVED/app-package.json" packages/app/package.json; rm -r "$SAVED"' EXIT

PNPM_OLD=11.24.0
PNPM_NEW=12.10.1
COMMITTED=common/config/rush/pnpm-lock.yaml
TEMP=common/temp/pnpm-lock.yaml
LINK=packages/app/node_modules/@graphql-typed-document-node/core

# Prints the graphql version that a lockfile records for the peer of
# @graphql-typed-document-node/core in app.
variant() {
  awk '/^  \.\.\/\.\.\/packages\/app:/{p=1;next} p&&/^  [^ ]/{p=0} p' "$1" \
    | grep -A2 "typed-document-node/core'" | grep -o 'graphql@[^)]*' || echo "(none)"
}

# Prints the graphql version that node_modules links for the peer of
# @graphql-typed-document-node/core in app.
linked() {
  readlink "$LINK" | grep -o 'graphql@[^/]*' || echo "(none)"
}

set_pnpm() {
  sed -i.bak -E "s/\"pnpmVersion\": \"[^\"]+\"/\"pnpmVersion\": \"$1\"/" rush.json && rm rush.json.bak
}

set_app_graphql() {
  node -e '
    const fs = require("fs");
    const f = "packages/app/package.json";
    const p = JSON.parse(fs.readFileSync(f, "utf8"));
    if (process.argv[1] === "add") p.dependencies.graphql = "17.0.0-alpha.7";
    else delete p.dependencies.graphql;
    p.dependencies = Object.fromEntries(Object.entries(p.dependencies).sort());
    fs.writeFileSync(f, JSON.stringify(p, null, 2) + "\n");
  ' "$1"
}

step() { printf '\n== %s\n' "$1"; }

step "Start from the same state each time"
rush purge >/dev/null
rm -f "$COMMITTED" common/config/rush/repo-state.json
set_pnpm "$PNPM_OLD"
set_app_graphql add

step "1. app depends on graphql@17.0.0-alpha.7. Run rush update with pnpm $PNPM_OLD"
rush update >/dev/null
echo "committed lockfile: $(variant "$COMMITTED")"

step "2. Remove graphql from app. Run rush update with pnpm $PNPM_OLD"
set_app_graphql remove
rush update >/dev/null
echo "committed lockfile: $(variant "$COMMITTED")"
echo "node_modules:       $(linked)"
BEFORE="$(mktemp)"; cp "$COMMITTED" "$BEFORE"

step "3. Set pnpm to $PNPM_NEW, then run rush update"
set_pnpm "$PNPM_NEW"
rush update >/dev/null
echo "temp lockfile:      $(variant "$TEMP")"
echo "committed lockfile: $(variant "$COMMITTED")"
echo "node_modules:       $(linked)"
if cmp -s "$COMMITTED" "$BEFORE"; then
  echo "committed lockfile changed: no"
else
  echo "committed lockfile changed: yes"
fi
rm "$BEFORE"

step "4. Run rush purge, then rush install with pnpm $PNPM_NEW"
rush purge >/dev/null
rush install >/dev/null
echo "committed lockfile: $(variant "$COMMITTED")"
echo "node_modules:       $(linked)"

step "Result"
if [ "$(variant "$COMMITTED")" != "$(linked)" ]; then
  echo "BUG: the committed lockfile records $(variant "$COMMITTED"), but node_modules links $(linked)."
  exit 1
fi
echo "OK: the committed lockfile matches node_modules."
