# ren-ai-skills

Personal Claude Code skills for the `sudo/` workspace (etch, sudo-terraform, etc.).

Each skill lives in `skills/<skill-name>/` and follows the [Anthropic skill conventions](https://docs.claude.com/en/docs/agents-and-tools/agent-skills): a `SKILL.md` with YAML frontmatter (`name`, `description`) plus optional supporting files.

## Skills

- **backlog-management** — Beads ↔ Linear sync model, Linear cleanup, epic description summarisation. Keeps Linear as a curated stakeholder view while beads holds implementation detail.

## Using locally

Skills are loaded by Claude Code from `~/.claude/skills/`. To activate a skill from this repo, symlink it:

```bash
ln -s "$PWD/skills/backlog-management" ~/.claude/skills/backlog-management
```

Or check the whole repo out as a sibling of your other workspaces and symlink each skill directory individually.

## Contributing

New skills should start with `superpowers:writing-skills` / `skill-creator` guidance: a clear "Use when…" description, keyword-rich body, and concrete examples. Keep them small and reference-style where possible.
