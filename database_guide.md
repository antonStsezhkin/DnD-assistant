# Database Guide

`dnd.db` — SQLite. Recreate at any time: `python app/db/create_db.py`

---

## Core ideas

### 1. Everything belongs to a source

A **source** is any document — a published rulebook, a homebrew supplement, a campaign-specific note.
Every entity (weapon, spell, creature, …) has a `source_id`. Nothing floats free.

```sql
INSERT INTO sources (slug, title, edition, language)
VALUES ('phb_5e', 'Player''s Handbook', '5e', 'en');

INSERT INTO sources (slug, title, edition, language)
VALUES ('my_homebrew', 'Gremling Compendium', 'custom', 'en');
```

### 2. Campaigns are a stack of sources

A campaign does not own any entities. It just declares which sources it uses and at what **priority**.

```sql
INSERT INTO campaigns (name, description)
VALUES ('Lost Mine of Phandelver', 'Starter campaign, no undead, extra mounts');

-- include the PHB at base priority
INSERT INTO campaign_sources (campaign_id, source_id, priority)
VALUES (1, 1, 0);   -- phb_5e at priority 0

-- also include homebrew on top
INSERT INTO campaign_sources (campaign_id, source_id, priority)
VALUES (1, 2, 10);  -- my_homebrew at priority 10 — wins on name clashes
```

### 3. Effects are the atomic mechanic unit

Damage, healing, conditions, forced movement — all effects. Weapons, spells, and creature
attacks are just delivery systems that point to a list of effects. The entity stores *what*
it does; the attacker's stats supply the *modifier*.

### 4. Resist is one number

```
effective_value = (1 - resist) * raw_value
```

| resist | meaning | multiplier |
|--------|---------|-----------|
| −1.0 | vulnerable | ×2.0 |
| 0.0 | normal | ×1.0 |
| 0.5 | resistant | ×0.5 |
| 1.0 | immune | ×0.0 |
| 2.0 | healed by this | ×−1.0 |

Zombie hit by Cure Wounds: `resist = 2.0` → `(1 − 2.0) × 10 = −10` → takes 10 damage. No special cases.

---

## Adding things

### Add a weapon

A weapon has intrinsic properties (cost, weight, range) and delivers effects on hit.
These are two separate inserts.

```sql
-- 1. the weapon itself
INSERT INTO weapons (source_id, name, category, cost_gp, weight_lb, range_normal_ft, range_long_ft, versatile_dice)
VALUES (1, 'Longsword', 'martial_melee', 15.0, 3.0, NULL, NULL, '1d10');

-- 2. its damage effect (slashing, STR-scaled, on hit)
INSERT INTO damage_types (name) VALUES ('slashing');  -- skip if already exists

INSERT INTO effects (source_id, name, effect_type, base_dice, base_flat, damage_type_id, scaling_ability, trigger)
VALUES (1, 'Longsword slashing', 'damage', '1d8', 0,
        (SELECT id FROM damage_types WHERE name = 'slashing'),
        'STR', 'on_hit');

-- 3. link weapon → effect
INSERT INTO weapon_effects (weapon_id, effect_id)
VALUES (
    (SELECT id FROM weapons WHERE name = 'Longsword' AND source_id = 1),
    (SELECT id FROM effects  WHERE name = 'Longsword slashing' AND source_id = 1)
);
```

### Add a weapon property

```sql
INSERT INTO weapon_properties (name) VALUES ('versatile');

INSERT INTO weapon_property_map (weapon_id, property_id)
VALUES (
    (SELECT id FROM weapons          WHERE name = 'Longsword'),
    (SELECT id FROM weapon_properties WHERE name = 'versatile')
);
```

### Add a creature (the Dronkey)

