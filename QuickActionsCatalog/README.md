# MenuCue Quick Actions Catalog

Official and community-style package index for MenuCue’s **Quick Action Repo Manager**.

## Layout

```text
QuickActionsCatalog/
  index.json
  packages/
    <slug>/
      package.json
      README.md
      workflow.zip          # zip of the .workflow bundle (checksum target)
      <Name>.workflow/     # source tree (optional alongside zip)
```

## `index.json`

| Field | Description |
|-------|-------------|
| `schemaVersion` | Currently `1` |
| `name` | Human-readable catalog name |
| `updatedAt` | ISO date string |
| `packages[]` | Summaries with `id`, `name`, `summary`, `version`, `tags`, `path` |

`path` is relative to the catalog root (the directory that contains `index.json`).

## `package.json`

| Field | Description |
|-------|-------------|
| `id` | Stable unique id (reverse-DNS recommended) |
| `name` | Display name (should match the Services menu title) |
| `version` | Semver string |
| `author` | Author or org |
| `readme` | Relative Markdown file |
| `workflow` | Relative `.workflow` bundle name |
| `workflowZip` | Relative zip of that bundle |
| `dependencies.brew` | Homebrew formula names to install (with user confirmation) |
| `minMacOS` | Minimum macOS version |
| `checksum` | `sha256:<hex>` of `workflowZip` |

## Authoring a package

### Via Quick Action (recommended)

1. Install the packager once: copy [`Package Quick Action.workflow`](../Package%20Quick%20Action.workflow) into `~/Library/Services/` (or open it in Automator and save as a Quick Action).
2. Build your Quick Action in Automator and save it as a `.workflow`.
3. In Finder, select that `.workflow` → right-click → **Quick Actions** → **Package Quick Action**.
4. Choose your `QuickActionsCatalog` folder (the directory that contains `index.json`).
5. Fill in the prompts (name, id, version, author, summary, tags, brew deps, etc.).

The action copies the workflow into `packages/<slug>/`, creates `workflow.zip` + checksum, writes `package.json` and `README.md`, and upserts the entry in `index.json`.

### Manually

1. Build a Quick Action in Automator and save it as a `.workflow`.
2. Place it under `packages/<slug>/`.
3. Zip it (keep the `.workflow` as the zip root entry):

```bash
ditto -c -k --sequesterRsrc --keepParent "My Action.workflow" workflow.zip
shasum -a 256 workflow.zip
```

4. Write `package.json` with the checksum as `sha256:<hex>`.
5. Write `README.md` with **Dependencies** (include `brew install …` when needed) and **How to use**.
6. Add a summary entry to `index.json`.

## Pointing MenuCue at a community catalog

In MenuCue → **Quick Action Repo Manager…** → **Add Repository URL…**, paste the HTTPS URL of your `index.json` (for example a raw GitHub URL).

Only HTTPS indexes are accepted.
