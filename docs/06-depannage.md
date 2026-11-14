# 6. Dépannage — problèmes rencontrés et solutions

Chaque section = un vrai problème vu pendant la mise en place.

## `sudo: il est nécessaire de saisir un mot de passe` / Ansible bloque sur sudo

**Cause :** l'utilisateur doit taper son mot de passe pour sudo.
**Solution :** sudo sans mot de passe, voir [02-preparer-le-serveur.md](02-preparer-le-serveur.md) étape C,
ou lancer Ansible avec `-K`.

## `ensurepip is not available ... apt install python3.14-venv`

**Cause :** `python3 -m venv` ne marche pas sur Ubuntu sans le paquet `python3-venv`.
**Solution adoptée :** utiliser `uv` (`uv venv .venv`), qui n'en a pas besoin.
Alternative : `sudo apt install python3-venv`.

## `The 'community.general.yaml' callback plugin has been removed`

**Cause :** `ansible.cfg` utilisait `stdout_callback = yaml`, supprimé des versions récentes.
**Solution (déjà appliquée) :** dans `ansible.cfg` :
```ini
stdout_callback = ansible.builtin.default
result_format = yaml
```

## `Could not find the requested service k3s: host` (avec `--check`)

**Cause :** en simulation, k3s n'est pas vraiment installé, donc le service n'existe pas.
**Solution :** normal, ignorer. Lancer sans `--check` pour de vrai.

## `make: ansible-galaxy: commande introuvable`

**Cause :** l'environnement virtuel n'est pas activé.
**Solution :** `source .venv/bin/activate` (à refaire dans chaque nouveau terminal).

## `kubectl: commande introuvable`

**Cause :** kubectl n'est pas installé sur le PC.
**Solution :** `ssh tour 'sudo k3s kubectl ...'` ou installer kubectl ([05](05-utiliser-le-cluster.md)).

## Les pods restent en `ContainerCreating`

**Cause :** premier démarrage, téléchargement des images (surtout Traefik, CoreDNS).
**Solution :** attendre 1 à 3 minutes. Si ça dure :
`kubectl describe pod <pod> -n <ns>` et regarder les `Events` en bas (problème réseau/DNS ?).

## `curl` vers une appli : `404 page not found`

**Cause :** Traefik répond mais aucun Ingress ne correspond au `Host`.
**Solution :** vérifier `kubectl get ingress -A` et que l'en-tête `Host` correspond exactement
(`curl -H 'Host: ...'`).

## `curl` : connexion refusée / timeout

**Causes possibles :** pare-feu (`sudo ufw status`), Traefik pas prêt, mauvaise IP.
**Vérifier :** `kubectl get pods -n kube-system` (traefik + svclb-traefik en `Running`).
Si `ufw` est actif : `sudo ufw allow 80,443,6443/tcp`.

## `kubectl` en local : `connection refused` ou certificat invalide

**Causes :** le kubeconfig vise `127.0.0.1` (remplacement raté), ou l'IP du serveur a changé.
**Solution :** vérifier `grep server kubeconfig/config` → doit contenir l'IP du serveur ;
sinon relancer `make k3s`. L'IP du serveur doit être fixe.

## Une release Helm est bloquée (`pending-install`, `failed`)

```bash
ssh tour 'sudo helm --kubeconfig /etc/rancher/k3s/k3s.yaml list -A --all'
ssh tour 'sudo helm --kubeconfig /etc/rancher/k3s/k3s.yaml uninstall <release> -n <ns>'
make apps
```

## Tout casser et recommencer

```bash
ssh tour 'sudo /usr/local/bin/k3s-uninstall.sh'
make all
```

## GPU : le DaemonSet `nvidia-device-plugin` a 0 pod (`DESIRED 0`)

**Cause :** le chart n'installe le plugin que sur les nœuds ayant le label `nvidia.com/gpu.present=true`
(ou ceux labellisés par Node Feature Discovery, absent ici).
**Solution (déjà dans `playbooks/apps.yml`) :** `kubectl label node <noeud> nvidia.com/gpu.present=true`.

## GPU : un pod reste `Pending` ou `nvidia.com/gpu` absent du nœud

- `kubectl get node -o jsonpath='{.items[0].status.allocatable}'` doit contenir `nvidia.com/gpu`.
- Le pod doit avoir `runtimeClassName: nvidia` **et** `limits: nvidia.com/gpu: 1`.
- Un seul pod peut utiliser le GPU à la fois.
- `ssh tour 'sudo grep nvidia /var/lib/rancher/k3s/agent/etc/containerd/config.toml'` doit montrer le runtime ; sinon `sudo systemctl restart k3s`.

## GPU : `nvidia-smi` échoue (`couldn't communicate with the NVIDIA driver`)

Souvent après une mise à jour de noyau : le module n'est pas chargé → `sudo reboot`. Vérifier `dkms status`.
