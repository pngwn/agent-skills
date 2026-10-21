# agent-skills

A collection of [Agent Skills](https://agentskills.io): folders of instructions, scripts and resources that agents can load to do specific tasks better.

## Layout

```
skills/
  <skill-name>/
    SKILL.md        # required: frontmatter + instructions
    scripts/        # optional: helper scripts the skill can run
    references/     # optional: docs loaded on demand
    assets/         # optional: templates, images, other files
template/
  SKILL.md          # starting point for new skills
```

## Adding a skill

1. Copy the template into a new folder under `skills/`. The folder name should match the skill's `name`.

   ```bash
   cp -r template skills/my-skill
   ```

2. Edit `skills/my-skill/SKILL.md`:
   - `name`: lowercase letters, numbers and hyphens, matching the folder name.
   - `description`: what the skill does and when to use it. This is what agents read to decide whether to load it.
3. Keep `SKILL.md` focused. Move long reference material into `references/` and link to it.

## Using these skills

Copy or symlink a skill folder into your agent's skills directory, for example `~/.claude/skills/` for Claude Code:

```bash
ln -s "$(pwd)/skills/my-skill" ~/.claude/skills/my-skill
```

## License

[MIT](LICENSE)
