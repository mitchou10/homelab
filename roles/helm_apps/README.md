# Rôle `helm_apps`

Installe helm sur le serveur puis déploie chaque entrée de `helm_releases`
(définie dans `inventory/group_vars/k3s_server.yml`) avec `kubernetes.core.helm`.

Variables : `helm_version`, `helm_kubeconfig` (défaut `/etc/rancher/k3s/k3s.yaml`), `helm_releases`.
Champs d'une release : voir [../../docs/04-ajouter-une-application.md](../../docs/04-ajouter-une-application.md).
