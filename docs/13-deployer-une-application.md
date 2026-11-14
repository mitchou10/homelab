# 13. Déployer une application (GitOps) avec secrets OpenBao et SSO

Principe : **ce dépôt (homelab) ne contient que l'infra**. Chaque application garde chez elle sa config de déploiement ;
Argo CD la lit, la déploie et détecte les changements.

```
  dépôt de l'appli  ──push──►  GitHub  ◄──sondage 3 min──  Argo CD  ──►  cluster
  (chart + values homelab                                      │
   + Application Argo CD)                    secrets: OpenBao ─► External Secrets ─► Secret Kubernetes
                                              SSO: Keycloak (client OIDC)
```

## Ce que l'infra fournit déjà

| Besoin | Fourni par | Comment l'utiliser |
|---|---|---|
| Déployer / synchroniser | Argo CD | une ressource `Application` pointant sur le dépôt de l'app |
| Ingress | Traefik (k3s) | `ingressClassName: traefik`, host `<app>.homelab.local` |
| Secrets | OpenBao + External Secrets | un `ExternalSecret` qui référence le `ClusterSecretStore` **`openbao`** |
| Connexion SSO | Keycloak (realm `homelab`) | un client OIDC (voir plus bas) |
| Noms de domaine | CoreDNS interne | `*.homelab.local` résolu vers Traefik **dans** le cluster |
| GPU | device plugin NVIDIA | `runtimeClassName: nvidia` + `nvidia.com/gpu: 1` |
| Autoscaling | KEDA | un `ScaledObject` à côté de l'appli (file, cron, scale to zero) : voir [14](14-keda.md) |

## 1. Le dépôt de l'application contient

1. un **chart Helm** (ou des manifests) ;
2. un fichier de valeurs **homelab** (ex. `values/homelab.yaml`) : ingress Traefik, URL de Keycloak, ExternalSecrets ;
3. une **Application Argo CD** (modèle ci-dessous).

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monapp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<toi>/<monapp>.git
    targetRevision: HEAD
    path: helm
    helm:
      valueFiles: [values.yaml, values/homelab.yaml]
  destination:
    server: https://kubernetes.default.svc
    namespace: monapp            # OBLIGATOIRE (sinon « Namespace … is missing »)
  syncPolicy:
    automated: {prune: true, selfHeal: true}
    syncOptions: [CreateNamespace=true]
```
Application appliquée **une fois** : `ssh tour 'sudo k3s kubectl apply -f -' < application.yaml` (ou interface Argo CD → Edit as YAML).

## 2. Comment les changements sont détectés

- Argo CD **interroge git toutes les 3 minutes** (pas de webhook : le cluster n'est pas joignable depuis internet, et c'est inutile ici).
- `automated` : il applique tout seul. `prune` supprime ce qui a disparu de git, `selfHeal` annule les modifications faites à la main.
- Tu modifies le chart ou les values → `git push` → au plus 3 minutes plus tard, le cluster est à jour.
- Forcer : bouton **Refresh** dans l'interface, ou `kubectl -n argocd annotate application monapp argocd.argoproj.io/refresh=hard --overwrite`.
- Nouvelle image : si le tag est dans les values, change-le et pousse. Pour l'automatiser, un bot (Renovate) ouvre des PR de mise à jour.

## 3. Ingress Traefik

Chart-level ou par composant, il suffit de :
```yaml
ingress:
  ingressClassName: traefik       # le « className » vaut "" par défaut dans beaucoup de charts
  hosts: [monapp.homelab.local]
```
Les annotations `nginx.ingress.kubernetes.io/*` n'ont aucun effet avec Traefik (inutiles, sans danger).
Ajouter `monapp.homelab.local` dans le `/etc/hosts` du PC (ou DNS local).

## 4. Secrets : OpenBao → External Secrets

Les secrets **ne sont jamais dans git**. Ils vivent dans OpenBao (KV v2 monté sur `secret/`).

1. Créer le secret : interface OpenBao (connexion SSO) ou
   `bao kv put secret/monapp DB_PASSWORD=... API_KEY=...`
2. Dans le dépôt de l'app, un `ExternalSecret` crée le `Secret` Kubernetes :
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: monapp-secrets
spec:
  refreshInterval: 1h
  secretStoreRef: {kind: ClusterSecretStore, name: openbao}
  target:
    name: monapp-secrets            # nom du Secret Kubernetes créé
    template:
      engineVersion: v2
      data:
        DATABASE_URL: "postgresql://app:{{ .DB_PASSWORD }}@db:5432/app"   # on peut composer des valeurs
  dataFrom:
    - extract: {key: monapp}        # = secret/monapp dans OpenBao
```
Le pod le consomme par `envFrom: - secretRef: {name: monapp-secrets}`. Si l'ExternalSecret est dans un chart Helm,
échapper `{{ }}` : `{{ "{{" }} .DB_PASSWORD {{ "}}" }}`.

**Droits** : External Secrets lit **tout** `secret/*` (policy `eso-reader`) via l'authentification Kubernetes (rôle `eso`).
Simple pour un homelab ; pour isoler des apps, créer un `SecretStore` par namespace avec son propre rôle OpenBao.

Diagnostic : `kubectl get externalsecret -A` (colonne STATUS = `SecretSynced`), `kubectl describe externalsecret <nom>`.

## 5. SSO Keycloak

Dans le realm `homelab`, un client **confidentiel** par application. Deux méthodes :
- **Console Keycloak** : Clients → Create client → OpenID Connect, Client authentication ON, redirect URI de l'app.
- **Ansible** : une entrée dans `keycloak_clients` (`inventory/group_vars/all.yml`) puis `make apps` crée le client (rôles de client,
  PKCE, mappers inclus : voir `roles/platform/templates/client.json.j2` pour les champs `attributes`, `client_roles`, `user_roles`, `groups_full_path`).

Côté application : issuer `http://keycloak.homelab.local/realms/homelab`, client id, client secret (à mettre dans OpenBao, voir §4),
scopes `openid profile email`, groupes dans le claim `groups`.

## 6. Erreurs courantes (déjà rencontrées)

| Message Argo CD | Cause | Solution |
|---|---|---|
| `Namespace for … is missing` | `destination.namespace` absent, et le chart ne met pas de namespace | ajouter `destination.namespace` + `CreateNamespace=true` |
| `failed to discover server resources for group version secrets.hashicorp.com/v1beta1` | le chart utilise le Vault Secrets Operator (absent) | remplacer par des `ExternalSecret` (§4) ; ne pas utiliser les values « entreprise » |
| `ImagePullBackOff` sur un registre privé | values d'un autre environnement | utiliser les images publiques, ou un `imagePullSecret` |
| `CreateContainerConfigError` | Secret absent (ExternalSecret pas encore synchronisé, ou clé manquante dans OpenBao) | `kubectl describe externalsecret`, vérifier `secret/<app>` dans OpenBao |
| Pods `Pending`, OpenBao `sealed` | OpenBao scellé après un redémarrage | `make unseal` |
