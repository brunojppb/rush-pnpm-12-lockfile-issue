# Rush with pnpm 12: the committed lockfile does not match node_modules

This repository reproduces a Rush bug with pnpm 12.

- Issue: https://github.com/microsoft/rushstack/issues/6117
- Fix (draft): the `brunojppb/6117/pnpm12-lockfile-sync` branch on https://github.com/brunojppb/rushstack. See [Test the fix](#test-the-fix).

This text uses two names for two lockfiles:

- The **committed lockfile** is `common/config/rush/pnpm-lock.yaml`. You commit this file to git.
- The **temp lockfile** is `common/temp/pnpm-lock.yaml`. pnpm writes this file during an install.

## The problem

With pnpm 12, `rush update` can keep the old committed lockfile. pnpm writes a different temp lockfile and links different packages in `node_modules`. Rush does not copy the temp lockfile to the committed lockfile.

`rush install` in a new clone has the same problem. It links packages that the committed lockfile does not record.

## Run the reproduction

You need Node 24. The `.nvmrc` file pins it.

```bash
./repro.sh
```

You do not need a global `rush` command. The script runs `common/scripts/install-run-rush.js`. That script downloads Rush 5.181.0 and the pnpm versions that the steps use.

The script starts from the same state each time. It exits with code 1 when it finds the bug.

## The repository

The repository has three projects:

- `lib` depends on `graphql@17.0.0-alpha.7`.
- `legacy` depends on `graphql@16.13.1`.
- `app` depends on `lib` and on `@graphql-typed-document-node/core@3.2.0`.

`@graphql-typed-document-node/core` has a peer dependency on `graphql`. The lockfile records the `graphql` version that pnpm picks for this peer. This text calls that record the **peer variant**.

## The steps

1. `app` depends on `graphql@17.0.0-alpha.7`. The script runs `rush update` with pnpm 11.24.0.
2. The script removes `graphql` from `app`. It runs `rush update` with pnpm 11.24.0 again.
3. The script sets `pnpmVersion` to 12.10.1. It runs `rush update`.
4. The script runs `rush purge`, then `rush install`. This step does the same work as a new clone.

## The result

```
== 3. Set pnpm to 12.10.1, then run rush update
temp lockfile:      graphql@16.13.1
committed lockfile: graphql@17.0.0-alpha.7
node_modules:       graphql@16.13.1
committed lockfile changed: no

== 4. Run rush purge, then rush install with pnpm 12.10.1
committed lockfile: graphql@17.0.0-alpha.7
node_modules:       graphql@16.13.1

== Result
BUG: the committed lockfile records graphql@17.0.0-alpha.7, but node_modules links graphql@16.13.1.
```

## The expected result

After step 3, the committed lockfile records `graphql@16.13.1`. The temp lockfile and `node_modules` record the same version.

## The cause

After step 2, the peer variant is `graphql@17.0.0-alpha.7`. This version does not satisfy the peer range `^17.0.0`.

`rush update` gives pnpm the `--no-prefer-frozen-lockfile` option. pnpm then resolves the dependencies again, and starts from the lockfile. pnpm 11 keeps the peer variant that the lockfile records. pnpm 12 recomputes the peer variant and picks `graphql@16.13.1`. pnpm 12 writes this version to the temp lockfile, so the temp lockfile and `node_modules` match.

These runs show the difference. Each run starts from the lockfile of step 2.

| Run | Peer variant in the temp lockfile |
| --- | --- |
| pnpm 11.24.0 and 11.28.5, `rush update` | `graphql@17.0.0-alpha.7` |
| pnpm 12.4.0 to 12.10.1, `rush update` | `graphql@16.13.1` |
| pnpm 12.10.1, `--prefer-frozen-lockfile` | `graphql@17.0.0-alpha.7` |
| pnpm 11.24.0 and 12.10.1, no lockfile | `graphql@16.13.1` |

pnpm 12.0.0 to 12.3.0 do not accept the `--no-prefer-frozen-lockfile` option, so `rush update` fails with them.

Rush copies the temp lockfile to the committed lockfile only when its own check finds a change. Here, the `package.json` files did not change, so Rush does not copy the file. `libraries/rush-lib/src/logic/base/BaseInstallManager.ts` has this comment in the branch that skips the copy:

```ts
// TODO: Validate whether the package manager updated it in a nontrivial way
```

`rush install` has a related problem. By default, it also gives pnpm the `--no-prefer-frozen-lockfile` option. pnpm 12 then recomputes the peer variants and does not follow the committed lockfile.

## Workarounds

- Run `rush update --recheck`. Rush then copies the temp lockfile to the committed lockfile.
- Set `"usePnpmFrozenLockfileForRushInstall": true` in `common/config/rush/experiments.json`. `rush install` then gives pnpm the `--frozen-lockfile` option, and pnpm follows the committed lockfile. This setting does not change `rush update`.

## Test the fix

The `brunojppb/6117/pnpm12-lockfile-sync` branch on https://github.com/brunojppb/rushstack has a fix. With the fix, `rush update` copies the temp lockfile to the committed lockfile when pnpm 12 changes it.

You need Node 22 to build Rush, because the `rushstack` repository accepts only Node 22. You need Node 24 to run `repro.sh`.

1. Clone the fork and check out the branch:

   ```bash
   git clone https://github.com/brunojppb/rushstack.git
   cd rushstack
   git checkout brunojppb/6117/pnpm12-lockfile-sync
   ```

2. With Node 22, install the dependencies and build Rush:

   ```bash
   node common/scripts/install-run-rush.js install
   node common/scripts/install-run-rush.js build --to @microsoft/rush
   ```

3. In this repository, with Node 24, set `REPRO_RUSH_START` to the start script of that build. Then run the script:

   ```bash
   REPRO_RUSH_START=/path/to/rushstack/apps/rush/lib-commonjs/start-dev.js ./repro.sh
   ```

The expected result:

```
== 3. Set pnpm to 12.10.1, then run rush update
temp lockfile:      graphql@16.13.1
committed lockfile: graphql@16.13.1
node_modules:       graphql@16.13.1
committed lockfile changed: yes

== 4. Run rush purge, then rush install with pnpm 12.10.1
committed lockfile: graphql@16.13.1
node_modules:       graphql@16.13.1

== Result
OK: the committed lockfile matches node_modules.
```

The script exits with code 0.

## Versions

- Rush 5.181.0
- pnpm 11.24.0 and 12.10.1
- Node 24.21.0