```sql
INSERT INTO creatures (
    source_id, name, size, creature_type, alignment,
    armor_class, armor_class_note, hit_points_avg, hit_points_formula,
    speed_walk_ft, speed_fly_ft,
    str, dex, con, int, wis, cha,
    challenge_rating, xp, passive_perception, languages
) VALUES (
    2,                          -- my_homebrew source
    'Dronkey',
    'Large', 'beast', 'chaotic neutral',
    10, 'natural hide',  22, '4d10',
    40, 10,              -- walks 40 ft, "flies" 10 ft (mostly hops and dreams)
    16, 8, 14, 4, 10, 14,
    '1/4', 50, 10, NULL
);

-- its bite attack
INSERT INTO creature_actions (creature_id, action_type, name, attack_type, to_hit_bonus, reach_ft, target, description)
VALUES (
    (SELECT id FROM creatures WHERE name = 'Dronkey'),
    'action', 'Indignant Bite', 'Melee Weapon Attack',
    5, 5, 'one target',
    'The Dronkey bites with the fury of a creature that knows it deserves better.'
);

-- the bite effect
INSERT INTO effects (source_id, name, effect_type, base_dice, base_flat, damage_type_id, scaling_ability, trigger)
VALUES (2, 'Dronkey bite', 'damage', '1d6', 0,
        (SELECT id FROM damage_types WHERE name = 'piercing'),
        'STR', 'on_hit');

INSERT INTO creature_action_effects (action_id, effect_id)
VALUES (
    (SELECT id FROM creature_actions WHERE name = 'Indignant Bite'),
    (SELECT id FROM effects WHERE name = 'Dronkey bite')
);
```

### Add a spell with a saving throw effect

```sql
INSERT INTO spells (source_id, name, level, school, casting_time, range,
                    component_verbal, component_somatic, component_material,
                    component_material_desc, duration, concentration)
VALUES (1, 'Fireball', 3, 'evocation', '1 action', '150 feet',
        1, 1, 1, 'a tiny ball of bat guano and sulfur',
        'Instantaneous', 0);

INSERT INTO effects (source_id, name, effect_type, base_dice, base_flat, damage_type_id,
                     trigger, save_ability, save_dc_formula, save_success_result)
VALUES (1, 'Fireball fire damage', 'damage', '8d6', 0,
        (SELECT id FROM damage_types WHERE name = 'fire'),
        'automatic', 'DEX', '8 + proficiency_bonus + INT_mod', 'half_damage');

INSERT INTO spell_effects (spell_id, effect_id)
VALUES (
    (SELECT id FROM spells  WHERE name = 'Fireball'),
    (SELECT id FROM effects WHERE name = 'Fireball fire damage')
);
```

### Add creature resistances

```sql
-- Zombie: resistant to bludgeoning, healed by necrotic, damaged by radiant
INSERT INTO creature_resistances (creature_id, damage_type_id, resist)
VALUES
    ((SELECT id FROM creatures WHERE name = 'Zombie'),
     (SELECT id FROM damage_types WHERE name = 'bludgeoning'), 0.5),

    ((SELECT id FROM creatures WHERE name = 'Zombie'),
     (SELECT id FROM damage_types WHERE name = 'necrotic'), 2.0),   -- "healed by"

    ((SELECT id FROM creatures WHERE name = 'Zombie'),
     (SELECT id FROM damage_types WHERE name = 'radiant'), -1.0);   -- vulnerable
```

### Exclude an entity from a campaign

```sql
-- This campaign has no goblins. The source still contains them; they're just banned here.
INSERT INTO campaign_exclusions (campaign_id, entity_type, entity_name, reason)
VALUES (1, 'creature', 'Goblin', 'Replaced by Gremlings in this setting');
```

---

## Pulling stats

### Get a creature for a specific campaign

```sql
SELECT c.*
FROM creatures c
JOIN campaign_sources cs ON c.source_id = cs.source_id
WHERE cs.campaign_id = :campaign_id
  AND c.name = :name
  AND NOT EXISTS (
      SELECT 1 FROM campaign_exclusions e
      WHERE e.campaign_id = :campaign_id
        AND e.entity_type = 'creature'
        AND e.entity_name = c.name
  )
ORDER BY cs.priority DESC
LIMIT 1;
```

The same pattern works for any entity type — swap `creatures` for `spells`, `weapons`, etc.

### Get all creatures available in a campaign

```sql
SELECT c.*
FROM creatures c
JOIN campaign_sources cs ON c.source_id = cs.source_id
WHERE cs.campaign_id = :campaign_id
  AND NOT EXISTS (
      SELECT 1 FROM campaign_exclusions e
      WHERE e.campaign_id = :campaign_id
        AND e.entity_type = 'creature'
        AND e.entity_name = c.name
  )
ORDER BY c.name;
```

### Get all effects a weapon delivers (with damage type name)

```sql
SELECT e.name, e.effect_type, e.base_dice, e.base_flat,
       dt.name AS damage_type, e.scaling_ability, e.trigger,
       e.save_ability, e.save_dc_formula, e.save_success_result
FROM effects e
JOIN weapon_effects we ON e.id = we.effect_id
JOIN weapons w         ON we.weapon_id = w.id
LEFT JOIN damage_types dt ON e.damage_type_id = dt.id
WHERE w.name = 'Longsword';
```

