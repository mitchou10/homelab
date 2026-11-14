# inventory/

Décrit **quelles machines** Ansible pilote et **avec quelles variables**.

- `hosts.yml` — la liste des machines : nom, IP (`ansible_host`), utilisateur SSH, clé SSH.
  Le groupe `k3s_server` contient le nœud k3s.
- `group_vars/all.yml` — variables pour toutes les machines (version k3s, options k3s, version helm, chemin du kubeconfig local).
- `group_vars/k3s_server.yml` — **la liste des applications** (`helm_releases`). C'est ce fichier qu'on édite pour ajouter une app.

Ajouter une machine : un nouveau bloc sous `hosts:` dans `hosts.yml`.
Tutoriels : [../docs/02-preparer-le-serveur.md](../docs/02-preparer-le-serveur.md) et [../docs/04-ajouter-une-application.md](../docs/04-ajouter-une-application.md).
