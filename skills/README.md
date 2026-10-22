# skills/ — agent skills for this repository

This directory is the **single source of truth** for the AI-agent skills that
teach a coding agent how to work in this repo. Each skill is a folder with a
`SKILL.md` in the open [Agent Skills](https://agentskills.io) format, which
Claude Code, OpenAI Codex, Kiro, Cursor, GitHub Copilot, Gemini CLI and
others can load.

| Skill | What it teaches |
| --- | --- |
| [`create-customization`](create-customization/SKILL.md) | Scaffold and implement a new `CUST-*` directory end to end |
| [`write-api-helpers`](write-api-helpers/SKILL.md) | Rules and patterns for `pre-/post-api-helpers.sh` and python helpers |
| [`validate-customization`](validate-customization/SKILL.md) | Run the validator and fix what it reports |

## How agents find these skills

Agents look for project skills in their own folder. Instead of maintaining
copies, those folders are **symlinks back to this directory**:

| Agent | Looks in | Committed link |
| --- | --- | --- |
| Claude Code | `.claude/skills/` | yes |
| Codex CLI, Gemini CLI, Cursor, Copilot (shared convention) | `.agents/skills/` | yes |
| Kiro | `.kiro/skills/` | yes |
| Cursor (native) | `.cursor/skills/` | on demand |
| GitHub Copilot (native) | `.github/skills/` | on demand |
| Gemini CLI (native) | `.gemini/skills/` | on demand |
| Codex CLI (older builds) | `.codex/skills/` | on demand |

Create or refresh links with:

```bash
scripts/link-skills.sh            # claude + .agents + kiro (the committed set)
scripts/link-skills.sh all        # every agent directory above
scripts/link-skills.sh --copy all # copies instead of symlinks (no-symlink environments)
scripts/link-skills.sh --list     # show the table
```

Agents without native skill support still get the content: `AGENTS.md`
(read by most agents; `CLAUDE.md` includes it) tells the agent to open
`skills/<name>/SKILL.md` when the task matches.

Discovery paths change between agent releases. If an agent does not pick the
skills up, check its current docs for the project-skills folder and add it to
`agent_dir()` in `scripts/link-skills.sh`.

## Skill format

```markdown
---
name: my-skill              # must equal the folder name; lowercase, dashes
description: One or two sentences saying WHAT it does and WHEN to use it.
              Agents match on this text, so include trigger words.
---

# Title

Instructions the agent follows once the skill is loaded. Keep it to the
procedure, the rules, and a checklist. Link to files in the repo rather than
restating them.
```

Optional subfolders: `scripts/` (runnable helpers), `references/` (longer
docs loaded on demand), `assets/` (templates).

## Adding or changing a skill

1. Create `skills/<name>/SKILL.md` with the frontmatter above.
2. Keep it short and procedural; put long reference material in
   `references/` and link to it.
3. Run `scripts/validate-customization.sh` (it checks skill frontmatter and
   that the agent links resolve).
4. Mention the skill in `AGENTS.md` so agents without skill support know it
   exists.

Because the agent folders are symlinks, no copying is needed; every agent
sees the change immediately.

## Repurposing this repo

If you clone this as the starting point for your own customizations repo,
keep `skills/` and the links, then edit the three skills to reflect your
own conventions (naming, required tags, approved regions, review process).
`AGENTS.md` is the place for always-on rules; skills are for on-demand
procedures.
