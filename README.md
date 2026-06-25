# Meta repository del progetto Pandora / BcOk

`pandora` è il nome dell'insieme dei software, plugin, ecc sviluppati da Ottomedia come CRM della rete Ufficiarredati.it

L'installazione operativa di `pandora` è [BcOk.it](https://bcok.it)

In questo repository salviamo la documentazione (work in progress) per gli sviluppatori (nel Wiki), script di aiuto, riferimenti, liste "promeoria" ecc.

I singoli plugin che compongono `pandora` e `BcOk` sono repository privati

## Workflow condiviso per Auto Tag

In `.github/workflows/auto-tag-version.yml` è presente un workflow condiviso tra tutti i plugin e temi di `pandora` per la gestione automatica dei tag di versione.

Il workflow crea un tag di versione ogni volta che individua un aggiornamento di versione nel file del plugin.

In particolare:

- legge la versione dal file principale del plugin
- crea automaticamente il tag Git
- crea automaticamente la GitHub Release
- legge le release notes da CHANGELOG.md

### Utilizzo del workflow

#### Caso standard

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

#### Caso con nome file personalizzato

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

#### Versionamento consigliato

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

### Convenzione CHANGELOG.md

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

### Requisiti repository plugin

Ogni repository deve avere:

* file plugin con header `Version:`
* `CHANGELOG.md`
* permesso GitHub Actions:

```yaml
permissions:
  contents: write
```

---

### Plugin Update Checker e repository privati

Per plugin privati GitHub:

* usare Fine-grained Personal Access Token
* accesso limitato al repository
* permesso:

  * Contents → Read-only

Configurazione consigliata:

```php
$updateChecker->setAuthentication(
    defined('GITHUB_UPDATER_AUTH_TOKEN') ? GITHUB_UPDATER_AUTH_TOKEN : ''
);
```

e nel `wp-config.php`:

```php
define('GITHUB_UPDATER_AUTH_TOKEN', 'github_pat_xxxxx');
```