### Get a creature's full stat block including actions and resistances

```sql
-- base stats
SELECT * FROM creatures WHERE name = 'Zombie';

-- actions and their effects
SELECT ca.name, ca.action_type, ca.attack_type, ca.to_hit_bonus,
       e.base_dice, e.base_flat, dt.name AS damage_type, e.trigger
FROM creature_actions ca
JOIN creature_action_effects cae ON ca.id = cae.action_id
JOIN effects e                   ON cae.effect_id = e.id
LEFT JOIN damage_types dt        ON e.damage_type_id = dt.id
WHERE ca.creature_id = (SELECT id FROM creatures WHERE name = 'Zombie');

-- resistances
SELECT dt.name AS damage_type, cr.resist,
       CASE
           WHEN cr.resist >= 2.0  THEN 'healed by'
           WHEN cr.resist = 1.0   THEN 'immune'
           WHEN cr.resist > 0     THEN 'resistant'
           WHEN cr.resist = 0     THEN 'normal'
           WHEN cr.resist < 0     THEN 'vulnerable'
       END AS label
FROM creature_resistances cr
JOIN damage_types dt ON cr.damage_type_id = dt.id
WHERE cr.creature_id = (SELECT id FROM creatures WHERE name = 'Zombie');
```

### Get a class's spell slots at a given level

```sql
SELECT cl.*
FROM class_levels cl
JOIN classes c ON cl.class_id = c.id
WHERE c.name = 'Wizard'
  AND cl.level = 5;
-- returns: proficiency_bonus=3, spell_slots_1=4, spell_slots_2=3, spell_slots_3=2, ...
```

---

## Checking existence

### Does this entity exist in a campaign?

```sql
-- Returns 1 if available, 0 if missing or excluded
SELECT COUNT(*) > 0 AS available
FROM creatures c
JOIN campaign_sources cs ON c.source_id = cs.source_id
WHERE cs.campaign_id = :campaign_id
  AND c.name = :name
  AND NOT EXISTS (
      SELECT 1 FROM campaign_exclusions e
      WHERE e.campaign_id = :campaign_id
        AND e.entity_type = 'creature'
        AND e.entity_name = c.name
  );
```

### What is excluded from a campaign?

```sql
SELECT entity_type, entity_name, reason
FROM campaign_exclusions
WHERE campaign_id = :campaign_id
ORDER BY entity_type, entity_name;
```

---

## How priority works

Priority only matters when **two sources in the same campaign define the same entity name**.
If names are unique across sources, priority is irrelevant.

### Example: homebrew Fireball override

```
Campaign "Dark Sun" uses:
  phb_5e      priority = 0    (Fireball: 8d6 fire, DEX save)
  dark_sun_hw priority = 10   (Fireball: 12d6 fire, no save — harsh setting)
```

The query `ORDER BY cs.priority DESC LIMIT 1` picks `priority=10` → the homebrew version.
The PHB Fireball still exists in the database; it's just outranked for this campaign.

### Example: additions don't care about priority

```
Campaign "Wild West" uses:
  phb_5e      priority = 0    (has Pegasus)
  wild_west_hw priority = 10  (has Dronkey — unique name, no clash)
```

The campaign has both. Priority was never consulted because no name matched twice.

### Example: two campaigns, same homebrew supplement

```
Campaign A: phb_5e (0) + gremling_compendium (10)
Campaign B: phb_5e (0) + gremling_compendium (5) + my_overrides (20)
```

`gremling_compendium` source rows are shared — zero duplication.
Campaign B's `my_overrides` can shadow specific Gremling entries at priority 20.

---

## Resistance calculation quick reference

```python
def apply_effect(raw_value: float, resist: float) -> float:
    """Positive result = damage taken. Negative = healed."""
    return (1.0 - resist) * raw_value

# Examples:
apply_effect(10, 0.0)   # → 10.0   normal
apply_effect(10, 0.5)   # → 5.0    resistant
apply_effect(10, 1.0)   # → 0.0    immune
apply_effect(10, -1.0)  # → 20.0   vulnerable
apply_effect(10, 2.0)   # → -10.0  healed (negative = HP gain)
```

No branching. No special cases for healing, necrotic, or undead. The number does the work.
