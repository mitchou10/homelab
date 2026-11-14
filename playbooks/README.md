# playbooks/

| Playbook | Fait quoi | Raccourci |
|---|---|---|
| `site.yml` | tout : `k3s.yml` puis `apps.yml` | `make all` |
| `k3s.yml` | prépare l'OS + installe k3s + récupère le kubeconfig | `make k3s` |
| `apps.yml` | installe helm + déploie les releases | `make apps` |

Simulation sans rien modifier : `make check`. Détail : [../docs/03-deployer-le-cluster.md](../docs/03-deployer-le-cluster.md).
