# Plugin KohaLa Abes WS

**Abes WS** est un plugin Koha qui permet d'exploiter depuis Koha des services
web de l'ABES. L'intégration à Koha de services web de l'ABES vise deux
objectifs distincts et complémentaires :

- **Contrôles rétrospectif** — Des listes d'anomalies de catalogage sont
  affichées. À partir de ces listes, des opérations de correction peuvent être
  lancées.

- **Enrichissement de l'affichage** — L'affichage des notices dans Koha est
  enrichies de données récupérées en temps réel à l'Abes.

Ce plugin a été conçu et développé lors d'un atelier _Services web de
l'[Abes](https://abes.fr)_ qui s'est tenu lors du Hackathon 2021 de
l'association [KohaLa](http://koha-fr.org) des utilisateurs français de Koha.

![Abes](https://raw.githubusercontent.com/fredericd/Koha-Plugin-KohaLa-AbesWS/master/Koha/Plugin/KohaLa/AbesWS/img/logo-abes.svg)
![KohaLa](https://raw.githubusercontent.com/fredericd/Koha-Plugin-KohaLa-AbesWS/master/Koha/Plugin/KohaLa/AbesWS/img/logo-kohala.png)

## Installation

**Activation des plugins** — Si ce n'est pas déjà fait, dans Koha, activez les
plugins. Demandez à votre prestataire Koha de le faire, ou bien vérifiez les
points suivants :

- Dans `koha-conf.xml`, activez les plugins.
- Dans le fichier de configuration d'Apache, définissez l'alias `/plugins`.
  Faites en sorte que le répertoire pointé ait les droits nécessaires.

**📁 TÉLÉCHARGEMENT** — Récupérez sur le site [Tamil](https://www.tamil.fr)
l'archive de l'Extension **[KohaLa Abes
WS](https://www.tamil.fr/download/koha-plugin-kohala-abesws-1.0.2.kpz)**.

Dans l'interface pro de Koha, allez dans `Outils > Outils de Plugins`. Cliquez
sur Télécharger un plugin. Choisissez l'archive **téléchargée** à l'étape
précédente. Cliquez sur Télécharger.

## Utilisation du plugin

### Configuration

Dans les Outils de plugins, vous voyez l'Extension *KohaLa Abes WS*. Cliquez sur
Actions > Configurer.

Quatre sections pilotent le fonctionnement du plugin :

- **Accès aux WS** — Paramètres d'accès aux services web.

- **Établissement** — L'ILN et les RCR de l'ILN. Les services web ne seront
  interrogés que pour cet ILN et ces RCR.

- **bibliocontrol**

- **Page détail**

### Bibliocontrol

### AlgoLiens

### Page de détail


## VERSIONS

* **1.0.1** / avril 2021 — Version initiale

## LICENCE

This software is copyright (c) 2021 by Tamil s.a.r.l..

This is free software; you can redistribute it and/or modify it under the same
terms as the Perl 5 programming language system itself.

