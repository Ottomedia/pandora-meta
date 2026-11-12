# Meta repository del progetto Pandora / BcOk

`pandora` è il nome dell'insieme dei software, plugin, ecc sviluppati da Ottomedia come CRM della rete Ufficiarredati.it

L'installazione operativa di `pandora` è [BcOk.it](https://bcok.it)

In questo repository salviamo la documentazione (work in progress) per gli sviluppatori (nel Wiki), script di aiuto, riferimenti, liste "promemoria" ecc.

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

* usare un Personal Access Token **classic** con scope `repo`
* non usare i token fine-grained: con `plugin-update-checker` v5.6, che si autentica sempre con Basic auth, non funzionano (provato)
* definire il token solo sui siti che ricevono gli aggiornamenti, non in locale, dove il codice si aggiorna con git

Lo scope `repo` dà accesso completo ai repository privati: il token va trattato come una credenziale critica.

Configurazione consigliata:

```php
add_action( 'plugins_loaded', function () {
    if ( ! defined( 'GITHUB_UPDATER_AUTH_TOKEN' ) ) {
        // In locale il codice si aggiorna con git: il token non serve e l'assenza non va segnalata.
        if ( 'local' !== wp_get_environment_type() ) {
            error_log( 'GITHUB_UPDATER_AUTH_TOKEN not defined in ' . __FILE__ . '. GitHub updates will not work.' );
        }
        return;
    }

    $updateChecker = PucFactory::buildUpdateChecker(
        'https://github.com/Ottomedia/nome-repository',
        __FILE__,
        'nome-plugin'
    );
    $updateChecker->setAuthentication( GITHUB_UPDATER_AUTH_TOKEN );
}, 0 );
```

e nel `wp-config.php`:

```php
define( 'GITHUB_UPDATER_AUTH_TOKEN', 'ghp_xxxxx' );
```

---

### Supporto per formati changelog multipli

Il workflow `auto-tag-version` supporta **due formati** per le release notes:

#### 1. CHANGELOG.md (formato standard)

```markdown
## [1.2.0] - 2026-01-15

- Nuova feature XYZ
- Fix bug ABC
```

Il parser estrae la sezione corrispondente alla versione (es. `## [1.2.0]`).

#### 2. readme.txt (formato WordPress)

```text
== Changelog ==

= 1.2.0 - 2026-01-15 =
* Nuova feature XYZ
* Fix bug ABC

= 1.1.0 - 2025-12-01 =
* Versione precedente
```

Il parser estrae la **prima entry** dalla sezione `== Changelog ==`.

**Ordine di priorità:**
1. Se esiste `CHANGELOG.md` → lo usa
2. Se esiste `readme.txt` → lo usa  
3. Altrimenti → release notes vuote

---

### Triggerare workflow multipli: configurazione PAT

**Problema**: GitHub blocca i workflow successivi quando il tag viene creato con il `GITHUB_TOKEN` default (protezione anti-loop).

**Soluzione**: Usare un **Personal Access Token (PAT)** per triggerare `release-plugin.yml`, `deploy.yml`, ecc.

#### Passo 1: Creare il PAT

1. GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)**
2. Generate new token (classic)
3. Scopes necessari:
   - ✅ `repo` (Full control of private repositories)
   - ✅ `workflow` (Update GitHub Action workflows)
4. Salva il token generato

#### Passo 2: Aggiungere il secret al repository

1. Repository → Settings → Secrets and variables → Actions
2. New repository secret:
   - Name: `WORKFLOW_TOKEN`
   - Value: `ghp_xxxxxxxxxxxxx` (il PAT creato)

#### Passo 3: Usare il token nel workflow

```yaml
name: Auto Tag Version

on:
  push:
    branches:
      - master  # o main

permissions:
  contents: write

jobs:
  auto-tag-version:
    uses: Ottomedia/pandora-meta/.github/workflows/auto-tag-version.yml@main
    with:
      plugin_file: wp-bcok-booking-carnet.php  # opzionale
    secrets:
      github-token: ${{ secrets.WORKFLOW_TOKEN }}
```

**Nota**: Se NON fornisci il secret `github-token`, il workflow usa il `GITHUB_TOKEN` default (comportamento backward-compatible). I workflow successivi **non** verranno triggerati.

## Script: matrice degli accessi

`tools/matrice-accessi.sh` verifica, **senza credenziali**, che ogni punto di ingresso di BcOk risponda come previsto a un visitatore non loggato: frontend, export, feed, vecchi URL di Ultimate Member, pagine di login, wp-admin, REST API (chiusa, tranne le route aperte di proposito), feed iCal, XML-RPC, file serviti dal web server. Contesto: issue #11 e #12.

```bash
tools/matrice-accessi.sh --pausa 0 https://bcok.local   # sito locale
tools/matrice-accessi.sh https://bcok.it                 # produzione, 1 secondo tra le richieste
```

- Fa solo richieste in lettura (più una POST innocua su `xmlrpc.php`) ed esce con 1 se almeno un controllo fallisce.
- In produzione Wordfence può bloccare l'IP che fa molte richieste di fila: lasciare la pausa predefinita e, se serve, mettere in whitelist temporanea il proprio IP.
- Le route REST aperte ai non loggati sono elencate in testa allo script (`ROUTE_REST_APERTE`): vanno tenute allineate a disable-json-api in produzione.
- Va lanciato dopo ogni rilascio che tocca l'accesso, dopo ogni passo della rimozione di Ultimate Member e dopo aggiornamenti importanti del core, di Wordfence o di disable-json-api.
