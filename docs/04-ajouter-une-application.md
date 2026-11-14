# 4. Ajouter / modifier / supprimer une application

Toutes les apps sont décrites dans **deux** endroits :

1. [inventory/group_vars/k3s_server.yml](../inventory/group_vars/k3s_server.yml) → **quoi** installer (chart, namespace…)
2. `apps/values/<app>.yml` → **comment** la configurer (les « values » Helm)

## Ajouter une app

### Exemple : installer Uptime Kuma

**1. Trouver le chart Helm.** Cherche sur https://artifacthub.io/ (ex. « uptime-kuma »).
Note : le nom du dépôt, son URL, le nom du chart.

**2. Déclarer la release** dans `inventory/group_vars/k3s_server.yml` :

```yaml
helm_releases:
  - name: whoami
    chart: cowboysysop/whoami
    repo_name: cowboysysop
    repo_url: https://cowboysysop.github.io/charts
    namespace: demo
    values_file: whoami.yml
    state: present

  - name: uptime-kuma                       # nom de la release (libre)
    chart: uptime-kuma/uptime-kuma          # <repo_name>/<nom du chart>
    repo_name: uptime-kuma
    repo_url: https://helm.irsigler.cloud
    namespace: monitoring                   # créé automatiquement
    version: "2.x.x"                        # optionnel mais recommandé : fige la version
    values_file: uptime-kuma.yml            # fichier dans apps/values/
    state: present
```

Champs :

| Champ | Obligatoire | Sens |
|---|---|---|
| `name` | oui | nom de la release Helm |
| `chart` | oui | `<repo_name>/<chart>` |
| `repo_name`, `repo_url` | oui | dépôt de charts à ajouter |
| `namespace` | non (`default`) | espace de noms K8s, créé si absent |
| `version` | non | version du chart (sinon la dernière) |
| `values_file` | non | fichier dans `apps/values/` |
| `state` | non (`present`) | `present` ou `absent` |

**3. Créer les values** `apps/values/uptime-kuma.yml`. Pour voir toutes les options d'un chart :

```bash
helm show values uptime-kuma/uptime-kuma     # après "helm repo add"
```

Exemple minimal avec un ingress Traefik :

```yaml
ingress:
  enabled: true
  hosts:
    - host: kuma.homelab.local
      paths: [/]
```

**4. Déployer :**

```bash
source .venv/bin/activate
make apps
```

**5. Accéder :** ajoute `192.168.1.12 kuma.homelab.local` dans le `/etc/hosts` de ton PC
(ou configure un DNS local), puis ouvre http://kuma.homelab.local.

## Modifier une app

Édite `apps/values/<app>.yml` (ou la `version`), puis `make apps`. Helm fait un upgrade.

## Supprimer une app

Passe `state: absent` dans `helm_releases`, puis `make apps`. La release est désinstallée.
Une fois nettoyé, tu peux supprimer l'entrée et le fichier de values.

> Les volumes persistants (PVC) ne sont pas toujours supprimés avec la release. Vérifie avec
> `ssh tour 'sudo k3s kubectl get pvc -A'`.

## Bonnes pratiques

- **Fige les versions** des charts (`version:`) pour des déploiements reproductibles.
- **Pas de mots de passe en clair** dans `apps/values/` : voir [prochaines étapes](08-prochaines-etapes.md) (ansible-vault / sops).
- Un commit git par changement d'app → l'historique raconte l'évolution du homelab.
