-- =============================================================================
-- D&D Rules Database
-- =============================================================================
-- Campaign model: a campaign declares which sources (rulebooks / homebrew books) it uses.
-- Entities belong to sources, not campaigns. No data is duplicated.
--   Iron Sword lives in source "phb_5e". Any campaign that includes that source gets it.
--   A homebrew override is a new source at higher priority with the same entity name.
-- Override lookup pattern (SQL):
--   SELECT e.* FROM weapons e
--   JOIN campaign_sources cs ON e.source_id = cs.source_id
--   WHERE cs.campaign_id = :cid AND e.name = :name
--   ORDER BY cs.priority DESC   -- highest-priority source wins
--   LIMIT 1
-- To share homebrew across campaigns: link the same source to both campaigns.
-- To keep content private to one campaign: create a dedicated source for it.
--
-- Design principle: effects are the atomic unit of game mechanics.
-- Damage is an instantaneous effect. A condition is a timed effect.
-- Weapons, spells, and creature attacks are all effect-delivery systems.
-- The effect stores the base value; the user of the weapon/spell supplies
-- the scaling modifier (ability score bonus, proficiency bonus, etc.).
--
-- Resistance model:  effective_value = (1 - resist) * raw_value
--   resist =  0.0  → normal        (×1.0)
--   resist =  0.5  → resistant     (×0.5)
--   resist =  1.0  → immune        (×0.0)
--   resist = -1.0  → vulnerable    (×2.0)
--   resist =  2.0  → healed by it  (×−1.0, e.g. fire heals fire creatures)
-- Zombies have resist = 2.0 against healing effects → healing damages them.
-- No special cases needed anywhere in the engine.
-- =============================================================================

PRAGMA foreign_keys = ON;

-- -----------------------------------------------------------------------------
-- SOURCES — one row per rulebook; every game entity traces back to one
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sources (
    id          INTEGER PRIMARY KEY,
    slug        TEXT    NOT NULL UNIQUE,  -- matches the rulebooks/ subdirectory name
    title       TEXT    NOT NULL,
    edition     TEXT,                     -- "5e", "4e", custom campaign name
    language    TEXT    NOT NULL DEFAULT 'en'
);

