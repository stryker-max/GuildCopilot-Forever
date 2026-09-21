# Forever project workflow

- This is the independent GuildCopilot-Forever project, derived from TBC 0.9.142.
- Never write or publish into stryker-max/GuildCopilot or the Anniversary installation.
- Addon identity: GuildCopilotForever. SavedVariables: GuildCopilotForeverDB.
- The user-facing addon name is Guild Copilot. Keep /gcp as the primary command and /guildcopilot as its alias. The repository name and internal Forever identifiers do not change the product name.
- The installation target is _classic_beta_/Interface/AddOns/GuildCopilotForever only.
- Verify the exact source/target paths and every installed file by SHA-256.
- Never modify WTF/SavedVariables files. Never package development tools into AddOns.
- Run npm ci and npm test; include a CHANGELOG and ROADMAP entry for every change.
- This repository has tests/artifact builds only. No automatic CurseForge publication.
- Report client restrictions honestly. Never evaluate secret values or bypass restricted APIs.
