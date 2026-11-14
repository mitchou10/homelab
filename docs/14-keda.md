# 14. KEDA : autoscaling piloté par les événements

KEDA (*Kubernetes Event-driven Autoscaling*) ajuste **le nombre de pods d'une application selon ce qui se passe réellement** :
nombre de messages dans une file, une heure de la journée, le résultat d'une requête… et peut descendre **à zéro pod**
quand il n'y a rien à faire.

C'est déjà installé : `make apps` déploie la release `keda` (namespace `keda`, chart 2.21.0).

## À quoi ça sert, concrètement ?

| Sans KEDA | Avec KEDA |
|---|---|
| Un worker tourne 24 h/24 même sans travail (il consomme CPU et RAM pour rien) | 0 pod quand la file est vide, 1 à N pods quand elle se remplit |
| Le HPA de base ne regarde que le **CPU et la mémoire** : un worker qui attend une longue tâche n'a pas de pic de CPU, donc pas de renfort | On scale sur la **vraie charge** : longueur de file, requêtes en attente… |
| Impossible de prévoir l'arrivée de travail | Un `cron` monte les pods avant l'heure de pointe |
| Un traitement ponctuel exige un Job lancé à la main | Un **Job par message** lancé automatiquement (`ScaledJob`) |

Exemples d'usage sur ce homelab : workers Celery (file Redis), traitements de documents (OCR…) qui dorment la nuit,
tâches planifiées, jobs de batch déclenchés par une file.

## Comment ça marche

```
 source d'événements ──► KEDA (operator) ──► crée et pilote un HPA ──► Deployment / StatefulSet
 (Redis, cron, SQL...)        │
                              └─ 0 ↔ 1 pod : KEDA lui-même      1 ↔ N pods : le HPA, alimenté par les métriques de KEDA
```
Tu écris **un objet** `ScaledObject` à côté de ton application ; KEDA s'occupe du reste.

Ce qui tourne dans le namespace `keda` :

| Pod | Rôle |
|---|---|
| `keda-operator` | surveille les `ScaledObject`, interroge les sources, fait passer 0 ↔ 1 |
| `keda-operator-metrics-apiserver` | fournit les métriques au HPA (API `external.metrics.k8s.io`) |
| `keda-admission-webhooks` | refuse les `ScaledObject` invalides (ex. deux autoscalers sur la même cible) |

Il **cohabite** avec le `metrics-server` de k3s (`metrics.k8s.io`) : ce sont deux API différentes.
Nouveaux objets Kubernetes (CRD) : `ScaledObject`, `ScaledJob`, `TriggerAuthentication`, `ClusterTriggerAuthentication`.

Vérifier :
```bash
ssh tour 'sudo k3s kubectl -n keda get pods'
ssh tour 'sudo k3s kubectl get scaledobject -A'        # READY / ACTIVE de chaque autoscaling
```

## Les réglages importants d'un ScaledObject

| Champ | Sens | Défaut |
|---|---|---|
| `scaleTargetRef.name` | le Deployment/StatefulSet à piloter (**même namespace**) | — |
| `minReplicaCount` | plancher. `0` = scale to zero | `0` |
| `maxReplicaCount` | plafond | `100` |
| `pollingInterval` | fréquence de lecture de la source (s) | `30` |
| `cooldownPeriod` | attente avant de redescendre **à 0** (s) | `300` |
| `triggers` | une ou plusieurs sources ; le plus gros besoin l'emporte | — |
| `advanced.horizontalPodAutoscalerConfig.behavior` | vitesse de montée/descente (ex. `scaleDown.stabilizationWindowSeconds`) | HPA par défaut |
| `advanced.restoreToOriginalReplicaCount` | à la suppression du `ScaledObject`, remettre le nombre de réplicas d'origine | `false` |

Mettre en pause : annotation `autoscaling.keda.sh/paused-replicas: "0"` sur le `ScaledObject`.

## Exemple 1 : workers sur une file Redis (cas typique Celery)

Un worker Celery lit une queue stockée dans une liste Redis. KEDA compte les éléments de la liste : **1 pod pour 5 messages**, de 0 à 4 pods.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: monapp-worker
  namespace: monapp
spec:
  scaleTargetRef:
    name: monapp-worker            # le Deployment des workers
  minReplicaCount: 0
  maxReplicaCount: 4
  pollingInterval: 5
  cooldownPeriod: 30
  triggers:
    - type: redis
      metadata:
        address: redis.monapp.svc.cluster.local:6379
        listName: celery           # nom de la queue Celery (dans Redis : une liste du même nom)
        listLength: "5"            # nombre de messages « acceptables » par pod
        databaseIndex: "0"         # même base que CELERY_BROKER_URL (.../0)
      authenticationRef:
        name: monapp-redis-auth
```

Le mot de passe Redis n'est **jamais** dans l'objet : une `TriggerAuthentication` le lit dans un Secret Kubernetes.
Ce Secret vient d'OpenBao via External Secrets (voir [13](13-deployer-une-application.md)) :

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: monapp-redis-auth
  namespace: monapp
spec:
  secretTargetRef:
    - parameter: password
      name: monapp-redis          # Secret Kubernetes (créé par un ExternalSecret)
      key: redis-password
```

**Essai réel fait sur ce cluster** (Redis avec mot de passe, 20 messages poussés) :
0 pod → **4 pods en moins de 10 s** ; file vidée → retour à **0 pod 30 s plus tard** (= `cooldownPeriod`).

Pièges propres à Celery + Redis :
- Un worker **préfetch** des tâches (`worker_prefetch_multiplier`, 4 par défaut) : elles sortent de la liste mais ne sont pas finies, donc la longueur de la liste
  **sous-estime** le travail. Mettre `worker_prefetch_multiplier = 1` et une valeur de `listLength` basse.
