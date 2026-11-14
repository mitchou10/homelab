# 10. Commits et releases automatiques

Les versions du homelab (tags + GitHub Releases + `CHANGELOG.md`) sont générées automatiquement par
**release-please**, à partir des messages de commit. On réutilise les workflows de ton dépôt
[`Mitchou10/github-workflow`](https://github.com/Mitchou10/github-workflow) (appelés en `@v0`).

## Écrire les commits : Conventional Commits

Format : `type(portée): description` (1re ligne ≤ 100 caractères).

| Type | Quand | Effet sur la version |
|---|---|---|
| `feat` | nouvelle fonctionnalité (rôle, app, playbook…) | **mineure** (0.1.0 → 0.2.0) |
| `fix` | correction de bug | patch (0.1.0 → 0.1.1) |
| `perf`, `refactor`, `revert`, `build` | amélioration, refonte, dépendances | patch |
| `docs`, `chore`, `ci`, `test`, `style` | doc, maintenance, CI | pas de release (cachés du changelog) |
| `feat!:` ou pied de page `BREAKING CHANGE:` | changement incompatible | majeure |

Exemples : `feat(gpu): add nvidia_cuda role`, `fix(k3s): wait for node ready`, `docs: explain sudo setup`.

Un commit = un changement logique (« par morceau »). Pas besoin de mentionner d'outil dans le message.

## Comment ça marche

1. Tu pousses sur `main` → le workflow [release.yml](../.github/workflows/release.yml) tourne.
2. release-please ouvre (ou met à jour) une **PR « chore(main): release X.Y.Z »** avec le changelog.
3. **Tu merges cette PR** quand tu veux publier → création du tag `vX.Y.Z` et de la GitHub Release.
4. Sur les PR, [lint-commits.yml](../.github/workflows/lint-commits.yml) vérifie le format des commits
   (et du **titre de la PR**, car on squash-merge : le titre devient le commit).

Configuration : [release-please-config.json](../release-please-config.json) (sections du changelog) et
[.release-please-manifest.json](../.release-please-manifest.json) (version courante, géré automatiquement : ne pas l'éditer).

## À faire une seule fois sur GitHub

Dépôt → Settings → Actions → General → **Workflow permissions** :
- « Read and write permissions »
- cocher « **Allow GitHub Actions to create and approve pull requests** » (sinon release-please ne peut pas ouvrir sa PR)

> Limite connue : la PR de release ouverte avec le `GITHUB_TOKEN` par défaut ne déclenche pas d'autres workflows.
> Le workflow partagé accepte une GitHub App (`APP_CLIENT_ID` / `APP_PRIVATE_KEY`) ou un PAT (`GH_PAT`) si tu en as besoin.

## Mettre à jour la version des workflows

Les appels utilisent `@v0` (dernière 0.x de `github-workflow`). Pour figer : `@v0.4.1`.
