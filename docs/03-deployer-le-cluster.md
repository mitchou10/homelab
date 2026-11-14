# 3. Déployer le cluster

Prérequis : [poste de contrôle](01-poste-de-controle.md) et [serveur](02-preparer-le-serveur.md) prêts,
`make ping` répond `pong`.

## Tout déployer d'un coup

```bash
source .venv/bin/activate
make all          # = ansible-playbook playbooks/site.yml
```

Durée : 2 à 5 minutes selon ta connexion. À la fin, le `PLAY RECAP` doit afficher `failed=0`.

## Ce qui se passe, étape par étape

`site.yml` enchaîne deux playbooks.

### Playbook `k3s.yml` (rôles `common` puis `k3s`)

**Rôle `common`** — [roles/common/tasks/main.yml](../roles/common/tasks/main.yml)
1. Installe les paquets : `curl`, `ca-certificates`, `python3-pip`, `python3-kubernetes`, `python3-yaml`, `git`
   (les paquets Python sont requis pour que le module Helm d'Ansible fonctionne sur la cible).
2. Désactive le **swap** (`swapoff -a`) et le retire de `/etc/fstab`. Kubernetes n'aime pas le swap.

**Rôle `k3s`** — [roles/k3s/tasks/main.yml](../roles/k3s/tasks/main.yml)
1. Regarde si `/usr/local/bin/k3s` existe déjà (sinon on saute l'installation → idempotent).
2. Télécharge le script officiel `https://get.k3s.io`.
3. Lance l'installation en mode `server` avec les options de `k3s_extra_server_args`.
4. S'assure que le service `k3s` tourne et démarre au boot.
5. Attend que le nœud soit `Ready`.
6. **Copie le kubeconfig** du serveur (`/etc/rancher/k3s/k3s.yaml`) vers `kubeconfig/config` sur ton PC.
7. Remplace `127.0.0.1` par l'IP du serveur dans ce fichier local (sinon `kubectl` viserait ton PC).

### Playbook `apps.yml` (rôle `helm_apps`)

[roles/helm_apps/tasks/main.yml](../roles/helm_apps/tasks/main.yml)
1. Installe le binaire `helm` sur le serveur (si absent).
2. Ajoute les dépôts de charts nécessaires (ex. `cowboysysop`).
3. Copie les fichiers `apps/values/*.yml` sur le serveur (dans `/tmp`).
4. Pour chaque entrée de `helm_releases` : `helm upgrade --install` (crée le namespace si besoin, attend que ce soit prêt).

## Lancer seulement une partie

```bash
make k3s       # seulement le cluster
make apps      # seulement les applications (le plus utilisé au quotidien)
make check     # simulation (--check --diff), ne modifie rien
```

> `make check` sur une machine vierge échoue sur « S'assurer que k3s tourne » : c'est normal,
> le service n'existe pas encore en simulation.

## Variables importantes

[inventory/group_vars/all.yml](../inventory/group_vars/all.yml) :

| Variable | Rôle | Défaut |
|---|---|---|
| `k3s_version` | version de k3s (vide = dernière stable) | `""` |
| `k3s_extra_server_args` | options passées à `k3s server` | `--write-kubeconfig-mode 644` |
| `k3s_local_kubeconfig` | où stocker le kubeconfig sur ton PC | `kubeconfig/config` |
| `helm_version` | version de helm installée | `v3.16.3` |

Exemple pour **désactiver Traefik** et utiliser un autre ingress :
`k3s_extra_server_args: "--write-kubeconfig-mode 644 --disable traefik"`.

> Attention : `k3s_version` vide installe la *dernière* version à la date du déploiement.
> Pour de la reproductibilité, fige-la (ex. `v1.37.2+k3s1`).

## Vérifier que ça marche

```bash
ssh tour 'sudo k3s kubectl get nodes'            # STATUS = Ready
ssh tour 'sudo k3s kubectl get pods -A'          # tout Running
curl -H 'Host: whoami.homelab.local' http://192.168.1.12    # doit répondre (HTTP 200)
```

Au premier démarrage, certains pods restent `ContainerCreating` ~1 minute (téléchargement des images) :
c'est normal, attends.

## Tout désinstaller (repartir de zéro)

Sur le serveur :

```bash
sudo /usr/local/bin/k3s-uninstall.sh     # supprime k3s, les pods et les données locales
```

Puis relance `make all` pour recréer.
