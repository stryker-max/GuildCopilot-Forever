# Guild Copilot 0.1.0-beta.5

Eigenständige Portierung von [Guild Copilot für TBC Anniversary](https://github.com/stryker-max/GuildCopilot) für **World of Warcraft: Forever Beta 1.60.1.69913**, Interface **16001**.

## Installation

1. Das Paket `GuildCopilotForever-0.1.0-beta.5.zip` entpacken.
2. Den darin enthaltenen Ordner `GuildCopilotForever` nach `World of Warcraft/_classic_beta_/Interface/AddOns/` kopieren.
3. Den WoW-Client vollständig neu starten, wenn das Addon neu hinzugefügt wurde. In der Addon-Liste **Guild Copilot** aktivieren.
4. Im Spiel mit **`/gcp`** öffnen. **`/gcp client`** zeigt Client, Addon-Version, Datenbank und Sync-Kanal; **`/gcp ver`** zeigt die Versionen in der Gilde/Gruppe.

Quellcode, Tests und Entwicklungswerkzeuge gehören nicht in den AddOns-Ordner. Der TBC-Installer ist für diese Fassung nicht geeignet.

## Zwei eigenständige Projekte

| | TBC Anniversary | Forever Beta |
|---|---|---|
| Repository | `stryker-max/GuildCopilot` | `stryker-max/GuildCopilot-Forever` |
| Addon-Ordner | `GuildCopilot` | `GuildCopilotForever` |
| Spielordner | `_anniversary_` | `_classic_beta_` |
| Befehl | `/gcp` | `/gcp` |
| Globale Addon-Tabelle | `GuildCopilot` | `GuildCopilotForever` |
| SavedVariables | `GuildCopilotDB` | `GuildCopilotForeverDB` |
| Sync-Präfix | `GuildCopilot` | `GCPForever` |

Keine automatische Übernahme von TBC-Daten. Die Forever-Fassung enthält weder den TBC-Installer noch dessen Updatepfad oder CurseForge-Veröffentlichungsworkflow. GitHub Actions führt Tests aus und stellt das ZIP als Build-Artefakt bereit; es veröffentlicht nichts auf CurseForge.

## Funktionsumfang der ersten Beta

- Gildenprofil, Mitgliederübersicht, manuell bestätigte Raidprofile, Berufe und Abmeldungen.
- Rekrutierungstexte, Bewerberpostfach, Antworten und Einladungen.
- Werkstatt mit bekannten Rezepten, Reagenzien, Beständen, Herstellern und Gildenaufträgen.
- Frei konfigurierbare Gruppen-/Raidsuche, ohne unbestätigte TBC-Instanzvorgaben.
- Ausrüstung erfassen und synchronisieren; gildenweit gepflegte Verzauberungsregeln.
- Raidvorbereitung mit **`/gcp raidcheck`**: letzte Momentaufnahme der lesbaren Gruppen-Buffs und eigenen mitgeführten Verbrauchsgegenstände. [Bedienung und Grenzen](docs/RAID-VORBEREITUNG.md).
- Vollständige zweiteilige Forever-Namen für Profile, Rechte, Hersteller und Aufträge; das Trennzeichen liefert der Client.
- Talentgruppen und ausgegebene Punkte aus der Forever-Talentoberfläche, einschließlich niedriger Level und verfügbarer Inspect-Daten.

Forever verwendet regionale Charakternamen und Regelsets statt der bisherigen Realm-Auswahl. Die angekündigte Zielstufe ist 60; die erste Beta-Testphase beginnt mit Stufe 20. Die Raiderliste filtert weiterhin auf Stufe 60 und kann deshalb während der Beta leer bleiben. Quellen und API-Abgleich stehen in [docs/FOREVER-GRUNDLAGE.md](docs/FOREVER-GRUNDLAGE.md).

## Bewusste Einschränkungen

- **Keine Verbrauchszähler aus dem Kampflog.** Die vom TBC-Addon verwendete öffentliche Schnittstelle ist im geprüften Forever-Build nicht verfügbar. Die Raidseite erfasst Vorbereitung; aktive Effekte oder Bestandsabnahmen beweisen keinen Verbrauch. Nicht lesbare Mitglieder gelten als unbekannt.
- **Keine TBC-BiS- oder Pflichtverzauberungsbewertungen.** Ausrüstung wird erfasst; ein belastbarer Forever-Regelsatz liegt noch nicht vor. Unbewertete Verzauberungen gelten standardmäßig als unbekannt. Gilden können eigene Regeln für vorhandene Verzauberungen pflegen.
- **Kein Warcraft-Logs-Import und keine TBC-Armory-Links.** Der bisherige Companion/Installer und dessen TBC-Datenmodell werden nicht mitgeliefert.
- Berufs- und Gildenbankfunktionen hängen von den im jeweiligen Beta-Build freigeschalteten Spielsystemen ab. Es werden keine Blizzard-API-Beschränkungen umgangen.
- SavedVariables werden regulär von WoW gespeichert. Ein im Beta-Client auftretender Speicher-/Wiederherstellungsfehler kann durch diese Portierung nicht behoben werden. Ein Wiederanmelden nach `/reload` und vollständigem Neustart gehört zur Abnahme.

## Validierung

Im Bewerberpostfach zeigt die Kopfzeile, ob Erkennungswörter eingerichtet sind. Neue Interessenten werden gemäß diesen Einstellungen aufgenommen; bekannte Unterhaltungen bleiben auch nach Ende der Suche aktiv. Private Folgetexte bleiben lokal. Antworten über 255 Bytes oder vom Client abgewiesene Aufrufe behalten den Entwurf; „an den Client übergeben“ bestätigt keine Serverzustellung.

Für vollständige Rezeptabgleiche müssen Sender und Empfänger **beta.2 oder neuer** verwenden. Große Rezepte werden vollständig über mehrere Nachrichten übertragen; beta.1 versteht dieses neue Format noch nicht.

Geprüft anhand der [Blizzard-UI-Quellen für genau Build 69913](https://github.com/Gethe/wow-ui-source/tree/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e). Automatisierte API-Vertragstests simulieren fehlende Classic-APIs, moderne Rückgabeformate, geschützte Werte, Start und alle Hauptseiten, Berufe, Aufträge, Sync und die Trennung vom TBC-Addon. Das ZIP wird auf Inhalt, Bytegleichheit zur Quelle und reproduzierbaren Aufbau geprüft.

**Diese Tests ersetzen keinen Test im laufenden WoW-Client mit mehreren Spielern.** Die Checkliste dafür steht in [docs/BETA-ABNAHME.md](docs/BETA-ABNAHME.md).

## Entwicklung

```sh
npm ci
npm test
npm run package
```

Optional dieselben Lua-Tests unter echtem Lua 5.1:

```sh
GCP_LUA51=lua5.1 npm run test:lua
```

Ausgabe: `build/GuildCopilotForever-0.1.0-beta.5.zip` und `build/SHA256.json`. Lizenz: MIT, ursprüngliche Urheberschaft des Guild Copilot Teams bleibt erhalten.