-- -----------------------------------------------------------------------------
-- CAMPAIGNS + SOURCE STACK
-- A campaign is just a named ordered stack of sources.
-- priority: higher number = overrides lower. Core rulebook = 0, homebrew = 10+.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS campaigns (
    id          INTEGER PRIMARY KEY,
    name        TEXT    NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE IF NOT EXISTS campaign_sources (
    campaign_id INTEGER NOT NULL REFERENCES campaigns(id),
    source_id   INTEGER NOT NULL REFERENCES sources(id),
    -- priority: only relevant when two sources define the same entity name.
    -- higher number wins. core rulebook = 0, homebrew overrides = 10+.
    -- additions (unique names like Dronkey) ignore priority entirely.
    priority    INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (campaign_id, source_id)
);

-- explicitly ban specific entities from a campaign regardless of which source provides them.
-- e.g. a campaign with no goblins: (campaign_id=1, entity_type='creature', entity_name='Goblin')
-- the engine checks this table before returning any entity.
CREATE TABLE IF NOT EXISTS campaign_exclusions (
    id          INTEGER PRIMARY KEY,
    campaign_id INTEGER NOT NULL REFERENCES campaigns(id),
    entity_type TEXT    NOT NULL, -- 'creature', 'spell', 'weapon', 'item', etc.
    entity_name TEXT    NOT NULL,
    reason      TEXT,             -- optional DM note: "goblins are replaced by Gremlings here"
    UNIQUE (campaign_id, entity_type, entity_name)
);

-- -----------------------------------------------------------------------------
-- DAMAGE TYPES — lookup table; normalises the "slashing / fire / psychic" enum
-- (universal — no campaign_id needed; homebrew damage types go here too)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS damage_types (
    id          INTEGER PRIMARY KEY,
    name        TEXT    NOT NULL UNIQUE   -- "slashing", "piercing", "fire", "psychic", …
);

-- -----------------------------------------------------------------------------
-- CONDITIONS — status effects by name (blinded, poisoned, restrained, …)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conditions (
    id          INTEGER PRIMARY KEY,
    source_id   INTEGER NOT NULL REFERENCES sources(id),
    name        TEXT    NOT NULL,
    description TEXT    NOT NULL,
    UNIQUE (source_id, name)
);

-- -----------------------------------------------------------------------------
-- EFFECTS — the universal mechanic primitive
--
-- Every mechanical outcome is an effect:
--   • damage     → instantaneous HP loss, scaled by ability + dice
--   • healing    → instantaneous HP gain
--   • condition  → applies a condition (blinded, poisoned …) for a duration
--   • forced_movement → pushes/pulls/teleports a target
--   • resource_change → costs/restores spell slots, hit dice, ki, etc.
--   • other      → catch-all for complex or narrative effects
--
-- "base_dice + base_flat" is the raw value before the user's modifiers.
-- scaling_ability: which of the user's ability scores is added to that value.
-- proficiency_applies: whether the user's proficiency bonus is also added.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS effects (
    id                  INTEGER PRIMARY KEY,
    source_id           INTEGER NOT NULL REFERENCES sources(id),
    name                TEXT    NOT NULL,
    effect_type         TEXT    NOT NULL CHECK (effect_type IN (
                            'damage', 'healing', 'condition',
                            'forced_movement', 'resource_change', 'other'
                        )),

    -- damage / healing magnitude
    base_dice           TEXT,            -- "1d6", "2d6", "8d6" — NULL for non-numeric effects
    base_flat           INTEGER,         -- fixed value added on top of dice roll (often 0)
    damage_type_id      INTEGER REFERENCES damage_types(id),   -- NULL for non-damage effects

    -- condition payload
    condition_id        INTEGER REFERENCES conditions(id),     -- NULL unless effect_type = 'condition'
    condition_duration  TEXT,            -- "1 minute", "until end of next turn", "permanent"

    -- forced movement
    distance_ft         INTEGER,         -- how far the target is moved; NULL if not movement
    movement_direction  TEXT,            -- "away", "toward", "up", "teleport"

    -- scaling: how the user's stats modify the base value
    scaling_ability     TEXT CHECK (scaling_ability IN
                            ('STR','DEX','CON','INT','WIS','CHA') OR scaling_ability IS NULL),
    proficiency_applies INTEGER NOT NULL DEFAULT 0 CHECK (proficiency_applies IN (0, 1)),

    -- when does this effect fire?
    trigger             TEXT    NOT NULL DEFAULT 'on_hit',
                        -- "on_hit", "automatic", "on_failed_save",
                        -- "start_of_turn", "end_of_turn", "on_crit"

    -- saving throw to avoid / halve the effect
    save_ability        TEXT CHECK (save_ability IN
                            ('STR','DEX','CON','INT','WIS','CHA') OR save_ability IS NULL),
    save_dc_formula     TEXT,            -- "8 + proficiency_bonus + CON_mod" — evaluated at runtime
    save_success_result TEXT,            -- "no_effect", "half_damage", "no_condition"

    description         TEXT,            -- full prose for edge cases / LLM context
    UNIQUE (source_id, name)
);

-- -----------------------------------------------------------------------------
-- WEAPONS
-- Intrinsic properties only. Damage and on-hit conditions live in weapon_effects.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS weapons (
    id              INTEGER PRIMARY KEY,
    source_id       INTEGER NOT NULL REFERENCES sources(id),
    name            TEXT    NOT NULL,
    category        TEXT    NOT NULL CHECK (category IN (
                        'simple_melee', 'simple_ranged',
                        'martial_melee', 'martial_ranged'
                    )),
    cost_gp         REAL,            -- converted to gold; 1 sp = 0.1 gp
    weight_lb       REAL,
    range_normal_ft INTEGER,         -- NULL for melee-only weapons
    range_long_ft   INTEGER,         -- long range: attacks at disadvantage
    versatile_dice  TEXT,            -- e.g. "1d10" — damage die when held two-handed; NULL if not versatile
    UNIQUE (source_id, name)
);

