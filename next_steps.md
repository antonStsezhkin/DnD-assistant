# Next Steps

## Where things stand

| Layer | Status |
|-------|--------|
| Rulebook ingestion → Markdown chunks | Done |
| SQLite schema (effects, resist model, all tables) | Done, empty |
| DB population | Not started |
| Calculation engine | Not started |
| Custom rulebook / campaign extension system | Not started |

---

## Recommendation: wiki first. You are right.

Building tools before the DB has data is building on air.
The populated DB will tell you exactly what the tools need to calculate.
Start tools too early and you will redesign them three times.

---

## The actual next step: DB population pipeline

You need a script that feeds rulebook chunks to llama 8b and writes the results to `dnd.db`.

### How to approach it

1. **One entity type at a time.** Start with the simplest table (`damage_types`, `conditions`, `weapon_properties`) to validate that llama can produce clean output at all. Then move to `weapons` → `armor` → `spells` → `creatures` → `classes`.

2. **Give llama a strict output format.** Llama 8b is not smart. Do not ask it to write SQL. Ask it to return JSON that matches a known schema, then you write the SQL. Example prompt structure:

   ```
   You are a data extractor. Read the following D&D rulebook excerpt and extract
   all WEAPONS into this exact JSON format. Return only the JSON array, no prose.

   Schema: [paste relevant columns]
   Text: [chapter content]
   ```

3. **Map chapters to entity types before running anything.** The chapter filenames already tell you what's in them. Build a simple routing table:
   - `*weapon*` → extract weapons
   - `*spell*` → extract spells  
   - `*armor*` → extract armor
   - `*creature*` / `*monster*` / `*beast*` → extract creatures
   - etc.

4. **Effects are the hard part.** Weapons, spells, and creature actions all need their effects extracted and linked. Do this in a second pass after the main entities are in — ask llama to re-read the same chunk but focus only on the mechanical effect (dice, type, conditions, saves).

5. **Validate as you go.** After each entity type is populated, run a few sanity queries:
   - Do all weapons have at least one effect?
   - Do all spells have a school and level?
   - Are there creatures with no actions?

### Files to create

- `app/db/populate.py` — orchestrator: walks `rulebooks/`, routes chapters, calls llama, writes to DB
- `app/db/prompts.py` — prompt templates per entity type (keep them separate so they are easy to tune)
- `app/db/extractors.py` — JSON → SQL insert functions per entity type (validate & clean llama output)

---

## After the wiki: calculation tools

Once the DB has real data, implement these in order of dependency:

1. **Dice roller** — `roll("2d6+3")` → integer. Everything else calls this.
2. **Effect resolver** — given an effect + attacker stats + target resist → final value. This is `(1 - resist) * (roll(base_dice) + flat + ability_mod)`.
3. **Attack resolver** — d20 + to_hit_bonus vs AC → hit/miss/crit, then call effect resolver.
4. **Spell resolver** — casting time check, slot cost, then effect resolver per target.
5. **Encounter builder** — pick creatures by CR, build a fight, run it.

---

## Campaign architecture (decided)

Single database. Campaigns do not duplicate data — they compose sources.

```
sources          campaigns
────────         ─────────
phb_5e    ◄──── campaign_sources (priority=0)  ← Lost Mine of Phandelver
my_brew   ◄──── campaign_sources (priority=10) ← same campaign
```

- **Iron Sword / Goblin / Pegasus** live in `phb_5e`. Every campaign including that source gets them — no copies.
- **Dronkey** lives in `my_brew`. Both Pegasus and Dronkey exist in the campaign — they have different names, so priority is irrelevant. Priority only matters when two sources define the **same name**.
- **Override** (e.g. "Fireball does 10d6 in this campaign"): add a `my_brew` row named "Fireball" at priority=10. The lookup `ORDER BY priority DESC LIMIT 1` picks it over the PHB version.
- **Exclude** (e.g. "no goblins in this campaign"): insert into `campaign_exclusions (campaign_id, entity_type='creature', entity_name='Goblin')`. The engine checks this table before returning any entity. The source still includes goblins — the exclusion is a campaign-level ban.
- **Private content**: create a dedicated source for that campaign; don't link it to other campaigns.

Two tables power the entire campaign system: `campaign_sources` + `campaign_exclusions`.

---

## The real end goal

Once you have a populated DB and a working calculation engine, the path to custom rulebooks is:

1. Query the DB for existing entities (spells, creatures, items).
2. Let the user describe what they want ("a fire-resistant goblin shaman with a curse attack").
3. LLM generates new entity rows using existing ones as templates.
4. Calculation engine validates the math (is the CR reasonable? is the damage balanced?).
5. Export the new entities back to Markdown chunks → add to a campaign wiki folder.

The wiki and the engine feed each other. The wiki without the engine is a reference book. The engine without the wiki is a calculator with no data. Together they are the campaign tool.

---

## Suggested session order after your rest

1. Write `app/db/populate.py` scaffolding (routing logic only, no llama calls yet).
2. Write one prompt template for `weapons` in `app/db/prompts.py`.
3. Run it against 3–5 weapon chapters, inspect the output.
4. Write the extractor + insert for weapons.
5. Repeat for each entity type. Conditions and damage types first — they are referenced by everything else and have no dependencies.
