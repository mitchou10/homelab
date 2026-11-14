# 15. Partager un GPU entre plusieurs pods (MIG, time-slicing, MPS, HAMi…)

Par défaut, Kubernetes donne **un GPU entier à un seul pod** : `nvidia.com/gpu: 1` réserve la carte, et un 2ᵉ pod qui la demande reste `Pending`
(voir [09](09-gpu-cuda.md)). Ce guide explique les moyens de **partager** une carte, ce que chacun apporte, et **comment faire dans chaque cas**.

> **Statut des procédures** (important, relis-le avant d'appliquer) :
> - ✅ *vérifié sur ce homelab* : rendu du chart avec la configuration du time-slicing (génération de la ConfigMap contrôlée) ;
> - ⚠️ *non appliqué sur le cluster* : toutes les procédures ci-dessous (le GPU n'a pas été reconfiguré pour écrire cette doc) ;
> - ❌ *non applicable à ce matériel* : MIG, et très probablement MPS (Quadro P4000, architecture Pascal).

## 1. Les notions

| Terme | Sens |
|---|---|
| **Partitionnement matériel** | la carte est découpée en tranches **isolées** (mémoire et calcul réservés). C'est MIG. |
| **Partage logiciel** | plusieurs processus utilisent la même carte, sans cloisonnement matériel : time-slicing, MPS, HAMi. |
| **Isolation de la mémoire** | un pod peut-il prendre toute la VRAM des autres ? Seuls MIG et HAMi l'empêchent. |
| **Part** (*replica*) | un « morceau » annoncé à Kubernetes. Avec 4 parts, le nœud annonce `nvidia.com/gpu: 4`. |

## 2. Comparatif

| Solution | Principe | Isolation mémoire | Matériel requis | Sur la Quadro P4000 (8 Go, Pascal) |
|---|---|---|---|---|
| **MIG** | La carte est découpée en instances matérielles | ✅ forte | GPU **Ampere ou plus récent** de datacenter (A100, A30, H100…) | ❌ impossible |
| **Time-slicing** | Les pods se partagent la carte **à tour de rôle** | ❌ aucune | tout GPU NVIDIA | ✅ **possible** (c'est une option du plugin déjà installé) |
| **MPS** | Les processus partagent la carte **en même temps** via un serveur commun | partielle | **Volta ou plus récent** (d'après les docs NVIDIA/Kubernetes) | ❌ probablement non (Pascal) |
| **HAMi** | Virtualisation **logicielle** : limite de mémoire et de calcul par pod | ✅ (par logiciel) | tout GPU NVIDIA | ⚠️ possible, mais remplace notre device plugin |
| **GPU Operator** | Opérateur NVIDIA qui installe/gère tout (driver, toolkit, plugin, MIG Manager) | — (selon le mode choisi) | selon le mode | ⚠️ possible mais fait doublon avec l'existant |
| **DRA** (*Dynamic Resource Allocation*) | Nouvelle API Kubernetes pour demander des GPU/parts avec des `ResourceClaim` | selon le mode | selon le mode | ⚠️ voie d'avenir, plus complexe, non couvert ici |

### Lequel choisir ?

```
Ta carte supporte MIG (A100, H100…) et tu veux de l'isolation forte ?   ──► MIG        (§5)
Pas de MIG, tu veux juste faire tourner plusieurs pods légers ?          ──► Time-slicing (§3)   ← cas du homelab
Tu veux limiter la VRAM / le calcul de chaque pod sans MIG ?             ──► HAMi       (§6)
Tu as plusieurs GPU/nœuds et veux tout automatiser (driver compris) ?    ──► GPU Operator (§7)
```
**Pour ce homelab (un seul GPU, 8 Go, Pascal) : time-slicing.** Il suffit d'une option sur le plugin que tu as déjà.

## 3. Time-slicing (recommandé ici) ⚠️

Principe : le plugin annonce **N parts** au lieu d'une. N pods peuvent demander chacun `nvidia.com/gpu: 1` ; la carte passe de l'un à l'autre.

**Limites à connaître**
- **Aucune isolation de la mémoire** : les 8 Go sont communs. Un pod qui en prend trop fait échouer les autres (`out of memory`).
- **Aucune garantie de performance** : la puissance se répartit selon l'activité. N pods lourds en même temps = chacun N fois plus lent.
- **Pas d'isolation de panne** : un pod qui plante le GPU peut gêner les autres.
- Convient aux **workers légers ou intermittents** (inférence légère, OCR, petits modèles) ; pas à plusieurs entraînements simultanés.

### Mise en place

1. Éditer [apps/values/nvidia-device-plugin.yml](../apps/values/nvidia-device-plugin.yml) :
   ```yaml
   ---
   runtimeClassName: nvidia

   config:
     default: default
     map:
       default: |-
         version: v1
         flags:
           migStrategy: none
         sharing:
           timeSlicing:
             renameByDefault: false              # false : la ressource reste "nvidia.com/gpu"
             failRequestsGreaterThanOne: true    # refuse un pod qui demande plusieurs parts (voir ci-dessous)
             resources:
               - name: nvidia.com/gpu
                 replicas: 4                       # nombre de parts : à adapter
   ```
2. Déployer : `make apps` (Helm met à jour la release `nvidia-device-plugin`, le plugin redémarre avec la nouvelle configuration).
3. Vérifier :
   ```bash
   ssh tour 'sudo k3s kubectl get node -o jsonpath="{.items[0].status.allocatable.nvidia\.com/gpu}"'   # 4 au lieu de 1
   ssh tour 'sudo k3s kubectl get node --show-labels | tr "," "\n" | grep -i nvidia.com/gpu'          # étiquette ...replicas / product
   ```
4. Utiliser : **rien ne change dans les pods** (`runtimeClassName: nvidia`, `nvidia.com/gpu: 1`). Lance plusieurs pods : ils tournent ensemble.
   Vérifier sur le serveur : `ssh tour nvidia-smi` liste tous les processus qui utilisent la carte.

**Choix des options**
- `replicas` : le nombre de pods simultanés voulu **au maximum**. Plus il est grand, plus le risque de saturer les 8 Go est élevé.
- `failRequestsGreaterThanOne: true` : un pod qui demanderait `nvidia.com/gpu: 2` croirait recevoir 2 GPU alors qu'il ne reçoit qu'**une seule carte partagée**. Avec `true`, il est refusé : plus clair. (NVIDIA le recommande, il est à `false` par défaut seulement pour la compatibilité.)
- `renameByDefault: true` : les parts s'annoncent `nvidia.com/gpu.shared` au lieu de `nvidia.com/gpu`. Utile pour **distinguer** les pods qui acceptent le partage de ceux qui veulent la carte entière. Les pods doivent alors demander `nvidia.com/gpu.shared`.

**Retour en arrière** : remettre `replicas: 1` (ou retirer le bloc `config`) puis `make apps`.

**Avec KEDA** ([14](14-keda.md)) : le `maxReplicaCount` d'un `ScaledObject` de workers GPU ne doit pas dépasser le nombre de parts, sinon les pods en trop restent `Pending`.

## 4. MPS ❌ (probablement non applicable : Pascal)

MPS (*Multi-Process Service*) fait **partager la carte en même temps** par plusieurs processus, avec des limites de mémoire par client.
D'après les documentations consultées, il demande des GPU **Volta ou plus récents** : la Quadro P4000 (Pascal) n'est donc pas concernée.
Pour une carte plus récente, le plugin NVIDIA le propose avec la même forme de configuration que le time-slicing :

```yaml
config:
  default: default
  map:
    default: |-
      version: v1
      sharing:
        mps:
          resources:
            - name: nvidia.com/gpu
              replicas: 4
```
Points d'attention : le chart a une section `mps:` (`enableHostPID`, répertoire `/run/nvidia/mps`) ; MPS et MIG sont **exclusifs** ; vérifier la compatibilité exacte avec ta carte
dans la documentation du plugin avant d'activer.

## 5. MIG ❌ (pas sur cette carte)

MIG découpe une carte en **instances isolées**, chacune avec sa mémoire et son calcul. Réservé aux GPU de datacenter **Ampere et plus récents** (A100, A30, H100…).
À garder en tête si tu changes de carte. Principe de la mise en place, avec le **GPU Operator** (§7), qui contient le *MIG Manager* :

1. Installer le GPU Operator en indiquant la stratégie MIG :
   - `mig.strategy=single` : chaque instance MIG apparaît comme `nvidia.com/gpu` (toutes de même taille) ;
   - `mig.strategy=mixed` : chaque profil a sa ressource (`nvidia.com/mig-1g.10gb`…), pour mélanger plusieurs tailles.
2. Si le driver est déjà installé sur l'hôte (notre cas avec le rôle `nvidia_cuda`), ajouter `driver.enabled=false`.
3. Choisir le découpage en étiquetant le nœud : `kubectl label node <nœud> nvidia.com/mig.config=all-1g.10gb --overwrite` (le nom du profil dépend de la carte).
4. Les pods demandent la ressource correspondante (`nvidia.com/gpu: 1` en `single`, `nvidia.com/mig-1g.10gb: 1` en `mixed`).

> Remarque de la doc NVIDIA : la stratégie MIG ne **active** pas le mode MIG, c'est le *MIG Manager* (via l'étiquette `nvidia.com/mig.config`) qui reconfigure la carte. Elle peut nécessiter de vider le nœud.
> La liste exacte des cartes supportées et des profils : voir le *MIG User Guide* de NVIDIA.

## 6. HAMi (limites de mémoire et de calcul, sans MIG) ⚠️

HAMi est un projet CNCF de **virtualisation logicielle** : un pod déclare **combien de VRAM et de calcul** il veut, et HAMi le limite. Fonctionne sur des cartes sans MIG.

**Ressources demandées par un pod**
```yaml
resources:
  limits:
    nvidia.com/gpu: 1            # une « carte virtuelle »
    nvidia.com/gpumem: 3000      # mémoire max en Mio
    nvidia.com/gpucores: 30      # pourcentage de calcul (1 à 100)
```
Sans `gpumem`/`gpucores`, le pod a toute la carte. Variante : `nvidia.com/gpumem-percentage`.

**Installation (d'après les guides publics, à valider avec la doc officielle)**
```bash
kubectl label node <nœud> gpu=on
helm repo add hami-charts https://project-hami.github.io/HAMi/
helm install hami hami-charts/hami -n kube-system --set scheduler.kubeScheduler.imageTag=<version de Kubernetes du cluster>
```
Pour l'intégrer proprement à ce dépôt : une entrée dans `helm_releases` (comme `keda`), des values dans `apps/values/hami.yml`, et la version figée.

**À savoir**
- HAMi **apporte son propre device plugin et son propre ordonnanceur** : il **remplace** le plugin NVIDIA (`nvidia-device-plugin`), il ne s'ajoute pas. Ne fais pas tourner les deux sur le même GPU.
- La limite est **logicielle** (interception de l'API CUDA) : plus souple que MIG, mais moins étanche.
- Les versions de Kubernetes/driver supportées varient selon les sources : lire les prérequis officiels. Le cluster est en k3s (ordonnanceur intégré) : à valider.
- Il garde la couche de virtualisation active même sans limites.

## 7. GPU Operator ⚠️ (tout automatiser)

Le **GPU Operator** NVIDIA installe et surveille : driver, container toolkit, device plugin, découverte des cartes, supervision (DCGM) et *MIG Manager*.
Il est pensé pour des **parcs de machines** (il gère le driver dans des conteneurs). Sur ce homelab, c'est **déjà fait par le rôle `nvidia_cuda` + le chart du plugin**, donc :

| Choix | Quand |
|---|---|
| **Garder l'existant** (recommandé ici) | un nœud, une carte, driver installé sur l'hôte |
| **Passer au GPU Operator** | plusieurs nœuds GPU, ou besoin de MIG / supervision intégrée |

Si tu l'installes malgré tout avec le driver de l'hôte : `driver.enabled=false` (confirmé par la doc NVIDIA) et, si le toolkit est aussi sur l'hôte, `toolkit.enabled=false`
(à confirmer dans la doc de ta version). **Retire alors** la release `nvidia-device-plugin` de `helm_releases` : l'opérateur déploie son propre plugin, deux plugins sur un nœud se marchent dessus.

## 8. Diagnostic

| Symptôme | Cause probable |
|---|---|
| Un 2ᵉ pod reste `Pending` (`Insufficient nvidia.com/gpu`) | pas de partage activé, ou plus de parts libres : `kubectl describe node` → *Allocated resources* |
| `CUDA out of memory` dans un pod | la VRAM est partagée sans isolation (time-slicing) : moins de parts, ou HAMi pour limiter |
| Un pod demandant 2 GPU est refusé | `failRequestsGreaterThanOne: true` : normal, demander 1 |
| `nvidia.com/gpu` toujours à 1 après le changement | le plugin n'a pas redémarré : `kubectl -n nvidia-device-plugin rollout restart ds/nvidia-device-plugin` |
| Les pods tournent mais sont très lents | N pods actifs en même temps se répartissent la carte : réduire le nombre de parts |
| Le plugin ne démarre plus | configuration invalide ou options exclusives (MPS + MIG) : `kubectl -n nvidia-device-plugin logs ds/nvidia-device-plugin` |

## Pour aller plus loin

- [Time-slicing avec le GPU Operator (NVIDIA)](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html.md) : syntaxe de la configuration (`replicas`, `renameByDefault`, `failRequestsGreaterThanOne`)
- [GPU Operator avec MIG (NVIDIA)](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-mig.html) : stratégies `single` / `mixed`, `driver.enabled=false`
- [Partage de GPU avec MPS, driver DRA](https://dra-driver-nvidia-gpu.sigs.k8s.io/docs/guides/mps/) : exigence Volta ou plus récent
- [HAMi : partage de GPU](https://cozystack.io/docs/v1.6/kubernetes/gpu-sharing/) : ressources `gpumem` / `gpucores`
