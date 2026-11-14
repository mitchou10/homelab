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

## Keycloak : « HTTPS required » sur la console d'admin

Le realm `master` impose HTTPS hors localhost. `make apps` le désactive (`sslRequired=NONE`, `roles/platform/tasks/post.yml`).
À la main : `ssh tour 'sudo k3s kubectl -n keycloak exec statefulset/keycloak-keycloakx -- /opt/keycloak/bin/kcadm.sh ...'`.

## Argo CD : « Log in via Keycloak » échoue / erreur OIDC

- Les noms `keycloak.homelab.local` et `argocd.homelab.local` sont-ils dans le `/etc/hosts` de ton PC ?
- Dans le cluster : `ssh tour 'sudo k3s kubectl run t --rm -i --restart=Never --image=busybox:1.36 -- nslookup keycloak.homelab.local'` doit répondre l'IP de Traefik (`10.43.x.x`), sinon `kubectl -n kube-system rollout restart deploy/coredns` ou relancer `make apps`.
- `kubectl -n argocd logs deploy/argocd-server | grep -i oidc`
- Le secret du client doit être identique des deux côtés : il vient de `.secrets/client_argocd_secret`. Relancer `make apps` resynchronise tout.

## Keycloak : mot de passe de la base refusé après perte de `.secrets/`

Les mots de passe sont régénérés mais Postgres a gardé l'ancien. Soit restaurer `.secrets/` depuis ta sauvegarde, soit supprimer le volume Postgres (perte des données Keycloak) : `kubectl -n keycloak delete sts keycloak-postgres pvc/data-keycloak-postgres-0`, puis `make apps`.

## OpenBao : « Vault is sealed » / apps qui ne lisent plus les secrets

Normal après un redémarrage : `make unseal`. Si le fichier `.secrets/openbao_init.json` est introuvable, restaure-le depuis ta sauvegarde (sans lui les données sont perdues).

## OpenBao : connexion OIDC refusée (« redirect_uri » invalide)

L'URL de callback doit être déclarée dans le client Keycloak `openbao` (`keycloak_clients` dans `inventory/group_vars/all.yml`) **et** dans le rôle OIDC (`configure.sh.j2`). Pour modifier un client existant : console admin Keycloak (le playbook ne met à jour que la création).

## Une appli ne joint pas `keycloak.homelab.local` : « Name or service not known » (alors qu'Argo CD y arrive)

**Cause :** la première version du DNS interne utilisait un `rewrite` CoreDNS vers le service Traefik. La réponse portait alors le nom `traefik.kube-system…`
et non le nom demandé : les clients **Go** l'acceptent (Argo CD, OpenBao), pas le résolveur **glibc** (Python, curl, Node…), qui l'ignore.
Symptôme vu : connexion SSO refusée avec « Login failed » côté application, alors que Keycloak accepte le mot de passe.
**Solution (déjà dans le rôle `platform`) :** une zone `homelab.local` avec un vrai enregistrement A vers l'IP du service Traefik (+ réponse vide pour l'IPv6).
Test depuis un pod : `python -c "import socket;print(socket.getaddrinfo('keycloak.homelab.local',80))"`.
Si l'IP du service Traefik change (réinstallation), relancer `make apps` met la zone à jour.
