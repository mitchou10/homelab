# Homelab — k3s + Ansible + Helm

Ce dépôt permet de **reconstruire tout le homelab depuis zéro** : on part d'une machine Linux
(quasi) vide, et en quelques commandes on obtient un cluster Kubernetes (k3s) avec ses applications.

> Philosophie : tout ce qui est installé sur le serveur est décrit ici. Si ce n'est pas dans le dépôt,
> ça n'existe pas. On peut détruire la machine et tout refaire.

## État actuel

| Élément | Valeur |
|---|---|
| Serveur | `tour` (192.168.1.12), Ubuntu 24.04, utilisateur `michou` |
| Kubernetes | k3s, **1 seul nœud** (control-plane + workloads) |
| Ingress | Traefik (fourni par k3s) |
| Déploiement des apps | Helm piloté par Ansible (ArgoCD prévu plus tard) |
| GPU | Quadro P4000, driver 580, CUDA 12.6, exposé à k3s (`nvidia.com/gpu`) |
| SSO | Keycloak (realm `homelab`), connecté à Argo CD |
| GitOps | Argo CD |
| Autoscaling | KEDA (workers sur file Redis, cron, jobs, scale to zero) |
| Secrets | OpenBao (SSO Keycloak) + External Secrets, **à desceller après un redémarrage : `make unseal`** |
| Apps | `whoami` (test), `nvidia-device-plugin` |

## Les docs, dans l'ordre

Lis-les dans cet ordre si tu repars de zéro :

1. [docs/01-poste-de-controle.md](docs/01-poste-de-controle.md) — installer Ansible sur **ton PC** (celui depuis lequel tu pilotes)
2. [docs/02-preparer-le-serveur.md](docs/02-preparer-le-serveur.md) — ce qu'il faut sur la machine cible (SSH, sudo)
3. [docs/03-deployer-le-cluster.md](docs/03-deployer-le-cluster.md) — installer k3s et déployer les apps
4. [docs/04-ajouter-une-application.md](docs/04-ajouter-une-application.md) — le quotidien : ajouter/modifier/supprimer une app
5. [docs/05-utiliser-le-cluster.md](docs/05-utiliser-le-cluster.md) — kubectl, accéder aux apps, commandes utiles
6. [docs/06-depannage.md](docs/06-depannage.md) — les problèmes rencontrés et leurs solutions
7. [docs/07-journal.md](docs/07-journal.md) — historique de tout ce qui a été fait, et pourquoi
8. [docs/08-prochaines-etapes.md](docs/08-prochaines-etapes.md) — ArgoCD, secrets, sauvegardes, etc.
9. [docs/09-gpu-cuda.md](docs/09-gpu-cuda.md) — driver NVIDIA, CUDA et GPU dans k3s
10. [docs/10-releases-et-commits.md](docs/10-releases-et-commits.md) — Conventional Commits et release-please
11. [docs/11-argocd-keycloak.md](docs/11-argocd-keycloak.md) — Argo CD, Keycloak et SSO
12. [docs/12-openbao.md](docs/12-openbao.md) — OpenBao (secrets), pourquoi pas Vault, unseal
13. [docs/13-deployer-une-application.md](docs/13-deployer-une-application.md) — déployer une appli (GitOps, secrets, SSO, ingress)
14. [docs/14-keda.md](docs/14-keda.md) — KEDA : autoscaling par événements (files, cron, jobs), avec exemples
15. [docs/15-partage-gpu.md](docs/15-partage-gpu.md) — partager un GPU : time-slicing, MIG, MPS, HAMi, GPU Operator

## Version express (si tout est déjà prêt)

```bash
source .venv/bin/activate     # active Ansible
make ping                     # le serveur répond ?
make all                      # GPU + k3s + apps (make gpu / k3s / apps séparément)
make unseal                   # après un redémarrage du serveur : desceller OpenBao
```

## Structure du dépôt

```
homelab/
├── ansible.cfg              # config Ansible (inventaire, sudo auto, affichage)
├── requirements.yml         # collections Ansible nécessaires (kubernetes.core...)
├── Makefile                 # raccourcis : make ping / k3s / apps / all / check
├── inventory/
│   ├── hosts.yml            # LES MACHINES (IP, utilisateur SSH)  -> README dedans
│   └── group_vars/
│       ├── all.yml          # variables globales (version k3s, helm...)
│       └── k3s_server.yml   # LA LISTE DES APPS (helm_releases)
├── playbooks/
│   ├── site.yml             # tout : k3s puis apps
│   ├── gpu.yml              # driver NVIDIA + CUDA + container toolkit
│   ├── k3s.yml              # seulement l'installation du cluster
│   └── apps.yml             # seulement les applications
├── roles/
│   ├── common/              # préparation de l'OS (paquets, swap)
│   ├── nvidia_cuda/         # driver NVIDIA, CUDA, container toolkit
│   ├── platform/            # DNS interne, secrets, Postgres, realm Keycloak
│   ├── openbao/             # init, unseal, configuration d'OpenBao, lien avec External Secrets
│   ├── k3s/                 # installation k3s + récupération kubeconfig
│   └── helm_apps/           # installation helm + déploiement des releases
├── apps/values/             # un fichier de values Helm par application
├── kubeconfig/              # kubeconfig récupéré (ignoré par git, contient des secrets)
├── .secrets/                # mots de passe générés (ignoré par git, À SAUVEGARDER)
├── apps/manifests/          # manifests de test (ex. gpu-test.yaml)
├── examples/                # modèles génériques à copier dans le dépôt d'une appli (Application Argo CD, values, secrets)
├── .github/workflows/       # release-please + lint des commits (workflows partagés)
└── docs/                    # tutoriels
```

## Vocabulaire rapide

- **Ansible** : outil qui exécute des « playbooks » (recettes) sur des machines en SSH. Idempotent : le relancer ne casse rien.
- **Inventaire** : la liste des machines que Ansible pilote.
- **Rôle** : un bloc de tâches réutilisable (ex. « installer k3s »).
- **k3s** : Kubernetes allégé, un seul binaire.
- **Helm** : gestionnaire de paquets Kubernetes ; un « chart » = une appli packagée, une « release » = une instance installée.
- **kubeconfig** : fichier qui dit à `kubectl` comment se connecter au cluster (adresse + identifiants).
- **Ingress / Traefik** : routeur HTTP du cluster, il aiguille `whoami.homelab.local` vers le bon pod.
