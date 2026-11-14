# 12. OpenBao (gestion des secrets)

OpenBao stocke les secrets du homelab (mots de passe, clés d'API, certificats…) et y donne accès de façon contrôlée.
Connexion par **SSO Keycloak** : même compte `michou` que pour Argo CD.

| | |
|---|---|
| Interface | http://openbao.homelab.local (ajouter le nom dans `/etc/hosts`, voir [11](11-argocd-keycloak.md)) |
| Connexion | méthode **OIDC** → bouton « Sign in with OIDC Provider » (rôle `homelab`) |
| Droits | groupe Keycloak `homelab-admins` → **admin** ; autres utilisateurs connectés → **lecture** de `secret/` |
| Stockage | raft intégré, 1 réplique, volume 2 Go (`local-path`) |
| Moteur de secrets | KV v2 monté sur `secret/` |

## Pourquoi OpenBao plutôt que Vault ?

**Décision : OpenBao** (14 novembre 2026). Raisons, par ordre d'importance :

1. **Licence open source.** OpenBao est sous **MPL 2.0** (open source au sens OSI). Vault est sous **BUSL 1.1** depuis août 2023 (v1.15) : code lisible, mais pas open source, avec une clause qui interdit d'en faire un produit/service concurrent de HashiCorp.
2. **Aucun risque pour un usage commercial futur.** Avec MPL 2.0 on peut utiliser, héberger ou embarquer OpenBao sans se demander si on « concurrence » quelqu'un. Avec BUSL, la notion de concurrent est floue et peut devenir un sujet si le homelab évolue en activité (services pour des clients, produit autour des secrets…).
3. **Gouvernance indépendante.** OpenBao est un projet de la Linux Foundation, pas d'un éditeur unique ; HashiCorp appartient désormais à IBM, ce qui peut changer la licence ou la politique de produit.
4. **Aucune perte pour notre usage.** OpenBao est un fork de Vault 1.14 (dernière version MPL) : mêmes concepts (scellement/descellement, KV, policies, identités), même API HTTP, **même méthode d'authentification OIDC** pour Keycloak, chart Helm proche. Les fonctions qui manquent sont surtout celles de Vault *Enterprise* (réplication…), inutiles sur un seul nœud.
5. **Réversible.** L'API étant compatible, les apps et les outils (CLI `bao` ≈ `vault`, External Secrets Operator…) se branchent de la même manière : changer plus tard est un travail limité.

**Inconvénients assumés :**
- Projet communautaire : pas de support commercial officiel, moins d'articles/tutoriels (mais la plupart de la doc Vault s'applique).
- Les deux projets divergent depuis 2023 : certaines fonctions récentes de Vault n'existent pas (et inversement).
- Migrer des **données** d'un Vault récent vers OpenBao n'est pas garanti ; on part donc de zéro ici, ce qui est notre cas.

> Ce choix repose sur mes connaissances au moment de la décision ; les détails de licence et de fonctions évoluent : relire les sites des deux projets avant un usage commercial sérieux.

## Ce que fait Ansible (`make apps`)

1. Helm déploie le chart `openbao/openbao` ([apps/values/openbao.yml](../apps/values/openbao.yml)).
2. Le rôle [openbao](../roles/openbao/tasks/main.yml) :
   - **initialise** OpenBao s'il ne l'est pas (1 part de clé, seuil 1) ;
   - enregistre la **clé de déscellement et le token root** dans `.secrets/openbao_init.json` (ignoré par git, droits 600) ;
   - **descelle** OpenBao ;
   - configure KV `secret/`, les policies `homelab-admin` / `homelab-reader`, l'auth OIDC Keycloak et le groupe `homelab-admins` ([configure.sh.j2](../roles/openbao/templates/configure.sh.j2)).
3. Le client OIDC `openbao` est créé dans Keycloak par le rôle `platform`.

La clé et le token ne passent jamais dans la ligne de commande (ils sont envoyés par l'entrée standard) et les tâches sont en `no_log`.

## Redémarrage : OpenBao reste scellé !

À chaque redémarrage du pod ou du serveur, OpenBao démarre **scellé** (par conception : les données sont illisibles tant qu'on ne fournit pas la clé). Les apps ne peuvent plus lire de secrets tant que ce n'est pas fait :

```bash
make unseal     # relit .secrets/openbao_init.json et descelle (idempotent)
```
Vérifier : `ssh tour 'sudo k3s kubectl -n openbao exec openbao-0 -- env BAO_ADDR=http://127.0.0.1:8200 bao status'` → `Sealed false`.

**Compromis de sécurité (à connaître)** : la clé de descellement et le token root sont stockés ensemble, en clair, sur ton PC. C'est pratique pour un homelab, mais quiconque a ce fichier a accès à tous les secrets. Pour durcir : plusieurs parts de clé (`openbao_key_shares: 5`, seuil 3) réparties dans un gestionnaire de mots de passe, ou un descellement automatique (auto-unseal via un KMS/transit).

## Sauvegarde (à faire !)

| Quoi | Comment |
|---|---|
| `.secrets/` (surtout `openbao_init.json`) | copie chiffrée dans ton gestionnaire de mots de passe |
| Données OpenBao | `ssh tour` puis `sudo k3s kubectl -n openbao exec openbao-0 -- env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN=<root> bao operator raft snapshot save /tmp/snap` puis `kubectl cp` |

Sans `openbao_init.json`, les données sont **définitivement perdues** (c'est le but du chiffrement).

## Utilisation

### Se connecter

- **Interface** : http://openbao.homelab.local → méthode **OIDC**, rôle `homelab` (déjà par défaut) → compte `michou`.
- **CLI** (si tu installes `bao` en local) :
  ```bash
  export BAO_ADDR=http://openbao.homelab.local
  bao login -method=oidc role=homelab      # ouvre le navigateur sur Keycloak
  ```

### Stocker et lire un secret

```bash
bao kv put secret/monapp/db user=app password=xxxx
bao kv get secret/monapp/db
```
Dans l'interface : Secrets → `secret/` → Create secret.

### Token root

Le token root (dans `openbao_init.json`) ne sert qu'à la configuration initiale et à la réparation. Le quotidien se fait en SSO. Quand tout est stable, on peut le révoquer (`bao token revoke`) et le régénérer au besoin avec `bao operator generate-root`.

### Brancher des applications Kubernetes (plus tard)

Pas encore installé. Option recommandée : **External Secrets Operator** (lit OpenBao, crée des `Secret` Kubernetes). Voir [08](08-prochaines-etapes.md). L'authentification Kubernetes d'OpenBao (`auth/kubernetes`) sera alors activée.

## Limites actuelles

- **HTTP sans TLS** : les secrets circulent en clair entre ton navigateur et OpenBao sur le réseau local. À corriger avec TLS (cert-manager) avant tout usage sérieux.
- 1 seule réplique : pas de haute disponibilité.
- L'interface web utilise l'URL de callback `/ui/vault/auth/oidc/oidc/callback` (héritée de Vault). Le flux complet a été testé par API (login Keycloak → callback → policies), **pas dans un vrai navigateur**.
- Le pod est considéré « prêt » même scellé (réglage voulu, voir `readinessProbe` dans les values) : un pod `Running 1/1` ne garantit donc pas qu'OpenBao est descellé.