- Les tâches prises mais pas encore acquittées (`acks_late`) ne sont **pas** dans la liste : le déclencheur `redis` simple ne les compte pas.
- Avec `minReplicaCount: 0`, la première tâche attend le démarrage du pod (quelques secondes, plus si l'image est lourde).
- Les tâches doivent supporter d'être **interrompues** : à la descente, Kubernetes arrête des pods (prévoir `terminationGracePeriodSeconds` suffisant).

## Exemple 2 : cron (monter avant l'heure de pointe)

Au moins 2 pods en semaine de 8 h à 19 h, aucun le reste du temps.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: monapp-web-heures-bureau
  namespace: monapp
spec:
  scaleTargetRef:
    name: monapp-web
  minReplicaCount: 0
  maxReplicaCount: 3
  triggers:
    - type: cron
      metadata:
        timezone: Europe/Paris
        start: 0 8 * * 1-5
        end: 0 19 * * 1-5
        desiredReplicas: "2"
```
Utile pour les outils internes peu utilisés. Combinable avec un autre déclencheur (le plus grand nombre de réplicas demandé gagne).

## Exemple 3 : CPU et mémoire (comme un HPA, plus des bornes à zéro)

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: monapp-api
  namespace: monapp
spec:
  scaleTargetRef:
    name: monapp-api
  minReplicaCount: 1
  maxReplicaCount: 5
  triggers:
    - type: cpu
      metricType: Utilization
      metadata:
        value: "70"
```
Les scalers `cpu` et `memory` **ne peuvent pas descendre à 0** (`minReplicaCount` ≥ 1). Ils s'appuient sur le metrics-server de k3s.
**Ne pas** activer en plus un HPA classique (par exemple `autoscaling.enabled: true` dans un chart Helm) sur la même cible.

## Exemple 4 : un Job par tâche (ScaledJob)

Au lieu de faire grossir un Deployment, KEDA **crée un Job** pour un groupe de messages, qui se termine seul. Idéal pour du traitement long et isolé.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: monapp-batch
  namespace: monapp
spec:
  jobTargetRef:
    template:
      spec:
        restartPolicy: Never
        containers:
          - name: batch
            image: monapp/batch:1.0.0
            command: ["python", "traiter_un_message.py"]
  pollingInterval: 10
  maxReplicaCount: 5               # jobs en parallèle au maximum
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  triggers:
    - type: redis
      metadata:
        address: redis.monapp.svc.cluster.local:6379
        listName: lot-a-traiter
        listLength: "1"
      authenticationRef:
        name: monapp-redis-auth
```
Le Job doit **consommer** le message (le retirer de la liste), sinon KEDA en recrée indéfiniment.

## Autres sources utiles (non testées ici)

KEDA sait lire de nombreuses sources (une soixantaine) : PostgreSQL (`postgresql`, requête SQL), RabbitMQ, Kafka, MySQL,
files d'objets S3, Prometheus, etc. Le schéma est toujours le même : un `type`, des `metadata`, une `TriggerAuthentication` pour les identifiants.
Catalogue : https://keda.sh/docs/latest/scalers/

> **Prometheus** (très pratique pour scaler sur des métriques applicatives) n'est **pas** installé sur ce homelab. À ajouter avant d'utiliser le scaler `prometheus`.
> **HTTP** (scale to zero d'une appli web selon les requêtes) demande l'extension `keda-add-ons-http`, non installée.

## GPU

Un GPU ne sert qu'**un pod à la fois** sur ce serveur (un seul GPU, voir [09](09-gpu-cuda.md)). Un `ScaledObject` qui demande plus d'un pod
avec `nvidia.com/gpu: 1` laissera les pods supplémentaires en `Pending`. Pour des workers GPU : `maxReplicaCount: 1`,
ou activer le partage du GPU (time-slicing : [15](15-partage-gpu.md)) et ne pas dépasser le nombre de parts.

## Où mettre le `ScaledObject` ?

**Avec l'application**, dans son chart ou ses manifests (par exemple via `extraObjects` d'un chart Helm), pas dans ce dépôt.
Ce dépôt ne fournit que l'opérateur KEDA. Argo CD le déploie ensuite comme le reste ([13](13-deployer-une-application.md)).

## Tester soi-même (reproduit l'essai du §1)

```bash
# 1. appliquer un ScaledObject, 2. pousser du travail, 3. regarder
ssh tour 'sudo k3s kubectl -n monapp get deploy monapp-worker -w'
ssh tour 'sudo k3s kubectl -n monapp exec deploy/redis -- redis-cli LPUSH celery a b c d e f g h i j'
ssh tour 'sudo k3s kubectl -n monapp describe scaledobject monapp-worker'    # événements et état
```

## Dépannage

| Symptôme | Cause probable |
|---|---|
| `ScaledObject` en `READY False` | source injoignable ou identifiants faux : `kubectl describe scaledobject`, logs `kubectl -n keda logs deploy/keda-operator` |
| Admission refusée : « already managed by the hpa » | un HPA existe déjà sur la même cible : le supprimer ou le désactiver dans le chart |
| Le pod ne monte pas à N | `maxReplicaCount` atteint, ressources du nœud insuffisantes, ou GPU unique (voir ci-dessus) |
| Ne redescend pas à 0 | `cooldownPeriod` pas écoulé, un autre déclencheur (cron, cpu) maintient ≥ 1 pod, ou des messages restent dans la file |
| `unauthorized` / `NOAUTH` | la `TriggerAuthentication` pointe vers un Secret ou une clé absents (voir `kubectl get externalsecret`, OpenBao scellé ?) |
