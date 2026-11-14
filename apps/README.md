# apps/

`values/<app>.yml` = la configuration Helm de chaque application (les « values » du chart).
Un fichier par app, référencé par `values_file:` dans `inventory/group_vars/k3s_server.yml`.

Voir toutes les options d'un chart : `helm show values <repo>/<chart>`.
Ne mets **pas** de mot de passe en clair ici (voir [../docs/08-prochaines-etapes.md](../docs/08-prochaines-etapes.md)).
Tutoriel : [../docs/04-ajouter-une-application.md](../docs/04-ajouter-une-application.md).
