#!/usr/bin/env bash
# Shows that `rush update` with pnpm 12 can leave common/config/rush/pnpm-lock.yaml
# out of sync with the lockfile that pnpm wrote and with node_modules.
set -euo pipefail

cd "$(dirname "$0")"

# The steps edit these files; put them back so a rerun starts from the committed state.
trap 'git checkout -- rush.json packages/app/package.json' EXIT

PNPM_OLD=11.24.0
PNPM_NEW=12.10.1
COMMITTED=common/config/rush/pnpm-lock.yaml
TEMP=common/temp/pnpm-lock.yaml
LINK=packages/app/node_modules/@graphql-typed-document-node/core

# Prints the peer variant that the lockfile records for app -> @graphql-typed-document-node/core.
variant() {
  awk '/^  \.\.\/\.\.\/packages\/app:/{p=1;next} p&&/^  [^ ]/{p=0} p' "$1" \
    | grep -A2 "typed-document-node/core'" | grep -o 'graphql@[^)]*' || echo "(none)"
}

# Prints the peer variant that node_modules links for app -> @graphql-typed-document-node/core.
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

step "Reset to a clean state"
rush purge >/dev/null
rm -f "$COMMITTED" common/config/rush/repo-state.json
set_pnpm "$PNPM_OLD"
set_app_graphql add

step "1. app depends on graphql@17.0.0-alpha.7 directly; rush update with pnpm $PNPM_OLD"
rush update >/dev/null
echo "committed lockfile: $(variant "$COMMITTED")"

step "2. Remove graphql from app; rush update with pnpm $PNPM_OLD"
set_app_graphql remove
rush update >/dev/null
echo "committed lockfile: $(variant "$COMMITTED")"
echo "node_modules link:  $(linked)"
BEFORE="$(mktemp)"; cp "$COMMITTED" "$BEFORE"

step "3. Switch to pnpm $PNPM_NEW; rush update"
set_pnpm "$PNPM_NEW"
rush update >/dev/null
echo "temp lockfile:      $(variant "$TEMP")"
echo "committed lockfile: $(variant "$COMMITTED")"
echo "node_modules link:  $(linked)"
if cmp -s "$COMMITTED" "$BEFORE"; then
  echo "committed lockfile changed: no"
else
  echo "committed lockfile changed: yes"
fi
rm "$BEFORE"

step "4. Clean checkout: rush purge; rush install with pnpm $PNPM_NEW"
rush purge >/dev/null
rush install >/dev/null
echo "committed lockfile: $(variant "$COMMITTED")"
echo "node_modules link:  $(linked)"

step "Result"
if [ "$(variant "$COMMITTED")" != "$(linked)" ]; then
  echo "BUG: the committed lockfile records $(variant "$COMMITTED"), but node_modules links $(linked)."
  exit 1
fi
echo "OK: the committed lockfile matches node_modules."
