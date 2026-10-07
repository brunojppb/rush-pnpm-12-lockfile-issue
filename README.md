# Rush + pnpm 12: committed lockfile goes out of sync with node_modules

With pnpm 12, `rush update` can leave `common/config/rush/pnpm-lock.yaml` unchanged while pnpm writes a different lockfile and links different packages. A later `rush install` on a clean checkout also links packages that the committed lockfile does not record.

## Run it

You need Node 22 and the `rush` command on your `PATH`. Rush downloads Rush 5.181.0 and the pinned pnpm versions on its own.

```bash
./repro.sh
```

The script starts from a clean state each time. It exits 1 when it finds the bug.

## What the script does

The repo holds three projects:

- `lib` depends on `graphql@17.0.0-alpha.7`.
- `legacy` depends on `graphql@16.13.1`.
- `app` depends on `lib` and on `@graphql-typed-document-node/core@3.2.0`, which has a peer dependency on `graphql`.

The steps:

1. `app` also depends on `graphql@17.0.0-alpha.7`. `rush update` with pnpm 11.24.0 records the peer variant `3.2.0(graphql@17.0.0-alpha.7)`.
2. The script removes `graphql` from `app`. `rush update` with pnpm 11.24.0 keeps that peer variant.
3. The script switches `pnpmVersion` to 12.10.1 and runs `rush update`.
4. The script runs `rush purge` and `rush install`, the same as CI on a clean checkout.

## Output

```
== 3. Switch to pnpm 12.10.1; rush update
temp lockfile:      graphql@16.13.1
committed lockfile: graphql@17.0.0-alpha.7
node_modules link:  graphql@16.13.1
committed lockfile changed: no

== 4. Clean checkout: rush purge; rush install with pnpm 12.10.1
committed lockfile: graphql@17.0.0-alpha.7
node_modules link:  graphql@16.13.1

== Result
BUG: the committed lockfile records graphql@17.0.0-alpha.7, but node_modules links graphql@16.13.1.
```

## Expected

After step 3, `common/config/rush/pnpm-lock.yaml` records `3.2.0(graphql@16.13.1)`, the same as `common/temp/pnpm-lock.yaml` and `node_modules`.

## Why it happens

pnpm 12 resolves peer dependencies again during an install. `17.0.0-alpha.7` does not satisfy the peer range `^17.0.0`, so pnpm 12 picks `graphql@16.13.1`. pnpm 11 kept the existing variant. pnpm 12 writes the new variant to `common/temp/pnpm-lock.yaml`, so pnpm itself stays consistent.

Rush copies `common/temp/pnpm-lock.yaml` back to `common/config/rush/pnpm-lock.yaml` only when Rush's own check finds the committed lockfile out of date. Here the `package.json` files match the lockfile, so Rush skips the copy. The `else` branch in `libraries/rush-lib/src/logic/base/BaseInstallManager.ts` has this comment:

```ts
// TODO: Validate whether the package manager updated it in a nontrivial way
```

`rush install` passes `--no-prefer-frozen-lockfile` to pnpm by default. pnpm 12 then resolves the peers again, and it does not follow the committed lockfile.

## Workarounds

- `rush update --recheck` copies the lockfile that pnpm wrote.
- `"usePnpmFrozenLockfileForRushInstall": true` in `common/config/rush/experiments.json` makes `rush install` pass `--frozen-lockfile`. pnpm 12 then links the variant that the committed lockfile records. `rush update` still leaves the committed lockfile stale.

## Versions

- Rush 5.181.0
- pnpm 11.24.0 and 12.10.1
- Node 22
