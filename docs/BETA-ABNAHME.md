# Prüfung im laufenden Spiel

Ziel: WoW Forever Beta 1.60.1.69913. Automatisierte Tests laufen außerhalb des Spiels und bestätigen keine Server- oder Mehrspielerfunktion.

1. WoW nach der Erstinstallation vollständig neu starten. In der Addon-Liste steht **Guild Copilot 0.1.0-beta.4**.
2. `/gcp client`: Interface 16001, Datenbank `GuildCopilotForeverDB`, Präfix `GCPForever`. `/gcp` öffnet das Hauptfenster; alle Seiten durchsehen.
3. Profil bestätigen, Fenster verschieben und eine Einstellung ändern. `/reload`, Ab-/Anmelden und vollständigen Client-Neustart prüfen. Bleiben die Werte erhalten? Falls nicht, zuerst den SavedVariables-Zustand des Beta-Clients prüfen; keine WTF-Dateien löschen.
4. Mit einem zweiten Gildenmitglied desselben Regelsets, derselben Fraktion und Addon-Version `/gcp ver` prüfen. Profile, Abmeldungen und Rezeptkataloge abgleichen. Vorname und Nachname müssen vollständig mit der Clientanzeige übereinstimmen; gleicher Vorname mit anderem Nachnamen muss getrennt bleiben. Auch Weiterleitung von Rezepten und Abklingzeiten prüfen.
5. Berufsfenster öffnen, Berufsrang, Rezept, Materialzahl und tatsächliche Ausbeute vergleichen, neues Rezept lernen. Die Werkstatt muss sich aktualisieren. Herstellen über den vorgesehenen Klick prüfen; eine abgewiesene API darf keinen Erfolg melden. Mehrfachausbeute und optionale Reagenzien gesondert prüfen.
6. Ein Gildenmitglied erstellt einen Auftrag, ein anderes nimmt ihn an und meldet Fertigung/Übergabe. Menge, Materialmodell und Nachrichten müssen übereinstimmen.
7. Gruppensuche mit frei gewählter Instanz testen; Rekrutierungstext bewusst per Klick posten, Antwort und Einladung prüfen.
8. Ausrüstung vor und nach einem Gegenstandswechsel prüfen. Im Kampf darf keine blockierte Inspect-Aktion oder Fehlermeldung ausgelöst werden; nach Kampfende aktualisiert sich die eigene Prüfung.
9. `/gcp raidcheck` außerhalb des Kampfes: lesbare hilfreiche Effekte mit dem Spiel vergleichen, eigene Verbrauchsvorräte mit den Taschen vergleichen. Offline/entfernte Mitglieder müssen unbekannt bleiben. Im Kampf oder laufenden Bossversuch muss der Check ablehnen und die letzte Momentaufnahme erhalten. Nach `/reload` muss sie erhalten bleiben. Es gibt keine Verbrauchszähler, Warcraft-Logs-Seite oder TBC-Pflichtbuffliste.
10. Talente schon unter Level 30 prüfen: eigene Punkte, bestätigtes Umskillen und Inspect eines Gruppenmitglieds. Ein unbestätigter Talententwurf darf nicht veröffentlicht werden. Fehlende oder gesperrte Daten dürfen keine Spezialisierung erfinden.
11. Während einer Client-Sendesperre darf eine Warteschlange keine Pakete verlieren; nach Freigabe muss sie fortsetzen. Anschließend Profil- und Rezeptabgleich erneut prüfen.
12. Eine leere Raiderliste bei Charakteren unter Stufe 60 ist erwartbar. Mitgliederzahl, eigene Profildaten und bekannte Profile getrennt prüfen; `/gcp client` erklärt die Grenze.
13. Postfach: ein Whisper-Erkennungswort (z. B. „gilde“) einrichten und Suchwerbung starten. Ein zweiter Spieler schickt einen passenden Whisper. Nach Suchende muss seine weitere Antwort weiterhin ankommen, auch bei aktiver Raidsuche. Neue unbekannte Interessenten müssen die Einstellung „nur während Suche“ weiterhin beachten. Ohne Erkennungswörter muss der Hinweis sichtbar sein.
14. Antworten aus dem Postfach: vollständige Namen, Umlaute und Entwürfe prüfen. Ein gesperrter/abgewiesener Versand oder eine Antwort über 255 Bytes darf den Entwurf nicht löschen. Erfolg bedeutet nur Übergabe an den Client; Zustellung beim zweiten Spieler kontrollieren. Einladungen ohne Gildenrecht dürfen keinen falschen Erfolg melden, soweit die API die Ablehnung zurückgibt.
15. Postfach zwischen zwei Gildenmitgliedern synchronisieren: ursprüngliche Bewerbung und Aktivitätszeitpunkt abgleichen, private Folgetexte dürfen nicht übertragen werden. Gelöschte/ignorierte Bewerber dürfen durch erneuten Sync nicht wiederkehren. Nach `/reload` und Neustart müssen die verbleibenden Einträge erhalten bleiben.

Bei Fehlern: erste vollständige Lua-Fehlermeldung, auslösende Aktion und Ausgabe von `/gcp client` festhalten. Die ersten Schritte ohne zusätzliche Addons gegenprüfen, falls ein Addon-Konflikt vermutet wird.