-- weapon properties: ammunition, finesse, heavy, light, loading, thrown, two_handed, versatile, reach
CREATE TABLE IF NOT EXISTS weapon_properties (
    id   INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS weapon_property_map (
    weapon_id   INTEGER NOT NULL REFERENCES weapons(id),
    property_id INTEGER NOT NULL REFERENCES weapon_properties(id),
    PRIMARY KEY (weapon_id, property_id)
);

-- a weapon delivers one or more effects when it hits
CREATE TABLE IF NOT EXISTS weapon_effects (
    weapon_id   INTEGER NOT NULL REFERENCES weapons(id),
    effect_id   INTEGER NOT NULL REFERENCES effects(id),
    PRIMARY KEY (weapon_id, effect_id)
);

-- -----------------------------------------------------------------------------
-- ARMOR
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS armor (
    id                   INTEGER PRIMARY KEY,
    source_id            INTEGER NOT NULL REFERENCES sources(id),
    name                 TEXT    NOT NULL,
    category             TEXT    NOT NULL CHECK (category IN ('light', 'medium', 'heavy', 'shield')),
    cost_gp              REAL,
    base_ac              INTEGER NOT NULL,
    -- how the wearer's DEX modifier applies to AC:
    --   full      = add full DEX mod (light armor)
    --   max2      = add DEX mod up to +2 (medium armor)
    --   none      = DEX not added (heavy armor)
    --   plus2     = flat +2 regardless of DEX (shield)
    dex_bonus_mode       TEXT    NOT NULL CHECK (dex_bonus_mode IN ('full', 'max2', 'none', 'plus2')),
    strength_req         INTEGER,         -- minimum STR to wear without speed penalty; NULL = no req
    stealth_disadvantage INTEGER NOT NULL DEFAULT 0 CHECK (stealth_disadvantage IN (0, 1)),
    weight_lb            REAL,
    UNIQUE (source_id, name)
);

-- -----------------------------------------------------------------------------
-- CLASSES
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS classes (
    id                      INTEGER PRIMARY KEY,
    source_id               INTEGER NOT NULL REFERENCES sources(id),
    name                    TEXT    NOT NULL,
    hit_die                 INTEGER NOT NULL,  -- 6, 8, 10, or 12
    primary_ability         TEXT    NOT NULL,
    saving_throw_prof_1     TEXT    NOT NULL,  -- e.g. "Wisdom"
    saving_throw_prof_2     TEXT    NOT NULL,  -- e.g. "Charisma"
    armor_proficiencies     TEXT,
    weapon_proficiencies    TEXT,
    tool_proficiencies      TEXT,
    skill_choices_count     INTEGER,           -- how many skills the player picks at creation
    skill_choices_from      TEXT,              -- comma-separated list of eligible skills
    UNIQUE (source_id, name)
);

-- one row per class × level; spell_slots_* are NULL for non-casters
CREATE TABLE IF NOT EXISTS class_levels (
    id                  INTEGER PRIMARY KEY,
    class_id            INTEGER NOT NULL REFERENCES classes(id),
    level               INTEGER NOT NULL CHECK (level BETWEEN 1 AND 20),
    proficiency_bonus   INTEGER NOT NULL,
    known_cantrips      INTEGER,
    spell_slots_1       INTEGER,
    spell_slots_2       INTEGER,
    spell_slots_3       INTEGER,
    spell_slots_4       INTEGER,
    spell_slots_5       INTEGER,
    spell_slots_6       INTEGER,
    spell_slots_7       INTEGER,
    spell_slots_8       INTEGER,
    spell_slots_9       INTEGER,
    UNIQUE (class_id, level)
);

-- named features (Sneak Attack, Spellcasting, Divine Smite …) granted at a specific level
CREATE TABLE IF NOT EXISTS class_features (
    id          INTEGER PRIMARY KEY,
    class_id    INTEGER NOT NULL REFERENCES classes(id),
    level       INTEGER NOT NULL CHECK (level BETWEEN 1 AND 20),
    name        TEXT    NOT NULL,
    description TEXT
);

-- -----------------------------------------------------------------------------
-- SPELLS
-- Mechanical outcomes (damage, conditions, movement) belong to spell_effects.
-- The description field here is for lore / flavour — not mechanics.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS spells (
    id                      INTEGER PRIMARY KEY,
    source_id               INTEGER NOT NULL REFERENCES sources(id),
    name                    TEXT    NOT NULL,
    level                   INTEGER NOT NULL CHECK (level BETWEEN 0 AND 9),
    school                  TEXT    NOT NULL,  -- "evocation", "necromancy", …
    casting_time            TEXT    NOT NULL,  -- "1 action", "1 bonus action", "1 reaction, …"
    range                   TEXT    NOT NULL,  -- "Touch", "60 feet", "Self (15-foot cone)"
    component_verbal        INTEGER NOT NULL DEFAULT 0 CHECK (component_verbal   IN (0, 1)),
    component_somatic       INTEGER NOT NULL DEFAULT 0 CHECK (component_somatic  IN (0, 1)),
    component_material      INTEGER NOT NULL DEFAULT 0 CHECK (component_material IN (0, 1)),
    component_material_desc TEXT,              -- e.g. "a pinch of bat guano and sulfur"
    duration                TEXT    NOT NULL,  -- "Instantaneous", "Concentration, up to 1 minute"
    concentration           INTEGER NOT NULL DEFAULT 0 CHECK (concentration IN (0, 1)),
    ritual                  INTEGER NOT NULL DEFAULT 0 CHECK (ritual IN (0, 1)),
    higher_level_desc       TEXT,              -- "At Higher Levels" block; NULL if absent
    UNIQUE (source_id, name)
);

CREATE TABLE IF NOT EXISTS spell_effects (
    spell_id    INTEGER NOT NULL REFERENCES spells(id),
    effect_id   INTEGER NOT NULL REFERENCES effects(id),
    PRIMARY KEY (spell_id, effect_id)
);

-- which class spell lists include this spell
CREATE TABLE IF NOT EXISTS spell_class_list (
    spell_id    INTEGER NOT NULL REFERENCES spells(id),
    class_id    INTEGER NOT NULL REFERENCES classes(id),
    PRIMARY KEY (spell_id, class_id)
);

-- -----------------------------------------------------------------------------
-- RACES & SUBRACES
-- parent_race_id NULL = base race; non-NULL = subrace of that parent
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS races (
    id                  INTEGER PRIMARY KEY,
    source_id           INTEGER NOT NULL REFERENCES sources(id),
    name                TEXT    NOT NULL,
    parent_race_id      INTEGER REFERENCES races(id),
    size                TEXT,              -- "Small", "Medium"
    speed_walk_ft       INTEGER,
    speed_fly_ft        INTEGER,
    speed_swim_ft       INTEGER,
    ability_bonus_str   INTEGER NOT NULL DEFAULT 0,
    ability_bonus_dex   INTEGER NOT NULL DEFAULT 0,
    ability_bonus_con   INTEGER NOT NULL DEFAULT 0,
    ability_bonus_int   INTEGER NOT NULL DEFAULT 0,
    ability_bonus_wis   INTEGER NOT NULL DEFAULT 0,
    ability_bonus_cha   INTEGER NOT NULL DEFAULT 0,
    languages           TEXT,
    UNIQUE (source_id, name)
);

CREATE TABLE IF NOT EXISTS race_traits (
    id          INTEGER PRIMARY KEY,
    race_id     INTEGER NOT NULL REFERENCES races(id),
    name        TEXT    NOT NULL,
    description TEXT
);

-- -----------------------------------------------------------------------------
-- BACKGROUNDS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS backgrounds (
    id                  INTEGER PRIMARY KEY,
    source_id           INTEGER NOT NULL REFERENCES sources(id),
    name                TEXT    NOT NULL,
    skill_proficiencies TEXT,
    tool_proficiencies  TEXT,
    languages_count     INTEGER NOT NULL DEFAULT 0,
    starting_equipment  TEXT,
    feature_name        TEXT,
    feature_description TEXT,
    UNIQUE (source_id, name)
);

-- -----------------------------------------------------------------------------
-- CREATURES / MONSTERS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS creatures (
    id                      INTEGER PRIMARY KEY,
    source_id               INTEGER NOT NULL REFERENCES sources(id),
    name                    TEXT    NOT NULL,
    size                    TEXT    NOT NULL,   -- Tiny / Small / Medium / Large / Huge / Gargantuan
    creature_type           TEXT    NOT NULL,   -- "beast", "humanoid", "undead", "dragon", …
    alignment               TEXT,
    armor_class             INTEGER NOT NULL,
    armor_class_note        TEXT,               -- "natural armor", "chain mail", …
    hit_points_avg          INTEGER NOT NULL,
    hit_points_formula      TEXT    NOT NULL,   -- "3d8+6"
    speed_walk_ft           INTEGER NOT NULL DEFAULT 0,
    speed_fly_ft            INTEGER,
    speed_swim_ft           INTEGER,
    speed_climb_ft          INTEGER,
    speed_burrow_ft         INTEGER,
    str                     INTEGER NOT NULL,
    dex                     INTEGER NOT NULL,
    con                     INTEGER NOT NULL,
    int                     INTEGER NOT NULL,
    wis                     INTEGER NOT NULL,
    cha                     INTEGER NOT NULL,
    challenge_rating        TEXT    NOT NULL,   -- "0", "1/8", "1/4", "1/2", "1" … "30"
    xp                      INTEGER NOT NULL,
    passive_perception      INTEGER,
    darkvision_ft           INTEGER,
    blindsight_ft           INTEGER,
    tremorsense_ft          INTEGER,
    truesight_ft            INTEGER,
    languages               TEXT,
    UNIQUE (source_id, name)
);

-- resist = (1 - resist) * damage; covers vulnerability, resistance, immunity,
-- and "healed by this damage type" in one column — no special cases needed
CREATE TABLE IF NOT EXISTS creature_resistances (
    id              INTEGER PRIMARY KEY,
    creature_id     INTEGER NOT NULL REFERENCES creatures(id),
    damage_type_id  INTEGER NOT NULL REFERENCES damage_types(id),
    resist          REAL    NOT NULL DEFAULT 0,
    UNIQUE (creature_id, damage_type_id)
);

-- same resist model for races (dwarf poison resistance, fire genasi fire immunity, …)
CREATE TABLE IF NOT EXISTS race_resistances (
    id              INTEGER PRIMARY KEY,
    race_id         INTEGER NOT NULL REFERENCES races(id),
    damage_type_id  INTEGER NOT NULL REFERENCES damage_types(id),
    resist          REAL    NOT NULL DEFAULT 0,
    UNIQUE (race_id, damage_type_id)
);

-- conditions are boolean — you either have immunity or you don't
CREATE TABLE IF NOT EXISTS creature_condition_immunities (
    creature_id     INTEGER NOT NULL REFERENCES creatures(id),
    condition_id    INTEGER NOT NULL REFERENCES conditions(id),
    PRIMARY KEY (creature_id, condition_id)
);

CREATE TABLE IF NOT EXISTS race_condition_immunities (
    race_id         INTEGER NOT NULL REFERENCES races(id),
    condition_id    INTEGER NOT NULL REFERENCES conditions(id),
    PRIMARY KEY (race_id, condition_id)
);

-- per-creature skill bonuses (e.g. Perception +3, Stealth +4)
CREATE TABLE IF NOT EXISTS creature_skills (
    id          INTEGER PRIMARY KEY,
    creature_id INTEGER NOT NULL REFERENCES creatures(id),
    skill       TEXT    NOT NULL,
    bonus       INTEGER NOT NULL
);

-- named passive traits: Keen Smell, Pack Tactics, Undead Fortitude, …
CREATE TABLE IF NOT EXISTS creature_traits (
    id          INTEGER PRIMARY KEY,
    creature_id INTEGER NOT NULL REFERENCES creatures(id),
    name        TEXT    NOT NULL,
    description TEXT    NOT NULL
);

-- attacks and special abilities; mechanical outcomes go in creature_action_effects
CREATE TABLE IF NOT EXISTS creature_actions (
    id              INTEGER PRIMARY KEY,
    creature_id     INTEGER NOT NULL REFERENCES creatures(id),
    action_type     TEXT    NOT NULL CHECK (action_type IN (
                        'action', 'reaction', 'bonus_action',
                        'legendary_action', 'lair_action'
                    )),
    name            TEXT    NOT NULL,
    -- attack roll mechanics (NULL for non-attack actions)
    attack_type     TEXT,            -- "Melee Weapon Attack", "Ranged Weapon Attack", "Melee Spell Attack"
    to_hit_bonus    INTEGER,
    reach_ft        INTEGER,
    range_normal_ft INTEGER,
    range_long_ft   INTEGER,
    target          TEXT,            -- "one target", "all creatures in a 15-foot cone"
    description     TEXT    NOT NULL -- full text preserved for LLM context
);

CREATE TABLE IF NOT EXISTS creature_action_effects (
    action_id   INTEGER NOT NULL REFERENCES creature_actions(id),
    effect_id   INTEGER NOT NULL REFERENCES effects(id),
    PRIMARY KEY (action_id, effect_id)
);

-- -----------------------------------------------------------------------------
-- EQUIPMENT (adventuring gear, tools, mounts, trade goods)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS equipment (
    id          INTEGER PRIMARY KEY,
    source_id   INTEGER NOT NULL REFERENCES sources(id),
    name        TEXT    NOT NULL,
    category    TEXT,               -- "adventuring_gear", "tool", "mount", "vehicle", "trade_good"
    cost_gp     REAL,
    weight_lb   REAL,
    description TEXT,
    UNIQUE (source_id, name)
);

-- -----------------------------------------------------------------------------
-- INDICES — most FK columns and all name lookups
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_weapons_source       ON weapons(source_id);
CREATE INDEX IF NOT EXISTS idx_armor_source         ON armor(source_id);
CREATE INDEX IF NOT EXISTS idx_spells_source        ON spells(source_id);
CREATE INDEX IF NOT EXISTS idx_spells_level_school  ON spells(level, school);
CREATE INDEX IF NOT EXISTS idx_classes_source       ON classes(source_id);
CREATE INDEX IF NOT EXISTS idx_class_levels_class   ON class_levels(class_id);
CREATE INDEX IF NOT EXISTS idx_class_features_class ON class_features(class_id, level);
CREATE INDEX IF NOT EXISTS idx_creatures_source     ON creatures(source_id);
CREATE INDEX IF NOT EXISTS idx_creatures_cr         ON creatures(challenge_rating);
CREATE INDEX IF NOT EXISTS idx_creature_actions     ON creature_actions(creature_id);
CREATE INDEX IF NOT EXISTS idx_effects_type         ON effects(effect_type);
CREATE INDEX IF NOT EXISTS idx_races_source             ON races(source_id);
CREATE INDEX IF NOT EXISTS idx_races_parent             ON races(parent_race_id);
CREATE INDEX IF NOT EXISTS idx_spell_class_list         ON spell_class_list(class_id);
CREATE INDEX IF NOT EXISTS idx_campaign_sources     ON campaign_sources(campaign_id, priority DESC);
CREATE INDEX IF NOT EXISTS idx_campaign_exclusions  ON campaign_exclusions(campaign_id, entity_type);
CREATE INDEX IF NOT EXISTS idx_creature_resistances     ON creature_resistances(creature_id);
CREATE INDEX IF NOT EXISTS idx_race_resistances         ON race_resistances(race_id);
CREATE INDEX IF NOT EXISTS idx_creature_cond_immunities ON creature_condition_immunities(creature_id);
CREATE INDEX IF NOT EXISTS idx_race_cond_immunities     ON race_condition_immunities(race_id);
