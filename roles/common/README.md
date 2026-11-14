# Rôle `common`

Prépare l'OS (Debian/Ubuntu) avant k3s.

- Installe : `curl`, `ca-certificates`, `python3-pip`, `python3-kubernetes`, `python3-yaml`, `git`
  (les paquets Python servent au module Helm d'Ansible).
- Désactive le swap (runtime + `/etc/fstab`), requis par Kubernetes.

Pas de variables. Fichier : `tasks/main.yml`.
