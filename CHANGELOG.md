# Änderungen

## 0.1.0-beta.3 – 21.09.2026

- Den bestehenden Produktnamen **Guild Copilot** in Addon-Liste, Fenster, Einstellungen, Chat, Hilfetexten und Übersetzungen wiederhergestellt.
- Der Hauptbefehl bleibt **`/gcp`**, der ausgeschriebene Alias **`/guildcopilot`**. Dokumentation und bestehende Prüfungen entsprechend korrigiert.
- Forever-Repository, interner Namensraum, SavedVariables und Installationsziel bleiben technisch getrennt; der sichtbare Produktname hängt nicht vom Repository-Namen ab.

## 0.1.0-beta.2 – 21.09.2026

- Forever-Talente über öffentliche `C_Traits`-Talentgruppen und Punktekosten auslesen, nach Gruppen-ID zuordnen und nach Client-Reihenfolge sortieren. Eigene und Inspect-Daten funktionieren auch mit wenigen Punkten; Gleichstand, geheime Werte und unbestätigte Änderungen werden nicht als eindeutige Spezialisierung veröffentlicht.
- Vollständige Vor-/Nachnamen mit dem vom Client gelieferten Trennzeichen verwenden; keine erfundenen Realmzusätze und keine Kürzung von Herstelleridentitäten. Rezept-, Schlüssellisten- und Abklingzeitpakete berücksichtigen lange Namen und die 255-Byte-Grenze.
- Berufs-Hauptpfad und aktuelle Fertigkeitsränge an die Forever-Berufsübersicht angepasst; unbestätigte Juwelenschleifen-Auswahl entfernt. Herstellungsfehler werden korrekt gemeldet.
- Client-Sendesperren vor direktem Versand und Übergabe an ChatThrottleLib beachten; Warteschlangen pausieren ohne Fehlversuche zu verbrauchen.
- Große Rezeptdatensätze werden über mehrere Pakete übertragen, statt Reagenzien zu entfernen. Die neuen FD/FC-Transfers setzen beta.2 auf Sender und Empfänger voraus; bisherige C/D-Transfers bleiben lesbar.
- Leeren Gildenfortschritt statt „SSC/TK“ vorgeben. Diagnose zeigt vollständigen Namen, Talentdaten und die Level-60-Grenze der Raiderliste.
- Forever-Quellenbasis und Spielabnahme aktualisiert; Regressionstests für Namen, Talentgruppen, Berufsränge, Sendesperren, Herstellungsfehler und Paketgrößen ergänzt. Eigenes Addon-ZIP für die direkte Installation unter `_classic_beta_/Interface/AddOns/GuildCopilotForever`.

## 0.1.0-beta.1 – 21.09.2026

- Eigenständige Forever-Fassung auf Basis von TBC Guild Copilot 0.9.142 (`71e650473b90e7d39ae4b814678ce64abe8c694a`).
- Getrenntes Repository, Addon-Verzeichnis, Versionsschema, Lua-Namensraum, Slash-Befehle, SavedVariables und Sync-Präfix.
- Anpassung an Forever 1.60.1.69913: Item-/Spell-/Skill-APIs, Talentabfragen und Berufsereignisse.
- Lange Spielernamen einschließlich Realm bleiben auch bei Aufträgen, Reservierungen und deren Synchronisierung vollständig erhalten.
- Realmqualifizierte Spielerzuordnung; Schutz vor der Auswertung geschützter Werte; Ausrüstungsprüfungen nach dem Kampf.
- TBC-Kampflog-Auswertung, TBC-Regelsätze, Raidvorgaben und externe TBC-Importe für Forever entfernt oder ausdrücklich als nicht verfügbar gekennzeichnet.
- Eigenes reproduzierbares Addon-Paket, API-Vertragstests und GitHub-Testworkflow ohne TBC-Veröffentlichungskonfiguration.
