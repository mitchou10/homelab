# 11. Argo CD + Keycloak (SSO)

- **Keycloak** : serveur d'identité. Un seul compte pour se connecter à toutes les applications (SSO via OpenID Connect).
- **Argo CD** : GitOps. Déploie des applications depuis git. Ici, déjà branché sur Keycloak.

Tout est déployé par `make apps`. Aucun mot de passe n'est écrit dans git.

## Adresses

| Service | URL | Connexion |
|---|---|---|
| Keycloak (console admin) | http://keycloak.homelab.local/admin/master/console/ | `admin` + mot de passe (voir ci-dessous) |
| Keycloak (compte utilisateur) | http://keycloak.homelab.local/realms/homelab/account/ | `michou` |
| Argo CD | http://argocd.homelab.local | bouton **Log in via Keycloak** |

### 1. Sur ton PC : résoudre les noms (une seule fois)

```bash
echo '192.168.1.12 keycloak.homelab.local argocd.homelab.local' | sudo tee -a /etc/hosts
```
À chaque nouvelle app (`<app>.homelab.local`), ajouter son nom sur cette ligne. Un DNS local (Pi-hole, AdGuard Home) avec un joker `*.homelab.local` évite de le refaire (voir [08](08-prochaines-etapes.md)).

### 2. Récupérer les mots de passe

Générés automatiquement au premier `make apps`, stockés dans `.secrets/` (**ignoré par git**).

```bash
make creds
```
- `keycloak_admin_password` : compte `admin` du realm `master` (administration de Keycloak)
- `homelab_user_password` : compte `michou` du realm `homelab` (ton compte pour toutes les apps)

> **Sauvegarde `.secrets/`** (gestionnaire de mots de passe). Si tu le perds, de nouveaux mots de passe seront générés, mais la base Postgres de Keycloak garde l'ancien mot de passe : il faudrait la réinitialiser.

## Ce qui est configuré par défaut

Realm **`homelab`** (importé au premier démarrage, voir [realm-homelab.json.j2](../roles/platform/templates/realm-homelab.json.j2)) :

| Élément | Valeur |
|---|---|
| Groupes | `homelab-admins`, `homelab-users` (les nouveaux utilisateurs vont dans `homelab-users`) |
| Utilisateur | `michou`, membre des deux groupes |
| Clients (apps) | `argocd` |
| Sessions | inactivité 10 h, durée max 24 h, anti brute-force activé |
| Inscription libre | désactivée |
| Token | contient le claim `groups` (les apps s'en servent pour les droits) |

Argo CD : les membres de `homelab-admins` sont **admin**, les autres connectés sont en **lecture seule** (`policy.default: role:readonly`).

## Comment ça marche (et pourquoi le DNS interne)

```
navigateur ──► argocd.homelab.local ──► Traefik ──► Argo CD
                    │ « Log in via Keycloak »
                    ▼
            keycloak.homelab.local ──► Traefik ──► Keycloak ──► Postgres
```
Argo CD (dans le cluster) doit aussi joindre `keycloak.homelab.local` pour valider les tokens. Dans le cluster, ce nom n'existe pas : le rôle `platform` ajoute donc une ConfigMap `coredns-custom` qui redirige **tout `*.homelab.local` vers Traefik**. L'adresse (issuer) est ainsi la même vue du navigateur et du cluster.

## Utiliser Argo CD

Exemple : déployer une app depuis git. Créer `argocd-apps/exemple.yaml` (puis `kubectl apply -f`, ou via l'interface) :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: exemple
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Mitchou10/homelab.git
    targetRevision: main
    path: apps/exemple          # dossier de manifests ou chart Helm
  destination:
    server: https://kubernetes.default.svc
    namespace: exemple
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
```
Migration progressive : les apps actuelles (Helm via Ansible) peuvent passer en `Application` une par une. Argo CD ne doit gérer qu'**une** source de vérité par app (soit Ansible, soit Argo CD).

## Connecter une nouvelle application au SSO

1. Dans [inventory/group_vars/all.yml](../inventory/group_vars/all.yml), ajouter un client dans `keycloak_clients` :
   ```yaml
   - id: grafana
     name: Grafana
     root_url: "http://grafana.{{ homelab_domain }}"
     redirect_uris: ["http://grafana.{{ homelab_domain }}/login/generic_oauth"]
     secret: "{{ lookup('ansible.builtin.password', secrets_dir ~ '/client_grafana_secret length=40 chars=ascii_letters,digits') }}"
   ```
2. Configurer l'app en OIDC avec :
   - **Issuer / URL de découverte** : `http://keycloak.homelab.local/realms/homelab` (`/.well-known/openid-configuration`)
   - **Client ID** : `grafana` ; **Client secret** : la valeur du `secret` (réutilisable dans ses values Helm via la même variable, comme `apps/values/argocd.yml`)
   - **Scopes** : `openid profile email` ; claim de groupes : `groups`
3. `make apps` : le client est **créé dans Keycloak automatiquement** (même si le realm existe déjà).
4. Ajouter `grafana.homelab.local` dans `/etc/hosts`.

> Ajouter un client crée celui-ci seulement s'il n'existe pas. Pour **modifier** un client existant (URL de redirection...), passer par la console d'admin Keycloak.

## Gérer les utilisateurs

Console admin → realm **homelab** (sélecteur en haut à gauche, pas `master`) → Users → Add user → Credentials (mot de passe) → Groups.
Donner `homelab-admins` aux administrateurs, rien de plus aux autres (ils sont dans `homelab-users`).

## Limites actuelles (à connaître)

- **HTTP uniquement, pas de TLS** : les mots de passe circulent en clair sur ton réseau local. Acceptable à la maison, à corriger avant toute exposition (cert-manager, voir [08](08-prochaines-etapes.md)). Pour que la console admin fonctionne en HTTP, le rôle met `sslRequired=NONE` sur le realm `master` ([post.yml](../roles/platform/tasks/post.yml)) : à retirer quand TLS sera en place.
- Keycloak n'importe son realm qu'au **premier démarrage**. Modifier le realm dans le dépôt ne change pas un Keycloak existant (sauf l'ajout de clients, géré par Ansible).
- Keycloak tourne en 1 réplique avec Postgres local (`local-path`) : pas de haute dispo. Penser aux sauvegardes (`pg_dump`).
- Le compte `admin` initial est un compte de bootstrap : pour de l'usage durable, créer un vrai admin nominatif dans le realm `master`.
