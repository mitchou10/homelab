# Rôle `k3s`

Installe k3s en mode `server` (mono-nœud) et récupère le kubeconfig.

Variables (`defaults/main.yml`, surchargées dans `inventory/group_vars/all.yml`) :
- `k3s_version` — version (vide = dernière stable)
- `k3s_extra_server_args` — options de `k3s server` (ex. `--disable traefik`)
- `k3s_local_kubeconfig` — où écrire le kubeconfig sur le PC

Idempotent : si `/usr/local/bin/k3s` existe, l'installation est sautée.
Pour **changer de version**, il faudra relancer le script d'install (non géré pour l'instant, voir docs/08).
Désinstaller : `sudo /usr/local/bin/k3s-uninstall.sh` sur le serveur.
