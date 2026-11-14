# Rôle `platform`

Prépare ce dont Keycloak et Argo CD ont besoin **avant** leur déploiement Helm :
- DNS interne : `*.homelab_domain` → Traefik (ConfigMap `coredns-custom`)
- Namespaces `keycloak` et `argocd`
- Secrets (admin, base de données, realm importé) à partir des mots de passe générés dans `.secrets/`
- Postgres pour Keycloak (StatefulSet, 2 Go local-path)
- `tasks/post.yml` (après Helm) : autorise l'admin Keycloak en HTTP et crée les clients OIDC manquants

Tutoriel : [../../docs/11-argocd-keycloak.md](../../docs/11-argocd-keycloak.md).
