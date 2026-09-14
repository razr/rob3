# ROB3 Copilot Instructions

Use the skills under `.github/skills/` for repository-specific guidance. They are
mirrored from the canonical Kiro sources in `.kiro/skills/`.

The canonical project lessons are in `.kiro/steering/rob3-lessons-learned.md`.
Keep firmware claims tagged `[BYTE]`, `[SIM]`, `[HW]`, or `[INFER]` according to
the provenance rules in that file.

To refresh the Copilot mirror after changing a Kiro skill, run:

```sh
./scripts/sync-skills.sh
```

Do not edit `.github/skills/` directly. Edit `.kiro/skills/` and run the sync
script. The mirrored files are committed so Copilot can discover them in the
repository.
