Intégration Continue (CI) avec Package check pour l'ensemble des applications YunoHost
==================

[Yunohost project](https://yunohost.org/#/)

**Avant d'utiliser ces scripts, lisez bien ce qui suit. Ceci est destiné à être utilisé sur un serveur dédié à cette tâche.**

Ensemble de scripts pour déployer les scripts d'intégration continue avec Jenkins sur l'ensemble des applications YunoHost.

Ce script nécessite une Debian Jessie avec ou sans YunoHost. Qui sera installé le cas échéant.
Puis jenkins sera installé et un job sera créé pour chaque application fonctionnelle dans les listes officielles et communautaires.
Chaque nuit, des jobs sont ajoutés ou supprimés en fonction de l'état des listes d'applications.

**Toutefois, le script ne prend pas en charge les hooks Github qui doivent être mis en place manuellement**
**Adresse de payload: https://domain.tld/jenkins/github-webhook/**
