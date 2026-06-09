# Migrazione workflow GitHub condiviso per plugin WordPress

## Obiettivo

Centralizzare il workflow GitHub che:

* legge la versione dal file principale del plugin
* crea automaticamente il tag Git
* crea automaticamente la GitHub Release
* legge le release notes da `CHANGELOG.md`

In modo da:

* evitare duplicazione del workflow in tutti i repository
* aggiornare la logica in un solo punto
* mantenere comportamento coerente in tutti i plugin del CRM

---

# Repository condiviso

Repository scelto:

```text
ottomedia/pandora-meta
```

Workflow condiviso:

```text
.github/workflows/auto-tag-version.yml
```

---

# Workflow condiviso

## File

Creare:

```text
.github/workflows/auto-tag-version.yml
```

## Contenuto

```yaml
name: Auto Tag Version Shared

on:
  workflow_call:
    inputs:
      plugin_file:
        required: false
        type: string

permissions:
  contents: write

jobs:
  tag-version:
    name: Create tag and release from plugin version
    runs-on: ubuntu-latest

    steps:
      - name: Check out repository
        uses: actions/checkout@v5
        with:
          fetch-depth: 0

      - name: Determine plugin file
        id: determine_plugin_file
        env:
          INPUT_PLUGIN_FILE: ${{ inputs.plugin_file }}
        run: |
          set -euo pipefail

          if [ -n "${INPUT_PLUGIN_FILE}" ]; then
            PLUGIN_FILE="${INPUT_PLUGIN_FILE}"
          else
            PLUGIN_FILE="${GITHUB_REPOSITORY#*/}.php"
          fi

          echo "plugin_file=${PLUGIN_FILE}" >> "${GITHUB_OUTPUT}"

      - name: Create version tag when plugin version changes
        id: tag_version
        env:
          PLUGIN_FILE: ${{ steps.determine_plugin_file.outputs.plugin_file }}
        run: |
          set -euo pipefail

          echo "file to check is ${PLUGIN_FILE}"

          revcount=$(git rev-list --all --count)
          if [ "${revcount}" -le 1 ]; then
            echo "History too short"
            exit 0
          fi

          histdiff=$(git diff --name-only HEAD HEAD~1 | grep -Fx "${PLUGIN_FILE}" || true)
          if [ "${histdiff}" != "${PLUGIN_FILE}" ]; then
            echo "${PLUGIN_FILE} not changed"
            exit 0
          fi

          version=$(grep "Version:" "${PLUGIN_FILE}" | cut -d ':' -f 2 | xargs)

          if [ -z "${version}" ]; then
            echo "Unable to detect plugin version"
            exit 1
          fi

          echo "version=${version}" >> "${GITHUB_OUTPUT}"

          if git rev-parse -q --verify "refs/tags/${version}" >/dev/null 2>&1; then
            echo "Tag already exists; no action taken"
            echo "created=false" >> "${GITHUB_OUTPUT}"
            exit 0
          fi

          echo "Creating new tag ${version}"

          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

          changeref=$(git rev-parse HEAD)

          git tag -a "${version}" "${changeref}" -m "Release version ${version}"

          git push origin "refs/tags/${version}"

          echo "created=true" >> "${GITHUB_OUTPUT}"

      - name: Prepare release notes from changelog
        if: steps.tag_version.outputs.created == 'true'
        env:
          VERSION: ${{ steps.tag_version.outputs.version }}
        run: |
          set -euo pipefail

          awk -v v="${VERSION}" '
            index($0, "## [" v "]") == 1 { found = 1; next }
            found && /^## \[/ { exit }
            found { print }
          ' CHANGELOG.md > RELEASE_NOTES.md

          if ! grep -q "[^[:space:]]" RELEASE_NOTES.md; then
            echo "Nessuna nota release trovata in CHANGELOG.md per la versione ${VERSION}." > RELEASE_NOTES.md
          fi

      - name: Create GitHub release
        if: steps.tag_version.outputs.created == 'true'
        env:
          GH_TOKEN: ${{ github.token }}
          VERSION: ${{ steps.tag_version.outputs.version }}
        run: |
          set -euo pipefail

          if gh release view "${VERSION}" >/dev/null 2>&1; then
            echo "Release ${VERSION} already exists; no action taken"
            exit 0
          fi

          gh release create "${VERSION}" \
            --title "v${VERSION}" \
            --notes-file RELEASE_NOTES.md
```

---

# Workflow minimale nei repository plugin

## Caso standard

Se il file principale del plugin coincide con il nome del repository:

Repository:

```text
wordattach-for-cf7
```

File plugin:

```text
wordattach-for-cf7.php
```

Workflow:

```yaml
name: Auto Tag Version

on:
  push:
    branches:
      - main

permissions:
  contents: write

jobs:
  auto-tag-version:
    uses: ottomedia/pandora-meta/.github/workflows/auto-tag-version.yml@main
```

---

# Caso con nome file personalizzato

Esempio:

Repository:

```text
crm-module
```

File plugin:

```text
crm-main-plugin.php
```

Workflow:

```yaml
name: Auto Tag Version

on:
  push:
    branches:
      - main

permissions:
  contents: write

jobs:
  auto-tag-version:
    uses: ottomedia/pandora-meta/.github/workflows/auto-tag-version.yml@main

    with:
      plugin_file: crm-main-plugin.php
```

---

# Versionamento consigliato

NON usare `@main` in produzione a lungo termine.

Meglio:

```yaml
uses: ottomedia/pandora-meta/.github/workflows/auto-tag-version.yml@v1
```

Procedura consigliata:

1. sviluppo su `main`
2. test su alcuni plugin
3. creazione tag:

```bash
git tag v1
git push origin v1
```

4. i plugin useranno `@v1`

---

# Convenzione CHANGELOG.md

Il parser release legge sezioni tipo:

```markdown
## [1.2.0]

- nuova feature
- fix bug
```

Formato richiesto:

```markdown
## [VERSIONE]
```

Esempio valido:

```markdown
## [2.5.1]
```

---

# Requisiti repository plugin

Ogni repository deve avere:

* file plugin con header `Version:`
* `CHANGELOG.md`
* permesso GitHub Actions:

```yaml
permissions:
  contents: write
```

---

# Possibili miglioramenti futuri

Il repository `pandora-meta` potrà contenere anche:

* workflow build ZIP WordPress
* PHPStan
* PHPCS
* PHPUnit
* deploy staging
* deploy produzione
* validazione changelog
* issue templates condivisi
* documentazione tecnica
* convenzioni di sviluppo CRM

---

# Note sicurezza

NON inserire nel workflow condiviso:

* token hardcoded
* secrets
* URL privati
* configurazioni infrastrutturali sensibili

I secrets devono rimanere nei singoli repository o nell’organizzazione GitHub.

---

# Plugin Update Checker e repository privati

Per plugin privati GitHub:

* usare Fine-grained Personal Access Token
* accesso limitato al repository
* permesso:

  * Contents → Read-only

Configurazione consigliata:

```php
$updateChecker->setAuthentication(
    defined('OTTO_GH_TOKEN') ? OTTO_GH_TOKEN : ''
);
```

e nel `wp-config.php`:

```php
define('OTTO_GH_TOKEN', 'github_pat_xxxxx');
```
