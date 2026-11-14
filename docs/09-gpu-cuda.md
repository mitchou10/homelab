# 9. GPU NVIDIA, CUDA et GPU dans Kubernetes

Objectif : sur une machine **vide** avec une carte NVIDIA, obtenir le driver, CUDA, et pouvoir donner le GPU à des pods k3s.

Machine actuelle : `tour`, **Quadro P4000** (architecture Pascal, 8 Go).

## Ce que fait le rôle `nvidia_cuda`

Fichier : [roles/nvidia_cuda/tasks/main.yml](../roles/nvidia_cuda/tasks/main.yml). Lancé par [playbooks/gpu.yml](../playbooks/gpu.yml).

| Étape | Détail |
|---|---|
| Détection | `lspci` : s'arrête avec une erreur claire s'il n'y a pas de GPU NVIDIA |
| Driver | `nvidia-driver-580` du dépôt Ubuntu (variable `nvidia_driver_package`) |
| Dépôt CUDA | paquet `cuda-keyring` (clé + dépôt réseau NVIDIA) |
| Protection du driver | fichier APT `preferences.d/cuda-no-driver` : le dépôt NVIDIA ne peut **pas** fournir/remplacer de driver |
| CUDA toolkit | `cuda-toolkit-12-6` (pas le méta-paquet `cuda`, qui embarque un driver) |
| Environnement | `/etc/profile.d/cuda.sh` (PATH + LD_LIBRARY_PATH) |
| Container toolkit | `nvidia-container-toolkit` : permet à containerd (donc k3s) de donner le GPU aux conteneurs |
| Vérification | `nvidia-smi`, `nvcc`, et signale si un **redémarrage** est requis |

Le rôle est **idempotent** : sur `tour`, où tout était déjà installé à la main, il n'a presque rien changé.

## Ce qui est fait côté Kubernetes

1. **Ordre** : `site.yml` lance `gpu.yml` **avant** `k3s.yml`. k3s détecte alors le runtime `nvidia` dans sa config containerd au démarrage.
   (Si le toolkit est installé *après* k3s, le handler redémarre k3s : `nvidia_restart_k3s`.)
2. **RuntimeClass `nvidia`** créée par [playbooks/apps.yml](../playbooks/apps.yml).
3. **Label du nœud** `nvidia.com/gpu.present=true` posé par Ansible. Le chart du device plugin ne se déploie que sur les nœuds portant ce label (d'habitude posé par Node Feature Discovery, qu'on n'installe pas).
4. **Device plugin NVIDIA** déployé via Helm (entrée `nvidia-device-plugin` dans `k3s_server.yml`, values dans `apps/values/nvidia-device-plugin.yml`). Il fait apparaître la ressource `nvidia.com/gpu` sur le nœud.

## Utilisation

### Depuis zéro

```bash
source .venv/bin/activate
make gpu        # driver + CUDA + container toolkit
make k3s        # (si pas déjà fait)
make apps       # RuntimeClass + label + device plugin
```
Ou tout d'un coup : `make all`.

### Si Ansible dit « Redémarrage requis : OUI »

Après une install de driver ou de noyau : `ssh tour sudo reboot`, puis vérifier `ssh tour nvidia-smi`.

### Vérifier

```bash
ssh tour nvidia-smi                                    # driver
ssh tour '/usr/local/cuda/bin/nvcc --version'          # CUDA toolkit
ssh tour 'sudo k3s kubectl get node -o jsonpath="{.items[0].status.allocatable.nvidia\.com/gpu}"'   # doit afficher 1
```

### Test dans Kubernetes

```bash
scp apps/manifests/gpu-test.yaml tour:/tmp/
ssh tour 'sudo k3s kubectl apply -f /tmp/gpu-test.yaml && sleep 20 && sudo k3s kubectl logs gpu-test'
ssh tour 'sudo k3s kubectl delete pod gpu-test'
```
On doit voir le tableau `nvidia-smi` avec la Quadro P4000 **depuis le pod**.

### Donner le GPU à une de tes apps

Dans le pod/déploiement :

```yaml
spec:
  runtimeClassName: nvidia          # obligatoire avec k3s
  containers:
    - name: app
      resources:
        limits:
          nvidia.com/gpu: 1
```

> Un GPU = **un seul pod à la fois** (pas de partage par défaut). Un 2e pod qui demande le GPU restera `Pending`.
> Le partage (time-slicing, MPS, MIG, HAMi) est expliqué dans [15](15-partage-gpu.md) : sur cette carte, le **time-slicing** est le choix adapté.

## Variables

| Variable | Défaut | Rôle |
|---|---|---|
| `nvidia_driver_package` | `nvidia-driver-580` | paquet driver Ubuntu |
| `cuda_toolkit_version` | `12-6` | version du toolkit (format APT) |
| `cuda_repo_distro` | `ubuntu2404` | distribution du dépôt NVIDIA |
| `nvidia_restart_k3s` | `true` | redémarrer k3s si le toolkit change |

### Pourquoi driver 580 et CUDA 12.x ?

Le P4000 est une carte **Pascal**. D'après la documentation NVIDIA, la branche de driver 580 est la dernière à la supporter, et CUDA 13 abandonne les architectures avant Turing : on reste donc en **CUDA 12.x**. (`nvidia-smi` affiche « CUDA Version: 13.0 » : c'est seulement la version maximale que le driver sait exécuter, pas le toolkit installé.) Si tu remplaces la carte par une plus récente, ces variables pourront monter.

## Rôles existants regardés (et pourquoi on ne les a pas utilisés tels quels)

| Projet | Verdict |
|---|---|
| [NVIDIA/ansible-role-nvidia-driver](https://github.com/NVIDIA/ansible-role-nvidia-driver) | Officiel mais **driver seulement**, et **redémarre** la machine automatiquement |
| [andrewtwin/ansible-role-install_nvidia_cuda](https://awesome.ecosyste.ms/projects/github.com%2Fandrewtwin%2Fansible-role-install_nvidia_cuda) | Driver + toolkit sur Ubuntu 24.04, mais peu actif (créé en janvier 2025) |
| [jedimt/ansible-role-cuda](https://galaxy.semaphoreui.com/views/jedimt/ansible-role-cuda) | Ciblé Ubuntu 22.04 |
| [Tuto k3s + GPU (ITNext)](https://itnext.io/enabling-nvidia-gpus-on-k3s-for-cuda-workloads-a11b96f967b0) | Source des étapes containerd/k3s (toolkit version containerd uniquement) |

Aucun ne couvre driver + CUDA + container toolkit + k3s ensemble, et `tour` avait déjà une install existante qu'il ne fallait pas écraser : le rôle est donc écrit pour ce dépôt, en reprenant leurs pratiques (clé via `cuda-keyring`, `cuda-toolkit` plutôt que le méta-paquet `cuda`).
