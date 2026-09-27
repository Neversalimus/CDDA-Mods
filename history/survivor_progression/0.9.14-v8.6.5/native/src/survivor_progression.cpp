#define NCMM_MOD_BUILD
#include "ncmm_api.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <map>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

namespace
{
const char *const module_id = "survivor_progression";
constexpr int state_schema = 7;

const char *required_caps[] = {
    "core.v1",
    "locale.v1",
    "module_contract.v1",
    "events.turn.v1",
    "character_state.v1",
    "character.modifiers.v1",
    "ui.basic.v1",
    "ui.tiles.v1",
    "ui.cards.v1",
    "ui.tree.v1",
    "gameplay.metrics.v1",
    "active_mods.v1",
    "ui.theme.v1",
    "module_hotkeys.context.v1",
    "module_hotkeys.v1",
    "api.versioning.v1",
    "state.migration.v1",
    "module.lifecycle.v1"
};

const ncmm_host_api_v1 *host = nullptr;
int turn_accumulator = 0;
bool last_character_available = false;
bool effects_dirty = true;
int current_xp_bonus_pct = 0;

enum class branch_id {
    combat,
    survival,
    mobility,
    crafting,
    scavenging,
    mastery
};

enum class currency_id {
    perk,
    major
};

enum class perk_kind {
    stat,
    effect
};

enum class perk_scaling {
    fixed,
    per_active_branch,
    per_owned_major
};

struct modifier_effect {
    const char *id;
    double value;
};

struct perk_def {
    const char *id;
    branch_id branch;
    int tier;
    int required_level;
    currency_id currency;
    const char *prereq1;
    const char *prereq2;
    const char *name_en;
    const char *name_ru;
    const char *desc_en;
    const char *desc_ru;
    std::array<modifier_effect, 4> effects;
    int effect_count;
    int xp_bonus_pct;
    perk_kind kind = perk_kind::stat;
    perk_scaling scaling = perk_scaling::fixed;
    double branch_amp_pct = 0.0;
    double global_amp_pct = 0.0;
};

perk_kind effective_kind( const perk_def &perk )
{
    return perk.kind == perk_kind::effect || perk.xp_bonus_pct != 0 ?
           perk_kind::effect : perk_kind::stat;
}

const perk_def perks[] = {
    { "c_power", branch_id::combat, 1, 1, currency_id::perk, "", "", "Power Training", "Силовая подготовка", "+1 Strength", "+1 к силе", {{ { "str_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "c_footwork", branch_id::combat, 1, 1, currency_id::perk, "", "", "Combat Footwork", "Боевая работа ног", "+0.5 dodge", "+0,5 уклонения", {{ { "dodge_flat", 0.5 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "c_precision", branch_id::combat, 2, 5, currency_id::perk, "c_power", "", "Precision", "Точность", "+0.5 melee hit", "+0,5 точности в ближнем бою", {{ { "melee_hit_flat", 0.5 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "c_reflexes", branch_id::combat, 2, 5, currency_id::perk, "c_footwork", "", "Reflex Drills", "Тренировка рефлексов", "+1 Dexterity", "+1 к ловкости", {{ { "dex_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "c_conditioning", branch_id::combat, 3, 10, currency_id::perk, "c_precision", "", "Combat Conditioning", "Боевая выносливость", "+8% maximum stamina", "+8% к максимуму выносливости", {{ { "stamina_max_pct", 8 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "c_tempo", branch_id::combat, 3, 10, currency_id::perk, "c_reflexes", "", "Battle Tempo", "Темп боя", "+3% speed", "+3% к скорости", {{ { "speed_pct", 3 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "c_bruiser", branch_id::combat, 4, 15, currency_id::perk, "c_conditioning", "", "Bruiser", "Громила", "+1 Strength, +0.5 melee hit", "+1 сила, +0,5 точности", {{ { "str_flat", 1 }, { "melee_hit_flat", 0.5 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "c_evasion", branch_id::combat, 4, 15, currency_id::perk, "c_tempo", "", "Evasive Fighter", "Уклончивый боец", "+0.75 dodge, -3% move cost", "+0,75 уклонения, -3% стоимости движения", {{ { "dodge_flat", 0.75 }, { "move_cost_pct", -3 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "c_veteran", branch_id::combat, 5, 20, currency_id::major, "c_bruiser", "c_evasion", "Veteran Fighter", "Ветеран", "+1 STR, +1 DEX, +0.5 melee hit", "+1 сила, +1 ловкость, +0,5 точности", {{ { "str_flat", 1 }, { "dex_flat", 1 }, { "melee_hit_flat", 0.5 }, { nullptr, 0.0 } }}, 3, 0 },
    { "c_apex", branch_id::combat, 6, 30, currency_id::major, "c_veteran", "", "Apex Combatant", "Вершина боя", "+5% speed, +1 dodge, +10% stamina, +0.5 hit", "+5% скорость, +1 уклонение, +10% выносливость, +0,5 точность", {{ { "speed_pct", 5 }, { "dodge_flat", 1 }, { "stamina_max_pct", 10 }, { "melee_hit_flat", 0.5 } }}, 4, 0 },
    { "s_hardy", branch_id::survival, 1, 1, currency_id::perk, "", "", "Hardy", "Закалённый", "+6% maximum stamina", "+6% к максимуму выносливости", {{ { "stamina_max_pct", 6 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "s_field", branch_id::survival, 1, 1, currency_id::perk, "", "", "Field Medicine", "Полевая медицина", "+10% natural healing", "+10% естественного лечения", {{ { "healing_pct", 10 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "s_pack", branch_id::survival, 2, 5, currency_id::perk, "s_hardy", "", "Pack Discipline", "Грамотная укладка", "+10% carrying capacity", "+10% грузоподъёмности", {{ { "carry_weight_pct", 10 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "s_resilient", branch_id::survival, 2, 5, currency_id::perk, "s_field", "", "Resilient Body", "Живучий организм", "+15% natural healing", "+15% естественного лечения", {{ { "healing_pct", 15 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "s_endurance", branch_id::survival, 3, 10, currency_id::perk, "s_pack", "", "Long Haul", "Долгий путь", "+10% maximum stamina", "+10% к максимуму выносливости", {{ { "stamina_max_pct", 10 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "s_instinct", branch_id::survival, 3, 10, currency_id::perk, "s_resilient", "", "Survival Instinct", "Инстинкт выживания", "+1 Perception", "+1 к восприятию", {{ { "per_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "s_ironback", branch_id::survival, 4, 15, currency_id::perk, "s_endurance", "", "Iron Back", "Железная спина", "+15% carry, +1 Strength", "+15% грузоподъёмности, +1 сила", {{ { "carry_weight_pct", 15 }, { "str_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "s_recovery", branch_id::survival, 4, 15, currency_id::perk, "s_instinct", "", "Rapid Recovery", "Быстрое восстановление", "+20% healing, +5% maximum stamina", "+20% лечение, +5% максимум выносливости", {{ { "healing_pct", 20 }, { "stamina_max_pct", 5 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "s_survivor", branch_id::survival, 5, 20, currency_id::major, "s_ironback", "s_recovery", "True Survivor", "Настоящий выживший", "+15% stamina, +10% carry, +15% healing", "+15% выносливость, +10% грузоподъёмность, +15% лечение", {{ { "stamina_max_pct", 15 }, { "carry_weight_pct", 10 }, { "healing_pct", 15 }, { nullptr, 0.0 } }}, 3, 0 },
    { "s_unbreakable", branch_id::survival, 6, 30, currency_id::major, "s_survivor", "", "Unbreakable", "Несломленный", "+15% stamina, +20% healing, +1 STR, +10% carry", "+15% выносливость, +20% лечение, +1 сила, +10% грузоподъёмность", {{ { "stamina_max_pct", 15 }, { "healing_pct", 20 }, { "str_flat", 1 }, { "carry_weight_pct", 10 } }}, 4, 0 },
    { "m_light", branch_id::mobility, 1, 1, currency_id::perk, "", "", "Light Step", "Лёгкий шаг", "-3% move cost", "-3% стоимости движения", {{ { "move_cost_pct", -3 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "m_cardio", branch_id::mobility, 1, 1, currency_id::perk, "", "", "Cardio Base", "Кардиобаза", "+6% maximum stamina", "+6% к максимуму выносливости", {{ { "stamina_max_pct", 6 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "m_stride", branch_id::mobility, 2, 5, currency_id::perk, "m_light", "", "Efficient Stride", "Эффективный шаг", "+3% speed", "+3% к скорости", {{ { "speed_pct", 3 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "m_breath", branch_id::mobility, 2, 5, currency_id::perk, "m_cardio", "", "Deep Reserve", "Глубокий резерв", "+8% maximum stamina", "+8% к максимуму выносливости", {{ { "stamina_max_pct", 8 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "m_parkour", branch_id::mobility, 3, 10, currency_id::perk, "m_stride", "", "Parkour Habit", "Привычка к паркуру", "-5% move cost, +1 Dexterity", "-5% стоимости движения, +1 ловкость", {{ { "move_cost_pct", -5 }, { "dex_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "m_quick", branch_id::mobility, 3, 10, currency_id::perk, "m_breath", "", "Quick Recovery", "Второе дыхание", "+4% speed", "+4% к скорости", {{ { "speed_pct", 4 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "m_runner", branch_id::mobility, 4, 15, currency_id::perk, "m_parkour", "", "Runner", "Бегун", "+5% speed, -3% move cost", "+5% скорость, -3% стоимость движения", {{ { "speed_pct", 5 }, { "move_cost_pct", -3 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "m_marathon", branch_id::mobility, 4, 15, currency_id::perk, "m_quick", "", "Marathoner", "Марафонец", "+12% maximum stamina, -2% move cost", "+12% выносливость, -2% стоимость движения", {{ { "stamina_max_pct", 12 }, { "move_cost_pct", -2 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "m_flow", branch_id::mobility, 5, 20, currency_id::major, "m_runner", "m_marathon", "Flow State", "Состояние потока", "+5% speed, +1 DEX, -5% move cost", "+5% скорость, +1 ловкость, -5% стоимость движения", {{ { "speed_pct", 5 }, { "dex_flat", 1 }, { "move_cost_pct", -5 }, { nullptr, 0.0 } }}, 3, 0 },
    { "m_untouchable", branch_id::mobility, 6, 30, currency_id::major, "m_flow", "", "Untouchable", "Неуловимый", "+7% speed, +1 dodge, -5% move cost, +8% stamina", "+7% скорость, +1 уклонение, -5% движение, +8% выносливость", {{ { "speed_pct", 7 }, { "dodge_flat", 1 }, { "move_cost_pct", -5 }, { "stamina_max_pct", 8 } }}, 4, 0 },
    { "f_hands", branch_id::crafting, 1, 1, currency_id::perk, "", "", "Practiced Hands", "Набитая рука", "+5% crafting speed", "+5% скорости крафта", {{ { "craft_speed_pct", 5 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "f_reader", branch_id::crafting, 1, 1, currency_id::perk, "", "", "Focused Reading", "Сосредоточенное чтение", "+10% reading speed", "+10% скорости чтения", {{ { "read_speed_pct", 10 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "f_efficiency", branch_id::crafting, 2, 5, currency_id::perk, "f_hands", "", "Workshop Rhythm", "Ритм мастерской", "+8% crafting speed", "+8% скорости крафта", {{ { "craft_speed_pct", 8 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "f_study", branch_id::crafting, 2, 5, currency_id::perk, "f_reader", "", "Study Habit", "Привычка учиться", "+1 Intelligence", "+1 к интеллекту", {{ { "int_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "f_workflow", branch_id::crafting, 3, 10, currency_id::perk, "f_efficiency", "", "Efficient Workflow", "Эффективный процесс", "+10% crafting speed", "+10% скорости крафта", {{ { "craft_speed_pct", 10 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "f_quickstudy", branch_id::crafting, 3, 10, currency_id::perk, "f_study", "", "Quick Study", "Быстрое обучение", "+15% reading speed", "+15% скорости чтения", {{ { "read_speed_pct", 15 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "f_engineer", branch_id::crafting, 4, 15, currency_id::perk, "f_workflow", "", "Engineer", "Инженер", "+10% crafting speed, +1 INT", "+10% крафт, +1 интеллект", {{ { "craft_speed_pct", 10 }, { "int_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "f_scholar", branch_id::crafting, 4, 15, currency_id::perk, "f_quickstudy", "", "Scholar", "Учёный", "+20% reading speed, +1 INT", "+20% чтение, +1 интеллект", {{ { "read_speed_pct", 20 }, { "int_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "f_master", branch_id::crafting, 5, 20, currency_id::major, "f_engineer", "f_scholar", "Master Artisan", "Мастер", "+15% craft, +10% read, +1 INT", "+15% крафт, +10% чтение, +1 интеллект", {{ { "craft_speed_pct", 15 }, { "read_speed_pct", 10 }, { "int_flat", 1 }, { nullptr, 0.0 } }}, 3, 0 },
    { "f_genius", branch_id::crafting, 6, 30, currency_id::major, "f_master", "", "Technical Genius", "Технический гений", "+20% craft, +20% read, +1 INT, +10% carry", "+20% крафт, +20% чтение, +1 интеллект, +10% грузоподъёмность", {{ { "craft_speed_pct", 20 }, { "read_speed_pct", 20 }, { "int_flat", 1 }, { "carry_weight_pct", 10 } }}, 4, 0 },
    { "g_observer", branch_id::scavenging, 1, 1, currency_id::perk, "", "", "Observer", "Наблюдатель", "+1 Perception", "+1 к восприятию", {{ { "per_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "g_hauler", branch_id::scavenging, 1, 1, currency_id::perk, "", "", "Hauler", "Носильщик", "+10% carrying capacity", "+10% грузоподъёмности", {{ { "carry_weight_pct", 10 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "g_route", branch_id::scavenging, 2, 5, currency_id::perk, "g_observer", "", "Route Sense", "Чувство маршрута", "-3% move cost", "-3% стоимости движения", {{ { "move_cost_pct", -3 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "g_pack", branch_id::scavenging, 2, 5, currency_id::perk, "g_hauler", "", "Pack Expert", "Эксперт по укладке", "+10% carrying capacity", "+10% грузоподъёмности", {{ { "carry_weight_pct", 10 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "g_awareness", branch_id::scavenging, 3, 10, currency_id::perk, "g_route", "", "Situational Awareness", "Ситуационная осведомлённость", "+1 PER, +2% speed", "+1 восприятие, +2% скорость", {{ { "per_flat", 1 }, { "speed_pct", 2 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "g_endurance", branch_id::scavenging, 3, 10, currency_id::perk, "g_pack", "", "Loaded March", "Марш с грузом", "+7% maximum stamina", "+7% к максимуму выносливости", {{ { "stamina_max_pct", 7 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "g_pathfinder", branch_id::scavenging, 4, 15, currency_id::perk, "g_awareness", "", "Pathfinder", "Следопыт", "-5% move cost, +1 PER", "-5% движение, +1 восприятие", {{ { "move_cost_pct", -5 }, { "per_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "g_mule", branch_id::scavenging, 4, 15, currency_id::perk, "g_endurance", "", "Human Mule", "Вьючный человек", "+15% carry, +1 STR", "+15% грузоподъёмность, +1 сила", {{ { "carry_weight_pct", 15 }, { "str_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "g_raider", branch_id::scavenging, 5, 20, currency_id::major, "g_pathfinder", "g_mule", "Veteran Scavenger", "Опытный добытчик", "+1 PER, +15% carry, +3% speed", "+1 восприятие, +15% грузоподъёмность, +3% скорость", {{ { "per_flat", 1 }, { "carry_weight_pct", 15 }, { "speed_pct", 3 }, { nullptr, 0.0 } }}, 3, 0 },
    { "g_legend", branch_id::scavenging, 6, 30, currency_id::major, "g_raider", "", "Wasteland Scavenger", "Легенда пустошей", "+1 PER, +20% carry, -5% move cost, +3% speed", "+1 восприятие, +20% грузоподъёмность, -5% движение, +3% скорость", {{ { "per_flat", 1 }, { "carry_weight_pct", 20 }, { "move_cost_pct", -5 }, { "speed_pct", 3 } }}, 4, 0 },
    { "a_fast", branch_id::mastery, 1, 1, currency_id::perk, "", "", "Fast Learner", "Быстрый ученик", "+100% Survivor XP", "+100% опыта Survivor", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 100 },
    { "a_focus", branch_id::mastery, 1, 1, currency_id::perk, "", "", "Focused Mind", "Собранный ум", "+1 Intelligence", "+1 к интеллекту", {{ { "int_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0 },
    { "a_adapt", branch_id::mastery, 2, 5, currency_id::perk, "a_fast", "", "Adaptive Learning", "Адаптивное обучение", "+25% Survivor XP", "+25% опыта Survivor", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 25 },
    { "a_balance", branch_id::mastery, 2, 5, currency_id::perk, "a_focus", "", "Balanced Growth", "Сбалансированное развитие", "+1 STR, +1 DEX", "+1 сила, +1 ловкость", {{ { "str_flat", 1 }, { "dex_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "a_learning", branch_id::mastery, 3, 10, currency_id::perk, "a_adapt", "", "Learning Loop", "Цикл обучения", "+25% Survivor XP, +5% crafting", "+25% опыта Survivor, +5% крафта", {{ { "craft_speed_pct", 5 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 25 },
    { "a_insight", branch_id::mastery, 3, 10, currency_id::perk, "a_balance", "", "Insight", "Проницательность", "+1 PER, +1 INT", "+1 восприятие, +1 интеллект", {{ { "per_flat", 1 }, { "int_flat", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "a_growth", branch_id::mastery, 4, 15, currency_id::perk, "a_learning", "", "Accelerated Growth", "Ускоренный рост", "+25% Survivor XP, +5% stamina", "+25% опыта Survivor, +5% выносливость", {{ { "stamina_max_pct", 5 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 25 },
    { "a_polymath", branch_id::mastery, 4, 15, currency_id::perk, "a_insight", "", "Polymath", "Универсал", "+10% craft, +10% reading", "+10% крафт, +10% чтение", {{ { "craft_speed_pct", 10 }, { "read_speed_pct", 10 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0 },
    { "a_paragon", branch_id::mastery, 5, 20, currency_id::major, "a_growth", "a_polymath", "Paragon", "Образец", "+1 STR, +1 DEX, +1 PER, +1 INT", "+1 ко всем основным характеристикам", {{ { "str_flat", 1 }, { "dex_flat", 1 }, { "per_flat", 1 }, { "int_flat", 1 } }}, 4, 0 },
    { "a_transcendent", branch_id::mastery, 6, 30, currency_id::major, "a_paragon", "", "Transcendent Survivor", "Совершенный выживший", "+50% XP, +3% speed, +10% stamina, +10% healing", "+50% опыта, +3% скорость, +10% выносливость, +10% лечение", {{ { "speed_pct", 3 }, { "stamina_max_pct", 10 }, { "healing_pct", 10 }, { nullptr, 0.0 } }}, 3, 50 }
,
    { "ce_rhythm", branch_id::combat, 1, 3, currency_id::perk, "c_power", "", "Combat Rhythm", "Боевой ритм", "Combat stat perks are 5% stronger.", "Статовые боевые перки на 5% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 5, 0 },
    { "ce_drills", branch_id::combat, 1, 6, currency_id::perk, "c_footwork", "", "Drilled Reflexes", "Отработанные рефлексы", "+0.25 dodge and +0.25 melee hit.", "+0,25 уклонения и +0,25 точности ближнего боя.", {{ { "dodge_flat", 0.25 }, { "melee_hit_flat", 0.25 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0, perk_kind::effect, perk_scaling::fixed, 0, 0 },
    { "ce_reserve", branch_id::combat, 2, 9, currency_id::perk, "c_precision", "ce_rhythm", "Reserve Under Fire", "Резерв под огнём", "+2% max stamina per active Survivor branch.", "+2% максимума выносливости за каждую активную ветку Survivor.", {{ { "stamina_max_pct", 2 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "ce_lessons", branch_id::combat, 2, 12, currency_id::perk, "c_reflexes", "ce_drills", "Lessons of Violence", "Уроки боя", "+4% Survivor XP per owned major perk.", "+4% опыта Survivor за каждый купленный большой перк.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 4, perk_kind::effect, perk_scaling::per_owned_major, 0, 0 },
    { "ce_tactics", branch_id::combat, 3, 15, currency_id::major, "c_conditioning", "ce_reserve", "Tactical Integration", "Тактическая интеграция", "Combat stat perks are another 10% stronger.", "Статовые боевые перки ещё на 10% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 10, 0 },
    { "ce_pressure", branch_id::combat, 3, 18, currency_id::perk, "c_tempo", "ce_lessons", "Relentless Pressure", "Непрерывный натиск", "+1% speed per active Survivor branch.", "+1% скорости за каждую активную ветку Survivor.", {{ { "speed_pct", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "ce_memory", branch_id::combat, 4, 22, currency_id::perk, "c_bruiser", "ce_tactics", "Battle Memory", "Боевая память", "+3% Survivor XP per active Survivor branch.", "+3% опыта Survivor за каждую активную ветку.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 3, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "ce_refined", branch_id::combat, 4, 26, currency_id::perk, "c_evasion", "ce_pressure", "Refined Drills", "Отточенная подготовка", "+0.5 melee hit and +0.5 dodge.", "+0,5 точности ближнего боя и +0,5 уклонения.", {{ { "melee_hit_flat", 0.5 }, { "dodge_flat", 0.5 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0, perk_kind::effect, perk_scaling::fixed, 0, 0 },
    { "ce_veteran_reflex", branch_id::combat, 5, 32, currency_id::perk, "ce_memory", "ce_refined", "Veteran Reflex", "Рефлекс ветерана", "+3% speed, +5% max stamina, +0.25 dodge.", "+3% скорости, +5% выносливости, +0,25 уклонения.", {{ { "speed_pct", 3 }, { "stamina_max_pct", 5 }, { "dodge_flat", 0.25 }, { nullptr, 0.0 } }}, 3, 0, perk_kind::effect, perk_scaling::fixed, 0, 0 },
    { "ce_warmaster", branch_id::combat, 6, 40, currency_id::major, "c_apex", "ce_veteran_reflex", "Warmaster", "Воевода", "All stat perks are 5% stronger.", "Все статовые перки на 5% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 0, 5 },
    { "se_lessons", branch_id::survival, 1, 3, currency_id::perk, "s_hardy", "", "Hard Lessons", "Тяжёлые уроки", "Survival stat perks are 5% stronger.", "Статовые перки выживания на 5% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 5, 0 },
    { "se_routine", branch_id::survival, 1, 6, currency_id::perk, "s_field", "", "Survival Routine", "Режим выживания", "+5% healing per active Survivor branch.", "+5% лечения за каждую активную ветку Survivor.", {{ { "healing_pct", 5 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "se_reserves", branch_id::survival, 2, 9, currency_id::perk, "s_pack", "se_lessons", "Deep Reserves", "Глубокие резервы", "+2% max stamina per active Survivor branch.", "+2% выносливости за каждую активную ветку Survivor.", {{ { "stamina_max_pct", 2 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "se_adaptive", branch_id::survival, 2, 12, currency_id::perk, "s_resilient", "se_routine", "Adaptive Survivor", "Адаптивный выживший", "+4% Survivor XP per owned major perk.", "+4% опыта Survivor за каждый большой перк.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 4, perk_kind::effect, perk_scaling::per_owned_major, 0, 0 },
    { "se_anchor", branch_id::survival, 3, 15, currency_id::major, "s_endurance", "se_reserves", "Anchor Point", "Точка опоры", "Survival stat perks are another 10% stronger.", "Статовые перки выживания ещё на 10% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 10, 0 },
    { "se_memory", branch_id::survival, 3, 18, currency_id::perk, "s_instinct", "se_adaptive", "Long Memory", "Долгая память", "+3% carry capacity per active Survivor branch.", "+3% грузоподъёмности за каждую активную ветку.", {{ { "carry_weight_pct", 3 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "se_hardened", branch_id::survival, 4, 22, currency_id::perk, "s_ironback", "se_anchor", "Hardened Practice", "Закалённая практика", "+4% healing per owned major perk.", "+4% лечения за каждый купленный большой перк.", {{ { "healing_pct", 4 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_owned_major, 0, 0 },
    { "se_grit", branch_id::survival, 4, 26, currency_id::perk, "s_recovery", "se_memory", "Grit", "Стойкость", "+10% healing and +8% max stamina.", "+10% лечения и +8% максимума выносливости.", {{ { "healing_pct", 10 }, { "stamina_max_pct", 8 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0, perk_kind::effect, perk_scaling::fixed, 0, 0 },
    { "se_carried", branch_id::survival, 5, 32, currency_id::perk, "se_hardened", "se_grit", "Lessons Carried", "Накопленный опыт", "+3% Survivor XP per active Survivor branch.", "+3% опыта Survivor за каждую активную ветку.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 3, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "se_indomitable", branch_id::survival, 6, 40, currency_id::major, "s_unbreakable", "se_carried", "Indomitable", "Несгибаемый", "All stat perks are 5% stronger.", "Все статовые перки на 5% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 0, 5 },
    { "me_economy", branch_id::mobility, 1, 3, currency_id::perk, "m_light", "", "Motion Economy", "Экономия движения", "Mobility stat perks are 5% stronger.", "Статовые перки мобильности на 5% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 5, 0 },
    { "me_practice", branch_id::mobility, 1, 6, currency_id::perk, "m_cardio", "", "Kinetic Practice", "Кинетическая практика", "-1% move cost per active Survivor branch.", "-1% стоимости движения за каждую активную ветку.", {{ { "move_cost_pct", -1 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "me_breath", branch_id::mobility, 2, 9, currency_id::perk, "m_stride", "me_economy", "Breath Cycle", "Цикл дыхания", "+2% max stamina per active Survivor branch.", "+2% выносливости за каждую активную ветку.", {{ { "stamina_max_pct", 2 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "me_road", branch_id::mobility, 2, 12, currency_id::perk, "m_breath", "me_practice", "Road Sense", "Чувство дороги", "+3% Survivor XP per active Survivor branch.", "+3% опыта Survivor за каждую активную ветку.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 3, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "me_flow", branch_id::mobility, 3, 15, currency_id::major, "m_parkour", "me_breath", "Flow Control", "Контроль потока", "Mobility stat perks are another 10% stronger.", "Статовые перки мобильности ещё на 10% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 10, 0 },
    { "me_stride", branch_id::mobility, 3, 18, currency_id::perk, "m_quick", "me_road", "Long Stride", "Длинный шаг", "+1% speed per active Survivor branch.", "+1% скорости за каждую активную ветку.", {{ { "speed_pct", 1 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "me_mastery", branch_id::mobility, 4, 22, currency_id::perk, "m_runner", "me_flow", "Kinetic Mastery", "Мастерство движения", "-0.5% move cost per owned major perk.", "-0,5% стоимости движения за каждый большой перк.", {{ { "move_cost_pct", -0.5 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_owned_major, 0, 0 },
    { "me_feather", branch_id::mobility, 4, 26, currency_id::perk, "m_marathon", "me_stride", "Featherstep", "Невесомый шаг", "+0.5 dodge and +2% speed.", "+0,5 уклонения и +2% скорости.", {{ { "dodge_flat", 0.5 }, { "speed_pct", 2 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0, perk_kind::effect, perk_scaling::fixed, 0, 0 },
    { "me_endless", branch_id::mobility, 5, 32, currency_id::perk, "me_mastery", "me_feather", "Endless Road", "Бесконечная дорога", "+3% Survivor XP per active Survivor branch.", "+3% опыта Survivor за каждую активную ветку.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 3, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "me_horizon", branch_id::mobility, 6, 40, currency_id::major, "m_untouchable", "me_endless", "Horizon Runner", "Бегущий к горизонту", "All stat perks are 5% stronger.", "Все статовые перки на 5% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 0, 5 },
    { "fe_iterate", branch_id::crafting, 1, 3, currency_id::perk, "f_hands", "", "Iterative Practice", "Практика итераций", "Crafting stat perks are 5% stronger.", "Статовые перки крафта на 5% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 5, 0 },
    { "fe_method", branch_id::crafting, 1, 6, currency_id::perk, "f_reader", "", "Methodical Work", "Методичная работа", "+3% crafting speed per active Survivor branch.", "+3% скорости крафта за каждую активную ветку.", {{ { "craft_speed_pct", 3 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "fe_notes", branch_id::crafting, 2, 9, currency_id::perk, "f_efficiency", "fe_iterate", "Living Notes", "Живые заметки", "+3% reading speed per active Survivor branch.", "+3% скорости чтения за каждую активную ветку.", {{ { "read_speed_pct", 3 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "fe_learning", branch_id::crafting, 2, 12, currency_id::perk, "f_study", "fe_method", "Learning by Making", "Учёба делом", "+4% Survivor XP per owned major perk.", "+4% опыта Survivor за каждый большой перк.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 4, perk_kind::effect, perk_scaling::per_owned_major, 0, 0 },
    { "fe_breakthrough", branch_id::crafting, 3, 15, currency_id::major, "f_workflow", "fe_notes", "Breakthrough", "Прорыв", "Crafting stat perks are another 10% stronger.", "Статовые перки крафта ещё на 10% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 10, 0 },
    { "fe_standard", branch_id::crafting, 3, 18, currency_id::perk, "f_quickstudy", "fe_learning", "Standardized Process", "Стандартизация", "+2% crafting speed per owned major perk.", "+2% скорости крафта за каждый большой перк.", {{ { "craft_speed_pct", 2 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_owned_major, 0, 0 },
    { "fe_systems", branch_id::crafting, 4, 22, currency_id::perk, "f_engineer", "fe_breakthrough", "Systems Thinking", "Системное мышление", "+2% reading speed per owned major perk.", "+2% скорости чтения за каждый большой перк.", {{ { "read_speed_pct", 2 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_owned_major, 0, 0 },
    { "fe_theory", branch_id::crafting, 4, 26, currency_id::perk, "f_scholar", "fe_standard", "Theory Into Practice", "Теория в практике", "+10% crafting and +10% reading speed.", "+10% скорости крафта и +10% скорости чтения.", {{ { "craft_speed_pct", 10 }, { "read_speed_pct", 10 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0, perk_kind::effect, perk_scaling::fixed, 0, 0 },
    { "fe_tuning", branch_id::crafting, 5, 32, currency_id::perk, "fe_systems", "fe_theory", "Fine Tuning", "Тонкая настройка", "+3% Survivor XP per active Survivor branch.", "+3% опыта Survivor за каждую активную ветку.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 3, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "fe_architect", branch_id::crafting, 6, 40, currency_id::major, "f_genius", "fe_tuning", "Architect Mind", "Разум архитектора", "All stat perks are 5% stronger.", "Все статовые перки на 5% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 0, 5 },
    { "ge_eye", branch_id::scavenging, 1, 3, currency_id::perk, "g_observer", "", "Sharp Eye", "Острый глаз", "Scavenging stat perks are 5% stronger.", "Статовые перки добычи на 5% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 5, 0 },
    { "ge_routes", branch_id::scavenging, 1, 6, currency_id::perk, "g_hauler", "", "Route Discipline", "Дисциплина маршрута", "-0.75% move cost per active Survivor branch.", "-0,75% стоимости движения за каждую активную ветку.", {{ { "move_cost_pct", -0.75 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "ge_load", branch_id::scavenging, 2, 9, currency_id::perk, "g_route", "ge_eye", "Load Planning", "Планирование груза", "+4% carry capacity per active Survivor branch.", "+4% грузоподъёмности за каждую активную ветку.", {{ { "carry_weight_pct", 4 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "ge_field", branch_id::scavenging, 2, 12, currency_id::perk, "g_pack", "ge_routes", "Field Experience", "Полевой опыт", "+3% Survivor XP per active Survivor branch.", "+3% опыта Survivor за каждую активную ветку.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 3, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "ge_opportunist", branch_id::scavenging, 3, 15, currency_id::major, "g_awareness", "ge_load", "Opportunist", "Оппортунист", "Scavenging stat perks are another 10% stronger.", "Статовые перки добычи ещё на 10% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 10, 0 },
    { "ge_cache", branch_id::scavenging, 3, 18, currency_id::perk, "g_endurance", "ge_field", "Cache Logic", "Логика тайников", "+0.25 PER per active Survivor branch.", "+0,25 восприятия за каждую активную ветку.", {{ { "per_flat", 0.25 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "ge_network", branch_id::scavenging, 4, 22, currency_id::perk, "g_pathfinder", "ge_opportunist", "Networked Routes", "Сеть маршрутов", "+2% speed per owned major perk.", "+2% скорости за каждый большой перк.", {{ { "speed_pct", 2 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 1, 0, perk_kind::effect, perk_scaling::per_owned_major, 0, 0 },
    { "ge_instinct", branch_id::scavenging, 4, 26, currency_id::perk, "g_mule", "ge_cache", "Scavenger Instinct", "Инстинкт добытчика", "+10% carry capacity and +0.5 PER.", "+10% грузоподъёмности и +0,5 восприятия.", {{ { "carry_weight_pct", 10 }, { "per_flat", 0.5 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0, perk_kind::effect, perk_scaling::fixed, 0, 0 },
    { "ge_wisdom", branch_id::scavenging, 5, 32, currency_id::perk, "ge_network", "ge_instinct", "Long Haul Wisdom", "Мудрость дальних рейдов", "+3% Survivor XP per owned major perk.", "+3% опыта Survivor за каждый большой перк.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 3, perk_kind::effect, perk_scaling::per_owned_major, 0, 0 },
    { "ge_nomad", branch_id::scavenging, 6, 40, currency_id::major, "g_legend", "ge_wisdom", "Nomad Legend", "Легенда кочевника", "All stat perks are 5% stronger.", "Все статовые перки на 5% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 0, 5 },
    { "ae_reflect", branch_id::mastery, 1, 3, currency_id::perk, "a_fast", "", "Reflection", "Рефлексия", "All stat perks are 2% stronger.", "Все статовые перки на 2% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 0, 2 },
    { "ae_cross", branch_id::mastery, 1, 6, currency_id::perk, "a_focus", "", "Cross Training", "Перекрёстная подготовка", "+5% Survivor XP per active Survivor branch.", "+5% опыта Survivor за каждую активную ветку.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 5, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "ae_foundation", branch_id::mastery, 2, 9, currency_id::perk, "a_adapt", "ae_reflect", "Strong Foundation", "Прочный фундамент", "+0.15 STR/DEX/PER/INT per active branch.", "+0,15 СИЛ/ЛОВ/ВОС/ИНТ за каждую активную ветку.", {{ { "str_flat", 0.15 }, { "dex_flat", 0.15 }, { "per_flat", 0.15 }, { "int_flat", 0.15 } }}, 4, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "ae_pattern", branch_id::mastery, 2, 12, currency_id::perk, "a_balance", "ae_cross", "Pattern Recognition", "Распознавание закономерностей", "+3% Survivor XP per owned major perk.", "+3% опыта Survivor за каждый большой перк.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 3, perk_kind::effect, perk_scaling::per_owned_major, 0, 0 },
    { "ae_milestone", branch_id::mastery, 3, 15, currency_id::major, "a_learning", "ae_foundation", "Milestone Discipline", "Дисциплина рубежей", "All stat perks are another 5% stronger.", "Все статовые перки ещё на 5% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 0, 5 },
    { "ae_integrate", branch_id::mastery, 3, 18, currency_id::perk, "a_insight", "ae_pattern", "Integration", "Интеграция", "+2% crafting and reading speed per active branch.", "+2% крафта и чтения за каждую активную ветку.", {{ { "craft_speed_pct", 2 }, { "read_speed_pct", 2 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 2, 0, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "ae_compound", branch_id::mastery, 4, 22, currency_id::perk, "a_growth", "ae_milestone", "Compounding Practice", "Накопительная практика", "All stat perks are another 5% stronger.", "Все статовые перки ещё на 5% сильнее.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 0, perk_kind::effect, perk_scaling::fixed, 0, 5 },
    { "ae_longgame", branch_id::mastery, 4, 26, currency_id::perk, "a_polymath", "ae_integrate", "Long Game", "Долгая игра", "+6% Survivor XP per active Survivor branch.", "+6% опыта Survivor за каждую активную ветку.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 6, perk_kind::effect, perk_scaling::per_active_branch, 0, 0 },
    { "ae_legacy", branch_id::mastery, 5, 32, currency_id::perk, "ae_compound", "ae_longgame", "Legacy Mindset", "Мышление наследия", "+0.05 STR/DEX/PER/INT per owned major perk.", "+0,05 СИЛ/ЛОВ/ВОС/ИНТ за каждый большой перк.", {{ { "str_flat", 0.05 }, { "dex_flat", 0.05 }, { "per_flat", 0.05 }, { "int_flat", 0.05 } }}, 4, 0, perk_kind::effect, perk_scaling::per_owned_major, 0, 0 },
    { "ae_ascendant", branch_id::mastery, 6, 40, currency_id::major, "a_transcendent", "ae_legacy", "Ascendant", "Восхождение", "All stat perks are 10% stronger and Survivor XP +50%.", "Все статовые перки на 10% сильнее, опыт Survivor +50%.", {{ { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 }, { nullptr, 0.0 } }}, 0, 50, perk_kind::effect, perk_scaling::fixed, 0, 10 },
    { "spc_c_juggernaut", branch_id::combat, 4, 15, currency_id::perk, "c_conditioning", "", "Juggernaut", "Штурмовик", "Commit to armored endurance: +10% stamina and +0.5 STR.", "Ставка на силовую выносливость: +10% выносливости и +0,5 СИЛ.", {{ { "stamina_max_pct", 10 }, { "str_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_c_duelist", branch_id::combat, 4, 15, currency_id::perk, "c_tempo", "", "Duelist", "Дуэлянт", "Commit to mobility and timing: +3% speed and +0.5 dodge.", "Ставка на мобильность и темп: +3% скорости и +0,5 уклонения.", {{ { "speed_pct", 3 }, { "dodge_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_c_tactician", branch_id::combat, 4, 15, currency_id::perk, "c_precision", "c_reflexes", "Tactician", "Тактик", "Commit to control: +0.5 PER and +0.25 melee hit.", "Ставка на контроль: +0,5 ВОС и +0,25 точности ближнего боя.", {{ { "per_flat", 0.5 }, { "melee_hit_flat", 0.25 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_c_juggernaut_cap", branch_id::combat, 5, 25, currency_id::major, "spc_c_juggernaut", "", "Iron Advance", "Железный натиск", "Juggernaut capstone: +1 STR, +12% stamina, +5% carry.", "Вершина штурмовика: +1 СИЛ, +12% выносливости, +5% груза.", {{ { "str_flat", 1 }, { "stamina_max_pct", 12 }, { "carry_weight_pct", 5 }, { nullptr, 0 } }}, 3, 0 },
    { "spc_c_duelist_cap", branch_id::combat, 5, 25, currency_id::major, "spc_c_duelist", "", "Perfect Tempo", "Идеальный темп", "Duelist capstone: +5% speed, +1 dodge, -3% move cost.", "Вершина дуэлянта: +5% скорости, +1 уклонение, -3% стоимости движения.", {{ { "speed_pct", 5 }, { "dodge_flat", 1 }, { "move_cost_pct", -3 }, { nullptr, 0 } }}, 3, 0 },
    { "spc_c_tactician_cap", branch_id::combat, 5, 25, currency_id::major, "spc_c_tactician", "", "Battlefield Control", "Контроль поля боя", "Tactician capstone: +1 PER, +0.75 melee hit, +3% speed.", "Вершина тактика: +1 ВОС, +0,75 точности, +3% скорости.", {{ { "per_flat", 1 }, { "melee_hit_flat", 0.75 }, { "speed_pct", 3 }, { nullptr, 0 } }}, 3, 0 },
    { "spc_s_nomad", branch_id::survival, 4, 15, currency_id::perk, "s_endurance", "", "Nomad", "Кочевник", "Commit to long expeditions: +8% stamina and +8% carry.", "Ставка на дальние походы: +8% выносливости и +8% груза.", {{ { "stamina_max_pct", 8 }, { "carry_weight_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_s_medic", branch_id::survival, 4, 15, currency_id::perk, "s_field", "s_resilient", "Field Medic", "Полевой медик", "Commit to recovery: +15% healing.", "Ставка на восстановление: +15% лечения.", {{ { "healing_pct", 15 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0 },
    { "spc_s_quartermaster", branch_id::survival, 4, 15, currency_id::perk, "s_pack", "", "Quartermaster", "Интендант", "Commit to preparation: +15% carry and +5% crafting speed.", "Ставка на подготовку: +15% груза и +5% скорости крафта.", {{ { "carry_weight_pct", 15 }, { "craft_speed_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_s_nomad_cap", branch_id::survival, 5, 25, currency_id::major, "spc_s_nomad", "", "Long Road", "Долгая дорога", "Nomad capstone: +15% stamina, +15% carry, -3% move cost.", "Вершина кочевника: +15% выносливости, +15% груза, -3% стоимости движения.", {{ { "stamina_max_pct", 15 }, { "carry_weight_pct", 15 }, { "move_cost_pct", -3 }, { nullptr, 0 } }}, 3, 0 },
    { "spc_s_medic_cap", branch_id::survival, 5, 25, currency_id::major, "spc_s_medic", "", "Trauma Veteran", "Ветеран травм", "Medic capstone: +30% healing and +8% stamina.", "Вершина медика: +30% лечения и +8% выносливости.", {{ { "healing_pct", 30 }, { "stamina_max_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_s_quartermaster_cap", branch_id::survival, 5, 25, currency_id::major, "spc_s_quartermaster", "", "Prepared for Anything", "Готов ко всему", "Quartermaster capstone: +25% carry and +8% crafting speed.", "Вершина интенданта: +25% груза и +8% скорости крафта.", {{ { "carry_weight_pct", 25 }, { "craft_speed_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_m_sprinter", branch_id::mobility, 4, 15, currency_id::perk, "m_cardio", "", "Sprinter", "Спринтер", "Commit to burst mobility: +3% speed and +5% stamina.", "Ставка на рывок: +3% скорости и +5% выносливости.", {{ { "speed_pct", 3 }, { "stamina_max_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_m_ghost", branch_id::mobility, 4, 15, currency_id::perk, "m_light", "m_parkour", "Ghost", "Призрак", "Commit to evasive movement: -4% move cost and +0.5 dodge.", "Ставка на уклончивость: -4% стоимости движения и +0,5 уклонения.", {{ { "move_cost_pct", -4 }, { "dodge_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_m_pathfinder", branch_id::mobility, 4, 15, currency_id::perk, "m_stride", "", "Pathfinder", "Путепроходец", "Commit to efficient travel: -3% move cost and +8% stamina.", "Ставка на эффективный путь: -3% стоимости движения и +8% выносливости.", {{ { "move_cost_pct", -3 }, { "stamina_max_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_m_sprinter_cap", branch_id::mobility, 5, 25, currency_id::major, "spc_m_sprinter", "", "Burst Engine", "Двигатель рывка", "Sprinter capstone: +6% speed and +10% stamina.", "Вершина спринтера: +6% скорости и +10% выносливости.", {{ { "speed_pct", 6 }, { "stamina_max_pct", 10 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_m_ghost_cap", branch_id::mobility, 5, 25, currency_id::major, "spc_m_ghost", "", "Vanishing Step", "Исчезающий шаг", "Ghost capstone: -7% move cost and +1 dodge.", "Вершина призрака: -7% стоимости движения и +1 уклонение.", {{ { "move_cost_pct", -7 }, { "dodge_flat", 1 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_m_pathfinder_cap", branch_id::mobility, 5, 25, currency_id::major, "spc_m_pathfinder", "", "Always a Route", "Путь всегда есть", "Pathfinder capstone: -5% move cost, +10% carry, +10% stamina.", "Вершина путепроходца: -5% стоимости движения, +10% груза, +10% выносливости.", {{ { "move_cost_pct", -5 }, { "carry_weight_pct", 10 }, { "stamina_max_pct", 10 }, { nullptr, 0 } }}, 3, 0 },
    { "spc_f_systems", branch_id::crafting, 4, 15, currency_id::perk, "f_engineer", "", "Systems Engineer", "Системный инженер", "Commit to engineering: +10% crafting speed and +0.5 INT.", "Ставка на инженерию: +10% скорости крафта и +0,5 ИНТ.", {{ { "craft_speed_pct", 10 }, { "int_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_f_improviser", branch_id::crafting, 4, 15, currency_id::perk, "f_hands", "f_workflow", "Improviser", "Импровизатор", "Commit to practical work: +8% crafting speed and +5% carry.", "Ставка на практику: +8% скорости крафта и +5% груза.", {{ { "craft_speed_pct", 8 }, { "carry_weight_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_f_researcher", branch_id::crafting, 4, 15, currency_id::perk, "f_reader", "f_scholar", "Researcher", "Исследователь", "Commit to theory: +10% reading speed and +0.5 INT.", "Ставка на теорию: +10% скорости чтения и +0,5 ИНТ.", {{ { "read_speed_pct", 10 }, { "int_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_f_systems_cap", branch_id::crafting, 5, 25, currency_id::major, "spc_f_systems", "", "Systems Architect", "Архитектор систем", "Engineer capstone: +18% crafting speed and +1 INT.", "Вершина инженера: +18% скорости крафта и +1 ИНТ.", {{ { "craft_speed_pct", 18 }, { "int_flat", 1 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_f_improviser_cap", branch_id::crafting, 5, 25, currency_id::major, "spc_f_improviser", "", "Make It Work", "Заставить работать", "Improviser capstone: +15% crafting speed and +10% carry.", "Вершина импровизатора: +15% скорости крафта и +10% груза.", {{ { "craft_speed_pct", 15 }, { "carry_weight_pct", 10 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_f_researcher_cap", branch_id::crafting, 5, 25, currency_id::major, "spc_f_researcher", "", "Applied Theory", "Прикладная теория", "Researcher capstone: +20% reading, +1 INT, +5% crafting speed.", "Вершина исследователя: +20% чтения, +1 ИНТ, +5% скорости крафта.", {{ { "read_speed_pct", 20 }, { "int_flat", 1 }, { "craft_speed_pct", 5 }, { nullptr, 0 } }}, 3, 0 },
    { "spc_g_prospector", branch_id::scavenging, 4, 15, currency_id::perk, "g_observer", "", "Prospector", "Искатель", "Commit to finding value: +0.5 PER and +5% carry.", "Ставка на поиск ценного: +0,5 ВОС и +5% груза.", {{ { "per_flat", 0.5 }, { "carry_weight_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_g_courier", branch_id::scavenging, 4, 15, currency_id::perk, "g_pack", "g_endurance", "Courier", "Курьер", "Commit to loaded travel: +15% carry and -2% move cost.", "Ставка на движение с грузом: +15% груза и -2% стоимости движения.", {{ { "carry_weight_pct", 15 }, { "move_cost_pct", -2 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_g_investigator", branch_id::scavenging, 4, 15, currency_id::perk, "g_awareness", "", "Investigator", "Исследователь руин", "Commit to reading the environment: +1 PER and +5% reading speed.", "Ставка на анализ окружения: +1 ВОС и +5% скорости чтения.", {{ { "per_flat", 1 }, { "read_speed_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_g_prospector_cap", branch_id::scavenging, 5, 25, currency_id::major, "spc_g_prospector", "", "Nothing Wasted", "Ничего не пропадает", "Prospector capstone: +1 PER and +10% carry.", "Вершина искателя: +1 ВОС и +10% груза.", {{ { "per_flat", 1 }, { "carry_weight_pct", 10 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0 },
    { "spc_g_courier_cap", branch_id::scavenging, 5, 25, currency_id::major, "spc_g_courier", "", "Heavy Route", "Тяжёлый маршрут", "Courier capstone: +25% carry, -4% move cost, +8% stamina.", "Вершина курьера: +25% груза, -4% стоимости движения, +8% выносливости.", {{ { "carry_weight_pct", 25 }, { "move_cost_pct", -4 }, { "stamina_max_pct", 8 }, { nullptr, 0 } }}, 3, 0 },
    { "spc_g_investigator_cap", branch_id::scavenging, 5, 25, currency_id::major, "spc_g_investigator", "", "Read the Ruins", "Читать руины", "Investigator capstone: +1.5 PER, +10% reading, -2% move cost.", "Вершина исследователя: +1,5 ВОС, +10% чтения, -2% стоимости движения.", {{ { "per_flat", 1.5 }, { "read_speed_pct", 10 }, { "move_cost_pct", -2 }, { nullptr, 0 } }}, 3, 0 },
    { "spc_a_specialist", branch_id::mastery, 4, 15, currency_id::perk, "a_focus", "a_growth", "Specialist", "Специалист", "Commit to depth: +10% Survivor XP.", "Ставка на глубину: +10% опыта Survivor.", {{ { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 0, 10 },
    { "spc_a_polymath", branch_id::mastery, 4, 15, currency_id::perk, "a_balance", "a_polymath", "Polymath Path", "Путь универсала", "Commit to breadth: +0.25 to all primary stats.", "Ставка на широту: +0,25 ко всем основным характеристикам.", {{ { "str_flat", 0.25 }, { "dex_flat", 0.25 }, { "per_flat", 0.25 }, { "int_flat", 0.25 } }}, 4, 0 },
    { "spc_a_selfteacher", branch_id::mastery, 4, 15, currency_id::perk, "a_adapt", "", "Self-Teacher", "Самоучка", "Commit to self-directed growth: +5% reading, +5% crafting, +5% Survivor XP.", "Ставка на самостоятельный рост: +5% чтения, +5% крафта, +5% опыта Survivor.", {{ { "read_speed_pct", 5 }, { "craft_speed_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 5 },
    { "spc_a_specialist_cap", branch_id::mastery, 5, 25, currency_id::major, "spc_a_specialist", "", "Deep Practice", "Глубокая практика", "Specialist capstone: +20% Survivor XP.", "Вершина специалиста: +20% опыта Survivor.", {{ { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 0, 20 },
    { "spc_a_polymath_cap", branch_id::mastery, 5, 25, currency_id::major, "spc_a_polymath", "", "Cross Discipline", "Перекрёстная дисциплина", "Polymath capstone: +0.5 to all primary stats.", "Вершина универсала: +0,5 ко всем основным характеристикам.", {{ { "str_flat", 0.5 }, { "dex_flat", 0.5 }, { "per_flat", 0.5 }, { "int_flat", 0.5 } }}, 4, 0 },
    { "spc_a_selfteacher_cap", branch_id::mastery, 5, 25, currency_id::major, "spc_a_selfteacher", "", "Compounding Insight", "Накопительное понимание", "Self-teacher capstone: +10% reading, +10% crafting, +10% Survivor XP.", "Вершина самоучки: +10% чтения, +10% крафта, +10% опыта Survivor.", {{ { "read_speed_pct", 10 }, { "craft_speed_pct", 10 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 10 },
    { "mg_arcane_focus", branch_id::mastery, 1, 2, currency_id::perk, "", "", "Arcane Focus", "Магический фокус", "Magiclysm: +0.5 effective Spellcraft.", "Magiclysm: +0,5 к эффективному Spellcraft.", {{ { "mg_spellcraft_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mg_mana_sensitivity", branch_id::mastery, 2, 5, currency_id::perk, "mg_arcane_focus", "", "Mana Sensitivity", "Чувствительность к мане", "Magiclysm: +8% maximum mana.", "Magiclysm: +8% к максимуму маны.", {{ { "mg_mana_max_pct", 8 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mg_battlemage", branch_id::mastery, 2, 5, currency_id::perk, "mg_arcane_focus", "", "Invocation Drills", "Тренировка заклинаний", "Magiclysm: spell casting time -5%.", "Magiclysm: время сотворения заклинаний -5%.", {{ { "mg_cast_time_pct", -5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mg_wayfarer", branch_id::mastery, 2, 5, currency_id::perk, "mg_arcane_focus", "", "Arcane Reach", "Магическая дальность", "Magiclysm: spell range +5%.", "Magiclysm: дальность заклинаний +5%.", {{ { "mg_range_pct", 5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mg_mana_regeneration", branch_id::mastery, 3, 9, currency_id::perk, "mg_mana_sensitivity", "", "Mana Regeneration", "Регенерация маны", "Magiclysm: mana regeneration +10%.", "Magiclysm: восстановление маны +10%.", {{ { "mg_mana_regen_pct", 10 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mg_stable_formula", branch_id::mastery, 3, 9, currency_id::perk, "mg_battlemage", "", "Stable Formula", "Стабильная формула", "Magiclysm: spell failure chance -7% multiplicatively.", "Magiclysm: шанс провала заклинаний -7% мультипликативно.", {{ { "mg_fail_pct", -7 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mg_shaped_evocation", branch_id::mastery, 3, 9, currency_id::perk, "mg_wayfarer", "", "Shaped Evocation", "Формованная эвокация", "Magiclysm: spell potency +6% (damage/healing magnitude).", "Magiclysm: мощность заклинаний +6% (урон/лечение).", {{ { "mg_spell_power_pct", 6 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mg_efficient_channels", branch_id::mastery, 4, 14, currency_id::perk, "mg_mana_regeneration", "", "Efficient Channels", "Эффективные каналы", "Magiclysm: spell mana cost -6%.", "Magiclysm: стоимость заклинаний в мане -6%.", {{ { "mg_spell_cost_pct", -6 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mg_spellcraft_drills", branch_id::mastery, 4, 14, currency_id::perk, "mg_stable_formula", "", "Spellcraft Drills", "Практика Spellcraft", "Magiclysm: +0.5 effective Spellcraft.", "Magiclysm: +0,5 к эффективному Spellcraft.", {{ { "mg_spellcraft_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mg_sustained_weave", branch_id::mastery, 4, 14, currency_id::perk, "mg_shaped_evocation", "", "Sustained Weave", "Удержание плетения", "Magiclysm: spell duration +8%.", "Magiclysm: длительность заклинаний +8%.", {{ { "mg_duration_pct", 8 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mg_deep_reservoir", branch_id::mastery, 5, 20, currency_id::perk, "mg_efficient_channels", "", "Deep Reservoir", "Глубокий резерв", "Magiclysm: +12% maximum mana and +8% mana regeneration.", "Magiclysm: +12% максимум маны и +8% восстановление маны.", {{ { "mg_mana_max_pct", 12 }, { "mg_mana_regen_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mg_quick_invocation", branch_id::mastery, 5, 20, currency_id::perk, "mg_spellcraft_drills", "", "Quick Invocation", "Быстрое сотворение", "Magiclysm: casting time -8% and failure chance -5%.", "Magiclysm: время сотворения -8%, шанс провала -5%.", {{ { "mg_cast_time_pct", -8 }, { "mg_fail_pct", -5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mg_arcane_geometry", branch_id::mastery, 5, 20, currency_id::perk, "mg_sustained_weave", "", "Arcane Geometry", "Магическая геометрия", "Magiclysm: area of effect +6% and range +5%.", "Magiclysm: площадь действия +6%, дальность +5%.", {{ { "mg_aoe_pct", 6 }, { "mg_range_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mg_mana_mastery", branch_id::mastery, 6, 25, currency_id::major, "mg_deep_reservoir", "", "Mana Mastery", "Мастерство маны", "Magiclysm mana capstone: spell cost -10%, mana regeneration +15%.", "Вершина маны Magiclysm: стоимость заклинаний -10%, регенерация маны +15%.", {{ { "mg_spell_cost_pct", -10 }, { "mg_mana_regen_pct", 15 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mg_ritual_craft", branch_id::mastery, 6, 25, currency_id::major, "mg_quick_invocation", "", "Ritual Mastery", "Мастерство ритуалов", "Magiclysm control capstone: +0.75 Spellcraft and +12% spell XP.", "Вершина контроля Magiclysm: +0,75 Spellcraft и +12% опыта заклинаний.", {{ { "mg_spellcraft_flat", 0.75 }, { "mg_spell_xp_pct", 12 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mg_high_thaumaturgy", branch_id::mastery, 6, 25, currency_id::major, "mg_arcane_geometry", "", "High Thaumaturgy", "Высшая тауматургия", "Magiclysm projection capstone: spell potency +10%, duration +10%.", "Вершина проекции Magiclysm: мощность +10%, длительность +10%.", {{ { "mg_spell_power_pct", 10 }, { "mg_duration_pct", 10 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mg_efficient_theory", branch_id::mastery, 7, 30, currency_id::perk, "mg_mana_mastery", "mg_ritual_craft", "Efficient Theory", "Эффективная теория", "Magiclysm convergence: spell cost -5%, spell XP +8%.", "Сведение путей Magiclysm: стоимость -5%, опыт заклинаний +8%.", {{ { "mg_spell_cost_pct", -5 }, { "mg_spell_xp_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mg_combat_weave", branch_id::mastery, 7, 30, currency_id::perk, "mg_ritual_craft", "mg_high_thaumaturgy", "Combat Weave", "Боевое плетение", "Magiclysm convergence: casting time -5%, spell potency +8%.", "Сведение путей Magiclysm: время сотворения -5%, мощность +8%.", {{ { "mg_cast_time_pct", -5 }, { "mg_spell_power_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mg_resonant_reserve", branch_id::mastery, 7, 30, currency_id::perk, "mg_mana_mastery", "mg_high_thaumaturgy", "Resonant Reserve", "Резонансный резерв", "Magiclysm convergence: maximum mana +10%, spell duration +8%.", "Сведение путей Magiclysm: максимум маны +10%, длительность +8%.", {{ { "mg_mana_max_pct", 10 }, { "mg_duration_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mg_archmage", branch_id::mastery, 8, 40, currency_id::major, "mg_efficient_theory", "mg_combat_weave", "Archmage", "Архимаг", "Magiclysm apex: +0.75 Spellcraft, -5% failure, +8% potency, +8% spell XP.", "Вершина Magiclysm: +0,75 Spellcraft, -5% провала, +8% мощность, +8% опыт заклинаний.", {{ { "mg_spellcraft_flat", 0.75 }, { "mg_fail_pct", -5 }, { "mg_spell_power_pct", 8 }, { "mg_spell_xp_pct", 8 } }}, 4, 0, perk_kind::effect },

    { "mom_mental_focus", branch_id::mastery, 1, 2, currency_id::perk, "", "", "Psionic Focus", "Псионический фокус", "Mind Over Matter powers: +0.5 effective Metaphysics while channeling.", "Силы Mind Over Matter: +0,5 к эффективной Metaphysics при ченнелинге.", {{ { "mom_metaphysics_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mom_still_mind", branch_id::mastery, 2, 5, currency_id::perk, "mom_mental_focus", "", "Still Mind", "Спокойный разум", "Mind Over Matter: power failure chance -6%.", "Mind Over Matter: шанс провала псионических сил -6%.", {{ { "mom_fail_pct", -6 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mom_neural_reserve", branch_id::mastery, 2, 5, currency_id::perk, "mom_mental_focus", "", "Neural Reserve", "Нейронный резерв", "Mind Over Matter: psionic stamina cost -5%.", "Mind Over Matter: затраты выносливости на псионику -5%.", {{ { "mom_spell_cost_pct", -5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mom_kinetic_control", branch_id::mastery, 2, 5, currency_id::perk, "mom_mental_focus", "", "Kinetic Control", "Кинетический контроль", "Mind Over Matter: power range +5%.", "Mind Over Matter: дальность псионических сил +5%.", {{ { "mom_range_pct", 5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mom_channel_discipline", branch_id::mastery, 3, 9, currency_id::perk, "mom_still_mind", "", "Channel Discipline", "Дисциплина канала", "Mind Over Matter: activation/casting time -5%.", "Mind Over Matter: время активации/применения -5%.", {{ { "mom_cast_time_pct", -5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mom_efficient_channel", branch_id::mastery, 3, 9, currency_id::perk, "mom_neural_reserve", "", "Efficient Channel", "Эффективный канал", "Mind Over Matter: psionic stamina cost -6%.", "Mind Over Matter: затраты выносливости на псионику -6%.", {{ { "mom_spell_cost_pct", -6 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mom_psionic_pressure", branch_id::mastery, 3, 9, currency_id::perk, "mom_kinetic_control", "", "Psionic Pressure", "Псионическое давление", "Mind Over Matter: psionic power potency +6%.", "Mind Over Matter: мощность псионических сил +6%.", {{ { "mom_spell_power_pct", 6 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mom_metaphysical_method", branch_id::mastery, 4, 14, currency_id::perk, "mom_channel_discipline", "", "Metaphysical Method", "Метод метафизики", "Mind Over Matter powers: +0.5 effective Metaphysics while channeling.", "Силы Mind Over Matter: +0,5 к эффективной Metaphysics при ченнелинге.", {{ { "mom_metaphysics_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mom_controlled_exposure", branch_id::mastery, 4, 14, currency_id::perk, "mom_efficient_channel", "", "Controlled Exposure", "Контролируемое воздействие", "Mind Over Matter: power-use XP +8%. Nether Attunement itself is not rewritten.", "Mind Over Matter: опыт за применение сил +8%. Сам Nether Attunement не переписывается.", {{ { "mom_spell_xp_pct", 8 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mom_extended_pattern", branch_id::mastery, 4, 14, currency_id::perk, "mom_psionic_pressure", "", "Extended Pattern", "Продлённый паттерн", "Mind Over Matter: power duration +8%.", "Mind Over Matter: длительность псионических сил +8%.", {{ { "mom_duration_pct", 8 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "mom_mental_lattice", branch_id::mastery, 5, 20, currency_id::perk, "mom_metaphysical_method", "", "Mental Lattice", "Ментальная решётка", "Mind Over Matter: failure chance -7%, activation time -5%.", "Mind Over Matter: шанс провала -7%, время активации -5%.", {{ { "mom_fail_pct", -7 }, { "mom_cast_time_pct", -5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mom_recovery_cycle", branch_id::mastery, 5, 20, currency_id::perk, "mom_controlled_exposure", "", "Recovery Cycle", "Цикл восстановления", "Mind Over Matter: stamina cost -7%, power-use XP +8%.", "Mind Over Matter: стоимость по выносливости -7%, опыт сил +8%.", {{ { "mom_spell_cost_pct", -7 }, { "mom_spell_xp_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mom_field_shaping", branch_id::mastery, 5, 20, currency_id::perk, "mom_extended_pattern", "", "Field Shaping", "Формирование поля", "Mind Over Matter: area of effect +6%, range +5%.", "Mind Over Matter: площадь действия +6%, дальность +5%.", {{ { "mom_aoe_pct", 6 }, { "mom_range_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mom_combat_focus", branch_id::mastery, 6, 25, currency_id::major, "mom_mental_lattice", "", "Noetic Control", "Ноэтический контроль", "Mind Over Matter control capstone: +0.75 effective Metaphysics while channeling, failure chance -8%.", "Вершина контроля Mind Over Matter: +0,75 эффективной Metaphysics при ченнелинге, шанс провала -8%.", {{ { "mom_metaphysics_flat", 0.75 }, { "mom_fail_pct", -8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mom_nether_discipline", branch_id::mastery, 6, 25, currency_id::major, "mom_recovery_cycle", "", "Nether Discipline", "Дисциплина Низины", "Mind Over Matter economy capstone: stamina cost -10%, power-use XP +12%.", "Вершина экономии Mind Over Matter: стоимость по выносливости -10%, опыт сил +12%.", {{ { "mom_spell_cost_pct", -10 }, { "mom_spell_xp_pct", 12 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mom_noetic_projection", branch_id::mastery, 6, 25, currency_id::major, "mom_field_shaping", "", "Noetic Projection", "Ноэтическая проекция", "Mind Over Matter projection capstone: potency +10%, duration +10%.", "Вершина проекции Mind Over Matter: мощность +10%, длительность +10%.", {{ { "mom_spell_power_pct", 10 }, { "mom_duration_pct", 10 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mom_stable_channel", branch_id::mastery, 7, 30, currency_id::perk, "mom_combat_focus", "mom_nether_discipline", "Stable Channel", "Стабильный канал", "Mind Over Matter convergence: failure -5%, stamina cost -5%.", "Сведение путей Mind Over Matter: провал -5%, стоимость по выносливости -5%.", {{ { "mom_fail_pct", -5 }, { "mom_spell_cost_pct", -5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mom_precise_manifestation", branch_id::mastery, 7, 30, currency_id::perk, "mom_combat_focus", "mom_noetic_projection", "Precise Manifestation", "Точная манифестация", "Mind Over Matter convergence: activation time -5%, range +6%.", "Сведение путей Mind Over Matter: время активации -5%, дальность +6%.", {{ { "mom_cast_time_pct", -5 }, { "mom_range_pct", 6 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mom_efficient_force", branch_id::mastery, 7, 30, currency_id::perk, "mom_nether_discipline", "mom_noetic_projection", "Efficient Force", "Эффективная сила", "Mind Over Matter convergence: stamina cost -5%, potency +8%.", "Сведение путей Mind Over Matter: стоимость по выносливости -5%, мощность +8%.", {{ { "mom_spell_cost_pct", -5 }, { "mom_spell_power_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "mom_transcendent_focus", branch_id::mastery, 8, 40, currency_id::major, "mom_stable_channel", "mom_efficient_force", "Transcendent Focus", "Трансцендентный фокус", "Mind Over Matter apex: +0.75 effective Metaphysics while channeling, failure -5%, potency +8%, power XP +8%.", "Вершина Mind Over Matter: +0,75 эффективной Metaphysics при ченнелинге, провал -5%, мощность +8%, опыт сил +8%.", {{ { "mom_metaphysics_flat", 0.75 }, { "mom_fail_pct", -5 }, { "mom_spell_power_pct", 8 }, { "mom_spell_xp_pct", 8 } }}, 4, 0, perk_kind::effect },

    { "xe_anomaly_method", branch_id::mastery, 1, 2, currency_id::perk, "", "", "Anomaly Method", "Метод аномалий", "Xedra Evolved: +0.5 effective Deduction.", "Xedra Evolved: +0,5 к эффективной Deduction.", {{ { "xe_deduction_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "xe_field_agent", branch_id::mastery, 2, 5, currency_id::perk, "xe_anomaly_method", "", "XEDRA Field Analysis", "Полевой анализ XEDRA", "Xedra Evolved: +0.5 effective Deduction.", "Xedra Evolved: +0,5 к эффективной Deduction.", {{ { "xe_deduction_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "xe_dross_resonance", branch_id::mastery, 2, 5, currency_id::perk, "xe_anomaly_method", "", "Dreamdross Resonance", "Резонанс дримдросса", "Xedra Evolved: +8% maximum mana.", "Xedra Evolved: +8% к максимуму маны.", {{ { "xe_mana_max_pct", 8 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "xe_dimensional_hunter", branch_id::mastery, 2, 5, currency_id::perk, "xe_anomaly_method", "", "Liminal Reach", "Пограничная дальность", "Xedra Evolved: spell/power range +5%.", "Xedra Evolved: дальность заклинаний/сил +5%.", {{ { "xe_range_pct", 5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "xe_gramarye_studies", branch_id::mastery, 3, 9, currency_id::perk, "xe_field_agent", "", "Gramarye Studies", "Изучение Gramarye", "Xedra Evolved: +0.5 effective Gramarye for fae magicks.", "Xedra Evolved: +0,5 к эффективной Gramarye для магии фей.", {{ { "xe_gramarye_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "xe_dream_metabolism", branch_id::mastery, 3, 9, currency_id::perk, "xe_dross_resonance", "", "Dream Metabolism", "Метаболизм сновидений", "Xedra Evolved: mana regeneration +10%.", "Xedra Evolved: восстановление маны +10%.", {{ { "xe_mana_regen_pct", 10 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "xe_fast_manifestation", branch_id::mastery, 3, 9, currency_id::perk, "xe_dimensional_hunter", "", "Fast Manifestation", "Быстрая манифестация", "Xedra Evolved: casting/activation time -5%.", "Xedra Evolved: время сотворения/активации -5%.", {{ { "xe_cast_time_pct", -5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "xe_dimensional_model", branch_id::mastery, 4, 14, currency_id::perk, "xe_gramarye_studies", "", "Dimensional Model", "Модель измерений", "Xedra Evolved: spell failure chance -6%.", "Xedra Evolved: шанс провала заклинаний -6%.", {{ { "xe_fail_pct", -6 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "xe_efficient_oneiromancy", branch_id::mastery, 4, 14, currency_id::perk, "xe_dream_metabolism", "", "Efficient Oneiromancy", "Эффективная онейромантия", "Xedra Evolved: mana cost -6% for Xedra spells.", "Xedra Evolved: стоимость маны заклинаний Xedra -6%.", {{ { "xe_spell_cost_pct", -6 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "xe_oneiric_force", branch_id::mastery, 4, 14, currency_id::perk, "xe_fast_manifestation", "", "Oneiric Force", "Онейрическая сила", "Xedra Evolved: spell/power potency +6%.", "Xedra Evolved: мощность заклинаний/сил +6%.", {{ { "xe_spell_power_pct", 6 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "xe_pattern_archive", branch_id::mastery, 5, 20, currency_id::perk, "xe_dimensional_model", "", "Pattern Archive", "Архив паттернов", "Xedra Evolved: +0.5 Deduction and +8% spell XP.", "Xedra Evolved: +0,5 Deduction и +8% опыта заклинаний.", {{ { "xe_deduction_flat", 0.5 }, { "xe_spell_xp_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "xe_dream_reservoir", branch_id::mastery, 5, 20, currency_id::perk, "xe_efficient_oneiromancy", "", "Dream Reservoir", "Резерв сновидений", "Xedra Evolved: +12% maximum mana and +8% mana regeneration.", "Xedra Evolved: +12% максимум маны и +8% восстановление маны.", {{ { "xe_mana_max_pct", 12 }, { "xe_mana_regen_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "xe_liminal_persistence", branch_id::mastery, 5, 20, currency_id::perk, "xe_oneiric_force", "", "Liminal Persistence", "Пограничная устойчивость", "Xedra Evolved: duration +8%, area of effect +6%.", "Xedra Evolved: длительность +8%, площадь действия +6%.", {{ { "xe_duration_pct", 8 }, { "xe_aoe_pct", 6 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "xe_occult_engineer", branch_id::mastery, 6, 25, currency_id::major, "xe_pattern_archive", "", "Occult Engineer", "Оккультный инженер", "Xedra Evolved analysis capstone: +0.75 Deduction and +0.75 Gramarye.", "Вершина анализа Xedra Evolved: +0,75 Deduction и +0,75 Gramarye.", {{ { "xe_deduction_flat", 0.75 }, { "xe_gramarye_flat", 0.75 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "xe_dream_economy", branch_id::mastery, 6, 25, currency_id::major, "xe_dream_reservoir", "", "Dream Economy", "Экономия сновидений", "Xedra Evolved dream capstone: mana cost -10%, mana regeneration +15%.", "Вершина сновидений Xedra Evolved: стоимость маны -10%, регенерация +15%.", {{ { "xe_spell_cost_pct", -10 }, { "xe_mana_regen_pct", 15 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "xe_reality_shaper", branch_id::mastery, 6, 25, currency_id::major, "xe_liminal_persistence", "", "Reality Shaper", "Формирователь реальности", "Xedra Evolved projection capstone: potency +10%, range +8%.", "Вершина проекции Xedra Evolved: мощность +10%, дальность +8%.", {{ { "xe_spell_power_pct", 10 }, { "xe_range_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "xe_dream_theorist", branch_id::mastery, 7, 30, currency_id::perk, "xe_occult_engineer", "xe_dream_economy", "Dream Theorist", "Теоретик сновидений", "Xedra Evolved convergence: spell XP +8%, mana cost -5%.", "Сведение путей Xedra Evolved: опыт заклинаний +8%, стоимость маны -5%.", {{ { "xe_spell_xp_pct", 8 }, { "xe_spell_cost_pct", -5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "xe_liminal_engineer", branch_id::mastery, 7, 30, currency_id::perk, "xe_occult_engineer", "xe_reality_shaper", "Liminal Engineer", "Пограничный инженер", "Xedra Evolved convergence: failure -5%, cast time -5%.", "Сведение путей Xedra Evolved: провал -5%, время сотворения -5%.", {{ { "xe_fail_pct", -5 }, { "xe_cast_time_pct", -5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "xe_oneiric_architect", branch_id::mastery, 7, 30, currency_id::perk, "xe_dream_economy", "xe_reality_shaper", "Oneiric Architect", "Онейрический архитектор", "Xedra Evolved convergence: potency +8%, duration +8%.", "Сведение путей Xedra Evolved: мощность +8%, длительность +8%.", {{ { "xe_spell_power_pct", 8 }, { "xe_duration_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "xe_boundary_master", branch_id::mastery, 8, 40, currency_id::major, "xe_dream_theorist", "xe_oneiric_architect", "Boundary Master", "Мастер границы", "Xedra Evolved apex: +0.75 Deduction, +0.5 Gramarye, failure -5%, potency +8%.", "Вершина Xedra Evolved: +0,75 Deduction, +0,5 Gramarye, провал -5%, мощность +8%.", {{ { "xe_deduction_flat", 0.75 }, { "xe_gramarye_flat", 0.5 }, { "xe_fail_pct", -5 }, { "xe_spell_power_pct", 8 } }}, 4, 0, perk_kind::effect },

    { "af_systems_operator", branch_id::mastery, 1, 2, currency_id::perk, "", "", "Systems Operator", "Оператор систем", "Aftershock Exoplanet: +0.25 effective Smartgun and +0.25 effective Metaphysics while channeling esper powers.", "Aftershock Exoplanet: +0,25 к Smartgun и +0,25 к эффективной Metaphysics при ченнелинге эспер-сил.", {{ { "af_smartgun_flat", 0.25 }, { "af_metaphysics_flat", 0.25 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "af_targeting_link", branch_id::mastery, 2, 5, currency_id::perk, "af_systems_operator", "", "Targeting Link", "Связь с прицелом", "Aftershock Exoplanet: +0.25 effective Smartgun.", "Aftershock Exoplanet: +0,25 к эффективному Smartgun.", {{ { "af_smartgun_flat", 0.25 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "af_conditioning", branch_id::mastery, 2, 5, currency_id::perk, "af_systems_operator", "", "Psi Endurance", "Пси-выносливость", "Aftershock Exoplanet esper powers: stamina cost -5%.", "Псионика Aftershock Exoplanet: затраты выносливости -5%.", {{ { "af_spell_cost_pct", -5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "af_expedition_logistics", branch_id::mastery, 2, 5, currency_id::perk, "af_systems_operator", "", "Vector Projection", "Векторная проекция", "Aftershock Exoplanet esper powers: range +5%.", "Псионика Aftershock Exoplanet: дальность +5%.", {{ { "af_range_pct", 5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "af_predictive_fire", branch_id::mastery, 3, 9, currency_id::perk, "af_targeting_link", "", "Predictive Fire", "Предиктивный огонь", "Aftershock Exoplanet: +0.25 effective Smartgun.", "Aftershock Exoplanet: +0,25 к эффективному Smartgun.", {{ { "af_smartgun_flat", 0.25 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "af_metaphysical_training", branch_id::mastery, 3, 9, currency_id::perk, "af_conditioning", "", "Metaphysical Training", "Тренировка метафизики", "Aftershock Exoplanet esper powers: +0.5 effective Metaphysics while channeling.", "Эспер-силы Aftershock Exoplanet: +0,5 к эффективной Metaphysics при ченнелинге.", {{ { "af_metaphysics_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "af_telekinetic_geometry", branch_id::mastery, 3, 9, currency_id::perk, "af_expedition_logistics", "", "Esper Geometry", "Геометрия эспера", "Aftershock Exoplanet esper powers: area of effect +6%.", "Псионика Aftershock Exoplanet: площадь действия +6%.", {{ { "af_aoe_pct", 6 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "af_sensor_fusion", branch_id::mastery, 4, 14, currency_id::perk, "af_predictive_fire", "", "Sensor Fusion", "Слияние сенсоров", "Aftershock Exoplanet: +0.25 effective Smartgun.", "Aftershock Exoplanet: +0,25 к эффективному Smartgun.", {{ { "af_smartgun_flat", 0.25 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "af_stable_esper", branch_id::mastery, 4, 14, currency_id::perk, "af_metaphysical_training", "", "Stable Esper", "Стабильный эспер", "Aftershock Exoplanet esper powers: failure chance -7%.", "Псионика Aftershock Exoplanet: шанс провала -7%.", {{ { "af_fail_pct", -7 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "af_esper_force", branch_id::mastery, 4, 14, currency_id::perk, "af_telekinetic_geometry", "", "Esper Force", "Сила эспера", "Aftershock Exoplanet esper powers: potency +6%.", "Псионика Aftershock Exoplanet: мощность +6%.", {{ { "af_spell_power_pct", 6 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "af_combat_technician", branch_id::mastery, 5, 20, currency_id::perk, "af_sensor_fusion", "", "Combat Technician", "Боевой техник", "Aftershock Exoplanet: +0.5 effective Smartgun.", "Aftershock Exoplanet: +0,5 к эффективному Smartgun.", {{ { "af_smartgun_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "af_efficient_esper", branch_id::mastery, 5, 20, currency_id::perk, "af_stable_esper", "", "Efficient Esper", "Эффективный эспер", "Aftershock Exoplanet esper powers: stamina cost -7%, power XP +8%.", "Псионика Aftershock Exoplanet: стоимость по выносливости -7%, опыт сил +8%.", {{ { "af_spell_cost_pct", -7 }, { "af_spell_xp_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "af_sustained_phenomena", branch_id::mastery, 5, 20, currency_id::perk, "af_esper_force", "", "Sustained Phenomena", "Устойчивые феномены", "Aftershock Exoplanet esper powers: duration +8%, range +5%.", "Псионика Aftershock Exoplanet: длительность +8%, дальность +5%.", {{ { "af_duration_pct", 8 }, { "af_range_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "af_smartgun_mastery", branch_id::mastery, 6, 25, currency_id::major, "af_combat_technician", "", "Smartgun Mastery", "Мастерство Smartgun", "Aftershock Exoplanet smartgun capstone: +0.75 effective Smartgun.", "Вершина Smartgun Aftershock Exoplanet: +0,75 к эффективному Smartgun.", {{ { "af_smartgun_flat", 0.75 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "af_esper_mastery", branch_id::mastery, 6, 25, currency_id::major, "af_efficient_esper", "", "Esper Mastery", "Мастерство эспера", "Aftershock Exoplanet esper capstone: +0.75 effective Metaphysics while channeling, failure chance -10%.", "Вершина эспера Aftershock Exoplanet: +0,75 эффективной Metaphysics при ченнелинге, шанс провала -10%.", {{ { "af_metaphysics_flat", 0.75 }, { "af_fail_pct", -10 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "af_noetic_artillery", branch_id::mastery, 6, 25, currency_id::major, "af_sustained_phenomena", "", "Noetic Artillery", "Ноэтическая артиллерия", "Aftershock Exoplanet projection capstone: esper potency +10%, range +8%.", "Вершина проекции Aftershock Exoplanet: мощность эспера +10%, дальность +8%.", {{ { "af_spell_power_pct", 10 }, { "af_range_pct", 8 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "af_neural_targeting", branch_id::mastery, 7, 30, currency_id::perk, "af_smartgun_mastery", "af_esper_mastery", "Neural Targeting", "Нейронное наведение", "Aftershock Exoplanet convergence: +0.25 Smartgun and +0.5 effective Metaphysics while channeling.", "Сведение путей Aftershock Exoplanet: +0,25 Smartgun и +0,5 эффективной Metaphysics при ченнелинге.", {{ { "af_smartgun_flat", 0.25 }, { "af_metaphysics_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "af_psionic_firecontrol", branch_id::mastery, 7, 30, currency_id::perk, "af_smartgun_mastery", "af_noetic_artillery", "Psionic Fire Control", "Псионическое управление огнём", "Aftershock Exoplanet convergence: +0.25 Smartgun, esper potency +6%.", "Сведение путей Aftershock Exoplanet: +0,25 Smartgun, мощность эспера +6%.", {{ { "af_smartgun_flat", 0.25 }, { "af_spell_power_pct", 6 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "af_stable_projection", branch_id::mastery, 7, 30, currency_id::perk, "af_esper_mastery", "af_noetic_artillery", "Stable Projection", "Стабильная проекция", "Aftershock Exoplanet convergence: stamina cost -5%, failure chance -5%.", "Сведение путей Aftershock Exoplanet: стоимость по выносливости -5%, провал -5%.", {{ { "af_spell_cost_pct", -5 }, { "af_fail_pct", -5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "af_posthuman_operator", branch_id::mastery, 8, 40, currency_id::major, "af_neural_targeting", "af_stable_projection", "Posthuman Operator", "Постчеловеческий оператор", "Aftershock Exoplanet apex: +0.5 Smartgun, +0.75 effective Metaphysics while channeling, stamina cost -5%, esper potency +8%.", "Вершина Aftershock Exoplanet: +0,5 Smartgun, +0,75 эффективной Metaphysics при ченнелинге, стоимость выносливости -5%, мощность эспера +8%.", {{ { "af_smartgun_flat", 0.5 }, { "af_metaphysics_flat", 0.75 }, { "af_spell_cost_pct", -5 }, { "af_spell_power_pct", 8 } }}, 4, 0, perk_kind::effect },
    { "afp_prime_operator", branch_id::mastery, 1, 2, currency_id::perk, "", "", "Prime Operator", "Оператор Prime", "Aftershock Prime: +0.25 effective Smartgun and +3% XP for Prime-sourced abilities.", "Aftershock Prime: +0,25 к эффективному Smartgun и +3% опыта способностей Prime.", {{ { "afp_smartgun_flat", 0.25 }, { "afp_spell_xp_pct", 3 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "afp_smartgun_interface", branch_id::mastery, 2, 5, currency_id::perk, "afp_prime_operator", "", "Smartgun Interface", "Интерфейс Smartgun", "Prime smart weapons: +0.25 effective Smartgun.", "Умное оружие Prime: +0,25 к эффективному Smartgun.", {{ { "afp_smartgun_flat", 0.25 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "afp_systems_theory", branch_id::mastery, 2, 5, currency_id::perk, "afp_prime_operator", "", "Systems Theory", "Теория систем", "Prime-sourced utility abilities: energy cost -4%, XP +4%.", "Утилитарные способности Prime: стоимость энергии -4%, опыт +4%.", {{ { "afp_spell_cost_pct", -4 }, { "afp_spell_xp_pct", 4 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "afp_translocation_calculus", branch_id::mastery, 2, 5, currency_id::perk, "afp_prime_operator", "", "Translocation Calculus", "Расчёт трансляции", "Prime-sourced spatial abilities: range +5%, duration +4%.", "Пространственные способности Prime: дальность +5%, длительность +4%.", {{ { "afp_range_pct", 5 }, { "afp_duration_pct", 4 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "afp_predictive_targeting", branch_id::mastery, 3, 9, currency_id::perk, "afp_smartgun_interface", "", "Predictive Targeting", "Предиктивное наведение", "Prime smart weapons: +0.25 effective Smartgun.", "Умное оружие Prime: +0,25 к эффективному Smartgun.", {{ { "afp_smartgun_flat", 0.25 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "afp_power_budget", branch_id::mastery, 3, 9, currency_id::perk, "afp_systems_theory", "", "Power Budget", "Энергобюджет", "Prime-sourced abilities: energy cost -4%, activation time -3%.", "Способности Prime: стоимость энергии -4%, время активации -3%.", {{ { "afp_spell_cost_pct", -4 }, { "afp_cast_time_pct", -3 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "afp_spatial_solution", branch_id::mastery, 3, 9, currency_id::perk, "afp_translocation_calculus", "", "Spatial Solution", "Пространственное решение", "Prime-sourced spatial abilities: range +5%, area +5%.", "Пространственные способности Prime: дальность +5%, площадь +5%.", {{ { "afp_range_pct", 5 }, { "afp_aoe_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "afp_sensor_fusion", branch_id::mastery, 4, 14, currency_id::perk, "afp_predictive_targeting", "", "Sensor Fusion", "Слияние сенсоров", "Prime smart weapons: +0.25 effective Smartgun.", "Умное оружие Prime: +0,25 к эффективному Smartgun.", {{ { "afp_smartgun_flat", 0.25 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "afp_utility_protocols", branch_id::mastery, 4, 14, currency_id::perk, "afp_power_budget", "", "Utility Protocols", "Утилитарные протоколы", "Prime-sourced abilities: XP +6%, failure chance -4%.", "Способности Prime: опыт +6%, шанс провала -4%.", {{ { "afp_spell_xp_pct", 6 }, { "afp_fail_pct", -4 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "afp_stable_translation", branch_id::mastery, 4, 14, currency_id::perk, "afp_spatial_solution", "", "Stable Translation", "Стабильная трансляция", "Prime-sourced spatial abilities: duration +6%, failure chance -4%.", "Пространственные способности Prime: длительность +6%, шанс провала -4%.", {{ { "afp_duration_pct", 6 }, { "afp_fail_pct", -4 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "afp_combat_technician", branch_id::mastery, 5, 20, currency_id::perk, "afp_sensor_fusion", "", "Prime Combat Technician", "Боевой техник Prime", "Prime smart weapons: +0.5 effective Smartgun.", "Умное оружие Prime: +0,5 к эффективному Smartgun.", {{ { "afp_smartgun_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "afp_systems_automation", branch_id::mastery, 5, 20, currency_id::perk, "afp_utility_protocols", "", "Systems Automation", "Автоматизация систем", "Prime-sourced abilities: activation time -5%, XP +7%.", "Способности Prime: время активации -5%, опыт +7%.", {{ { "afp_cast_time_pct", -5 }, { "afp_spell_xp_pct", 7 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "afp_field_projection", branch_id::mastery, 5, 20, currency_id::perk, "afp_stable_translation", "", "Field Projection", "Полевая проекция", "Prime-sourced abilities: potency +6%, range +5%.", "Способности Prime: мощность +6%, дальность +5%.", {{ { "afp_spell_power_pct", 6 }, { "afp_range_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "afp_smartgun_mastery", branch_id::mastery, 6, 25, currency_id::major, "afp_combat_technician", "", "Prime Smartgun Mastery", "Мастерство Smartgun Prime", "Prime smartgun capstone: +0.75 effective Smartgun.", "Вершина Smartgun Prime: +0,75 к эффективному Smartgun.", {{ { "afp_smartgun_flat", 0.75 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "afp_prime_systems_mastery", branch_id::mastery, 6, 25, currency_id::major, "afp_systems_automation", "", "Prime Systems Mastery", "Мастерство систем Prime", "Prime systems capstone: energy cost -7%, activation time -6%, XP +8%.", "Вершина систем Prime: стоимость энергии -7%, время активации -6%, опыт +8%.", {{ { "afp_spell_cost_pct", -7 }, { "afp_cast_time_pct", -6 }, { "afp_spell_xp_pct", 8 }, { nullptr, 0 } }}, 3, 0, perk_kind::effect },
    { "afp_translocation_mastery", branch_id::mastery, 6, 25, currency_id::major, "afp_field_projection", "", "Translocation Mastery", "Мастерство трансляции", "Prime spatial capstone: potency +8%, range +8%, duration +8%.", "Вершина трансляции Prime: мощность +8%, дальность +8%, длительность +8%.", {{ { "afp_spell_power_pct", 8 }, { "afp_range_pct", 8 }, { "afp_duration_pct", 8 }, { nullptr, 0 } }}, 3, 0, perk_kind::effect },
    { "afp_integrated_firecontrol", branch_id::mastery, 7, 30, currency_id::perk, "afp_smartgun_mastery", "afp_prime_systems_mastery", "Integrated Fire Control", "Интегрированное управление огнём", "Prime convergence: +0.25 Smartgun, activation time -4%.", "Сведение Prime: +0,25 Smartgun, время активации -4%.", {{ { "afp_smartgun_flat", 0.25 }, { "afp_cast_time_pct", -4 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "afp_remote_geometry", branch_id::mastery, 7, 30, currency_id::perk, "afp_prime_systems_mastery", "afp_translocation_mastery", "Remote Geometry", "Удалённая геометрия", "Prime convergence: area +5%, duration +5%.", "Сведение Prime: площадь +5%, длительность +5%.", {{ { "afp_aoe_pct", 5 }, { "afp_duration_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "afp_mobile_platform", branch_id::mastery, 7, 30, currency_id::perk, "afp_smartgun_mastery", "afp_translocation_mastery", "Mobile Platform", "Мобильная платформа", "Prime convergence: +0.25 Smartgun, range +5%.", "Сведение Prime: +0,25 Smartgun, дальность +5%.", {{ { "afp_smartgun_flat", 0.25 }, { "afp_range_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "afp_prime_integrator", branch_id::mastery, 8, 40, currency_id::major, "afp_integrated_firecontrol", "afp_remote_geometry", "Prime Integrator", "Интегратор Prime", "Prime apex: +0.5 Smartgun, energy cost -5%, potency +6%, duration +6%.", "Вершина Prime: +0,5 Smartgun, стоимость энергии -5%, мощность +6%, длительность +6%.", {{ { "afp_smartgun_flat", 0.5 }, { "afp_spell_cost_pct", -5 }, { "afp_spell_power_pct", 6 }, { "afp_duration_pct", 6 } }}, 4, 0, perk_kind::effect },

    { "sec_field_researcher", branch_id::mastery, 1, 2, currency_id::perk, "", "", "Secronom Field Researcher", "Полевой исследователь Secronom", "Against Secronom creatures: damage +2%, incoming damage -2%.", "Против существ Secronom: урон +2%, входящий урон -2%.", {{ { "sec_damage_pct", 2 }, { "sec_resist_pct", 2 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "sec_hunter_drills", branch_id::mastery, 2, 5, currency_id::perk, "sec_field_researcher", "", "Hunter Drills", "Тренировки охотника", "Against Secronom creatures: damage +3%.", "Против существ Secronom: урон +3%.", {{ { "sec_damage_pct", 3 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "sec_pathogen_hardening", branch_id::mastery, 2, 5, currency_id::perk, "sec_field_researcher", "", "Pathogen Hardening", "Закалка против патогенов", "Against Secronom creatures: incoming damage -3%.", "Против существ Secronom: входящий урон -3%.", {{ { "sec_resist_pct", 3 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "sec_crimson_anatomy", branch_id::mastery, 2, 5, currency_id::perk, "sec_field_researcher", "", "Crimson Anatomy", "Анатомия Crimson", "Against Crimson Horror species: extra damage +3%.", "Против видов Crimson Horror: дополнительный урон +3%.", {{ { "sec_crimson_damage_pct", 3 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "sec_vital_targets", branch_id::mastery, 3, 9, currency_id::perk, "sec_hunter_drills", "", "Vital Targets", "Уязвимые точки", "Against Secronom creatures: damage +4%.", "Против существ Secronom: урон +4%.", {{ { "sec_damage_pct", 4 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "sec_toxicology", branch_id::mastery, 3, 9, currency_id::perk, "sec_pathogen_hardening", "", "Toxicology", "Токсикология", "Against Secronom creatures: incoming damage -4%.", "Против существ Secronom: входящий урон -4%.", {{ { "sec_resist_pct", 4 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "sec_flesh_patterning", branch_id::mastery, 3, 9, currency_id::perk, "sec_crimson_anatomy", "", "Flesh Patterning", "Структура плоти", "Against Crimson Horror species: extra damage +4%.", "Против видов Crimson Horror: дополнительный урон +4%.", {{ { "sec_crimson_damage_pct", 4 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "sec_elite_tracking", branch_id::mastery, 4, 14, currency_id::perk, "sec_vital_targets", "", "Elite Tracking", "Выслеживание элиты", "Against elite/catastrophic Secronom species: extra damage +4%.", "Против элитных/катастрофических видов Secronom: дополнительный урон +4%.", {{ { "sec_elite_damage_pct", 4 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "sec_adaptive_response", branch_id::mastery, 4, 14, currency_id::perk, "sec_toxicology", "", "Adaptive Response", "Адаптивная реакция", "Against elite/catastrophic Secronom species: incoming damage -4% extra.", "Против элитных/катастрофических видов Secronom: дополнительное снижение урона -4%.", {{ { "sec_elite_resist_pct", 4 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "sec_crimson_countermeasures", branch_id::mastery, 4, 14, currency_id::perk, "sec_flesh_patterning", "", "Crimson Countermeasures", "Контрмеры Crimson", "Against Crimson Horror species: incoming damage -4% extra.", "Против видов Crimson Horror: дополнительное снижение урона -4%.", {{ { "sec_crimson_resist_pct", 4 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "sec_execution_protocol", branch_id::mastery, 5, 20, currency_id::perk, "sec_elite_tracking", "", "Execution Protocol", "Протокол уничтожения", "Against elite/catastrophic Secronom species: extra damage +5%.", "Против элитных/катастрофических видов Secronom: дополнительный урон +5%.", {{ { "sec_elite_damage_pct", 5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "sec_hardened_survivor", branch_id::mastery, 5, 20, currency_id::perk, "sec_adaptive_response", "", "Hardened Survivor", "Закалённый выживший", "Against elite/catastrophic Secronom species: incoming damage -5% extra.", "Против элитных/катастрофических видов Secronom: дополнительное снижение урона -5%.", {{ { "sec_elite_resist_pct", 5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "sec_fleshbreaker", branch_id::mastery, 5, 20, currency_id::perk, "sec_crimson_countermeasures", "", "Fleshbreaker", "Разрушитель плоти", "Against Crimson Horror species: extra damage +5%, incoming damage -3% extra.", "Против видов Crimson Horror: дополнительный урон +5%, дополнительное снижение урона -3%.", {{ { "sec_crimson_damage_pct", 5 }, { "sec_crimson_resist_pct", 3 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "sec_hunter_mastery", branch_id::mastery, 6, 25, currency_id::major, "sec_execution_protocol", "", "Secronom Hunter Mastery", "Мастерство охотника Secronom", "Hunter capstone: damage +6% to all Secronom and +4% extra to elites.", "Вершина охотника: урон +6% по всем Secronom и ещё +4% по элите.", {{ { "sec_damage_pct", 6 }, { "sec_elite_damage_pct", 4 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "sec_survival_mastery", branch_id::mastery, 6, 25, currency_id::major, "sec_hardened_survivor", "", "Secronom Survival Mastery", "Мастерство выживания Secronom", "Survival capstone: incoming damage -6% from all Secronom and -4% extra from elites.", "Вершина выживания: входящий урон -6% от всех Secronom и ещё -4% от элиты.", {{ { "sec_resist_pct", 6 }, { "sec_elite_resist_pct", 4 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "sec_crimson_mastery", branch_id::mastery, 6, 25, currency_id::major, "sec_fleshbreaker", "", "Crimson Horror Mastery", "Мастерство Crimson Horror", "Crimson capstone: extra damage +7%, incoming damage -5% extra.", "Вершина Crimson: дополнительный урон +7%, дополнительное снижение урона -5%.", {{ { "sec_crimson_damage_pct", 7 }, { "sec_crimson_resist_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "sec_apex_hunter", branch_id::mastery, 7, 30, currency_id::perk, "sec_hunter_mastery", "sec_survival_mastery", "Apex Hunter", "Вершинный охотник", "Secronom convergence: damage +4%, incoming damage -4%.", "Сведение Secronom: урон +4%, входящий урон -4%.", {{ { "sec_damage_pct", 4 }, { "sec_resist_pct", 4 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "sec_ultimate_protocol", branch_id::mastery, 7, 30, currency_id::perk, "sec_survival_mastery", "sec_crimson_mastery", "Ultimate Protocol", "Протокол Ultimate", "Secronom convergence: elite resistance +5%, Crimson damage +4%.", "Сведение Secronom: защита от элиты +5%, урон по Crimson +4%.", {{ { "sec_elite_resist_pct", 5 }, { "sec_crimson_damage_pct", 4 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "sec_red_harvest", branch_id::mastery, 7, 30, currency_id::perk, "sec_hunter_mastery", "sec_crimson_mastery", "Red Harvest", "Красная жатва", "Secronom convergence: elite damage +5%, Crimson damage +5%.", "Сведение Secronom: урон по элите +5%, урон по Crimson +5%.", {{ { "sec_elite_damage_pct", 5 }, { "sec_crimson_damage_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "sec_nightmare_specialist", branch_id::mastery, 8, 40, currency_id::major, "sec_apex_hunter", "sec_red_harvest", "Nightmare Specialist", "Специалист по кошмарам", "Secronom apex: damage +5%, resistance +5%, elite damage +5%, Crimson damage +5%.", "Вершина Secronom: урон +5%, защита +5%, урон по элите +5%, урон по Crimson +5%.", {{ { "sec_damage_pct", 5 }, { "sec_resist_pct", 5 }, { "sec_elite_damage_pct", 5 }, { "sec_crimson_damage_pct", 5 } }}, 4, 0, perk_kind::effect },

    { "secx_flesh_initiate", branch_id::mastery, 1, 2, currency_id::perk, "", "", "Flesh Initiate", "Посвящённый плоти", "Secronom+: +0.25 effective Flesh Weaving and +0.25 Bio-organic Weapons.", "Secronom+: +0,25 к Flesh Weaving и +0,25 к Bio-organic Weapons.", {{ { "secx_flesh_craft_flat", 0.25 }, { "secx_flesh_combat_flat", 0.25 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "secx_flesh_weaving", branch_id::mastery, 2, 5, currency_id::perk, "secx_flesh_initiate", "", "Flesh Weaving Practice", "Практика Flesh Weaving", "Secronom+: +0.5 effective Flesh Weaving.", "Secronom+: +0,5 к эффективному Flesh Weaving.", {{ { "secx_flesh_craft_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "secx_biomorph_training", branch_id::mastery, 2, 5, currency_id::perk, "secx_flesh_initiate", "", "Biomorph Training", "Тренировка Biomorph", "Secronom+: +0.5 effective Bio-organic Weapons.", "Secronom+: +0,5 к эффективному Bio-organic Weapons.", {{ { "secx_flesh_combat_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "secx_neural_link", branch_id::mastery, 2, 5, currency_id::perk, "secx_flesh_initiate", "", "Flesh Vessel Neural Link", "Нейросвязь Flesh Vessel", "Secronom+-sourced abilities: energy cost -4%, XP +4%.", "Способности Secronom+: стоимость энергии -4%, опыт +4%.", {{ { "secx_spell_cost_pct", -4 }, { "secx_spell_xp_pct", 4 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "secx_resource_shaping", branch_id::mastery, 3, 9, currency_id::perk, "secx_flesh_weaving", "", "Resource Shaping", "Формирование ресурсов", "Secronom+: +0.5 effective Flesh Weaving.", "Secronom+: +0,5 к эффективному Flesh Weaving.", {{ { "secx_flesh_craft_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "secx_armament_drills", branch_id::mastery, 3, 9, currency_id::perk, "secx_biomorph_training", "", "Armament Drills", "Тренировки вооружения", "Secronom+: +0.5 effective Bio-organic Weapons.", "Secronom+: +0,5 к эффективному Bio-organic Weapons.", {{ { "secx_flesh_combat_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "secx_morph_control", branch_id::mastery, 3, 9, currency_id::perk, "secx_neural_link", "", "Morph Control", "Контроль морфинга", "Secronom+-sourced abilities: activation time -4%, failure chance -4%.", "Способности Secronom+: время активации -4%, шанс провала -4%.", {{ { "secx_cast_time_pct", -4 }, { "secx_fail_pct", -4 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "secx_advanced_weaving", branch_id::mastery, 4, 14, currency_id::perk, "secx_resource_shaping", "", "Advanced Flesh Weaving", "Продвинутое Flesh Weaving", "Secronom+: +0.5 effective Flesh Weaving.", "Secronom+: +0,5 к эффективному Flesh Weaving.", {{ { "secx_flesh_craft_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "secx_combat_instinct", branch_id::mastery, 4, 14, currency_id::perk, "secx_armament_drills", "", "Bio-organic Combat Instinct", "Биоорганический боевой инстинкт", "Secronom+: +0.5 effective Bio-organic Weapons.", "Secronom+: +0,5 к эффективному Bio-organic Weapons.", {{ { "secx_flesh_combat_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "secx_flesh_channel", branch_id::mastery, 4, 14, currency_id::perk, "secx_morph_control", "", "Flesh Channel", "Канал плоти", "Secronom+-sourced abilities: duration +5%, potency +5%.", "Способности Secronom+: длительность +5%, мощность +5%.", {{ { "secx_duration_pct", 5 }, { "secx_spell_power_pct", 5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "secx_material_mastery", branch_id::mastery, 5, 20, currency_id::perk, "secx_advanced_weaving", "", "Living Material Mastery", "Мастерство живого материала", "Secronom+: +0.75 effective Flesh Weaving.", "Secronom+: +0,75 к эффективному Flesh Weaving.", {{ { "secx_flesh_craft_flat", 0.75 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "secx_bioorganic_mastery", branch_id::mastery, 5, 20, currency_id::perk, "secx_combat_instinct", "", "Bio-organic Armament Mastery", "Мастерство биооружия", "Secronom+: +0.75 effective Bio-organic Weapons.", "Secronom+: +0,75 к эффективному Bio-organic Weapons.", {{ { "secx_flesh_combat_flat", 0.75 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "secx_vessel_resonance", branch_id::mastery, 5, 20, currency_id::perk, "secx_flesh_channel", "", "Flesh Vessel Resonance", "Резонанс Flesh Vessel", "Secronom+-sourced abilities: energy cost -5%, duration +6%.", "Способности Secronom+: стоимость энергии -5%, длительность +6%.", {{ { "secx_spell_cost_pct", -5 }, { "secx_duration_pct", 6 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "secx_fleshcraft_mastery", branch_id::mastery, 6, 25, currency_id::major, "secx_material_mastery", "", "Fleshcraft Mastery", "Мастерство Fleshcraft", "Flesh Weaving capstone: +1.0 effective Flesh Weaving.", "Вершина Flesh Weaving: +1,0 к эффективному Flesh Weaving.", {{ { "secx_flesh_craft_flat", 1.0 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "secx_biomorph_mastery", branch_id::mastery, 6, 25, currency_id::major, "secx_bioorganic_mastery", "", "Biomorph Mastery", "Мастерство Biomorph", "Bio-organic Weapons capstone: +1.0 effective Bio-organic Weapons.", "Вершина Bio-organic Weapons: +1,0 к эффективному Bio-organic Weapons.", {{ { "secx_flesh_combat_flat", 1.0 }, { nullptr, 0 }, { nullptr, 0 }, { nullptr, 0 } }}, 1, 0, perk_kind::effect },
    { "secx_flesh_vessel_mastery", branch_id::mastery, 6, 25, currency_id::major, "secx_vessel_resonance", "", "Flesh Vessel Mastery", "Мастерство Flesh Vessel", "Flesh Vessel capstone: potency +8%, energy cost -6%, duration +8%.", "Вершина Flesh Vessel: мощность +8%, стоимость энергии -6%, длительность +8%.", {{ { "secx_spell_power_pct", 8 }, { "secx_spell_cost_pct", -6 }, { "secx_duration_pct", 8 }, { nullptr, 0 } }}, 3, 0, perk_kind::effect },
    { "secx_living_arsenal", branch_id::mastery, 7, 30, currency_id::perk, "secx_fleshcraft_mastery", "secx_biomorph_mastery", "Living Arsenal", "Живой арсенал", "Secronom+ convergence: +0.5 Flesh Weaving and +0.5 Bio-organic Weapons.", "Сведение Secronom+: +0,5 Flesh Weaving и +0,5 Bio-organic Weapons.", {{ { "secx_flesh_craft_flat", 0.5 }, { "secx_flesh_combat_flat", 0.5 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "secx_adaptive_morph", branch_id::mastery, 7, 30, currency_id::perk, "secx_biomorph_mastery", "secx_flesh_vessel_mastery", "Adaptive Morph", "Адаптивный морф", "Secronom+ convergence: +0.5 Bio-organic Weapons, activation time -4%.", "Сведение Secronom+: +0,5 Bio-organic Weapons, время активации -4%.", {{ { "secx_flesh_combat_flat", 0.5 }, { "secx_cast_time_pct", -4 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "secx_artificial_ecology", branch_id::mastery, 7, 30, currency_id::perk, "secx_fleshcraft_mastery", "secx_flesh_vessel_mastery", "Artificial Ecology", "Искусственная экология", "Secronom+ convergence: +0.5 Flesh Weaving, ability XP +6%.", "Сведение Secronom+: +0,5 Flesh Weaving, опыт способностей +6%.", {{ { "secx_flesh_craft_flat", 0.5 }, { "secx_spell_xp_pct", 6 }, { nullptr, 0 }, { nullptr, 0 } }}, 2, 0, perk_kind::effect },
    { "secx_flesh_architect", branch_id::mastery, 8, 40, currency_id::major, "secx_living_arsenal", "secx_adaptive_morph", "Flesh Architect", "Архитектор плоти", "Secronom+ apex: +0.75 Flesh Weaving, +0.75 Bio-organic Weapons, potency +6%, energy cost -5%.", "Вершина Secronom+: +0,75 Flesh Weaving, +0,75 Bio-organic Weapons, мощность +6%, стоимость энергии -5%.", {{ { "secx_flesh_craft_flat", 0.75 }, { "secx_flesh_combat_flat", 0.75 }, { "secx_spell_power_pct", 6 }, { "secx_spell_cost_pct", -5 } }}, 4, 0, perk_kind::effect }
};

bool russian()
{
    const char *raw = host && host->get_locale ? host->get_locale() : "en";
    const std::string locale = raw ? raw : "en";
    return locale == "ru" || locale.rfind( "ru_", 0 ) == 0;
}

std::string tr( const char *en, const char *ru )
{
    return russian() ? ru : en;
}

bool active_world_mod( const char *mod_id )
{
    return host != nullptr && host->world_mod_active != nullptr &&
           host->world_mod_active( mod_id ) != 0;
}
int64_t get_state( const std::string &key, int64_t fallback )
{
    if( !host || !host->character_state_get_i64 ) {
        return fallback;
    }
    return host->character_state_get_i64( module_id, key.c_str(), fallback );
}

void set_state( const std::string &key, int64_t value )
{
    if( host && host->character_state_set_i64 ) {
        host->character_state_set_i64( module_id, key.c_str(), value );
    }
}

void message( const std::string &text )
{
    if( host && host->ui_message ) {
        host->ui_message( text.c_str() );
    }
}

bool character_available()
{
    return host && host->character_state_available && host->character_state_available();
}

const std::string &perk_key( const perk_def &perk )
{
    static const std::map<std::string_view, std::string> keys = []() {
        std::map<std::string_view, std::string> result;
        for( const perk_def &entry : perks ) {
            result.emplace( std::string_view( entry.id ), std::string( "p_" ) + entry.id );
        }
        return result;
    }();
    const auto it = keys.find( std::string_view( perk.id ) );
    if( it != keys.end() ) {
        return it->second;
    }
    static const std::string invalid_key = "p_invalid";
    return invalid_key;
}

struct ranked_perk_rule {
    const char *id;
    int max_rank;
    double extra_scale;
};

const ranked_perk_rule *ranked_perk_rule_for( const perk_def &perk )
{
    static const ranked_perk_rule rules[] = {
        { "c_conditioning", 5, 0.125 }, { "s_field", 3, 0.50 },
        { "m_light", 5, 1.0 / 6.0 }, { "f_hands", 5, 0.40 },
        { "g_route", 3, 1.0 / 3.0 }, { "a_adapt", 5, 0.20 },

        { "mg_arcane_focus", 5, 0.125 }, { "mg_spellcraft_drills", 5, 0.125 },
        { "mg_mana_sensitivity", 3, 0.25 }, { "mg_mana_regeneration", 3, 0.25 },
        { "mom_mental_focus", 5, 0.125 }, { "mom_metaphysical_method", 5, 0.125 },
        { "mom_neural_reserve", 3, 0.25 }, { "mom_channel_discipline", 3, 0.25 },
        { "xe_anomaly_method", 5, 0.125 }, { "xe_gramarye_studies", 5, 0.125 },
        { "xe_field_agent", 3, 0.25 }, { "xe_dimensional_model", 3, 0.25 },
        { "af_systems_operator", 5, 0.125 }, { "af_targeting_link", 5, 0.125 },
        { "af_metaphysical_training", 5, 0.125 }, { "af_conditioning", 3, 0.25 },

        { "afp_prime_operator", 5, 0.125 }, { "afp_smartgun_interface", 5, 0.125 },
        { "afp_systems_theory", 3, 0.25 }, { "afp_translocation_calculus", 3, 0.25 },
        { "sec_field_researcher", 5, 0.125 }, { "sec_hunter_drills", 5, 0.125 },
        { "sec_pathogen_hardening", 3, 0.25 }, { "sec_crimson_anatomy", 3, 0.25 },
        { "secx_flesh_initiate", 5, 0.125 }, { "secx_flesh_weaving", 5, 0.125 },
        { "secx_biomorph_training", 5, 0.125 }, { "secx_neural_link", 3, 0.25 }
    };
    const std::string id = perk.id ? perk.id : "";
    for( const ranked_perk_rule &rule : rules ) {
        if( id == rule.id ) return &rule;
    }
    return nullptr;
}

bool ranked_perk_id( const perk_def &perk )
{
    return ranked_perk_rule_for( perk ) != nullptr;
}

int perk_max_rank( const perk_def &perk )
{
    const ranked_perk_rule *rule = ranked_perk_rule_for( perk );
    return rule ? rule->max_rank : 1;
}

double perk_extra_rank_scale( const perk_def &perk )
{
    const ranked_perk_rule *rule = ranked_perk_rule_for( perk );
    return rule ? rule->extra_scale : 0.0;
}

int perk_rank( const perk_def &perk )
{
    return static_cast<int>( std::max<int64_t>(
        0, std::min<int64_t>( perk_max_rank( perk ), get_state( perk_key( perk ), 0 ) ) ) );
}

bool perk_maxed( const perk_def &perk )
{
    return perk_rank( perk ) >= perk_max_rank( perk );
}

double perk_rank_multiplier_for( const perk_def &perk, int rank )
{
    if( rank <= 0 ) {
        return 0.0;
    }
    rank = std::min( rank, perk_max_rank( perk ) );
    return 1.0 + static_cast<double>( rank - 1 ) * perk_extra_rank_scale( perk );
}

double perk_rank_multiplier( const perk_def &perk )
{
    return perk_rank_multiplier_for( perk, perk_rank( perk ) );
}

std::string rank_roman( int rank )
{
    switch( rank ) {
        case 1: return "I";
        case 2: return "II";
        case 3: return "III";
        case 4: return "IV";
        case 5: return "V";
        default: return std::to_string( rank );
    }
}

std::string rank_chevrons( const perk_def &perk )
{
    const int max_rank = perk_max_rank( perk );
    if( max_rank <= 1 ) return {};
    const int rank = perk_rank( perk );
    std::string result;
    for( int i = 0; i < max_rank; ++i ) {
        result += i < rank ? "▲" : "△";
    }
    return result;
}

std::string perk_display_name( const perk_def &perk )
{
    std::string result = russian() ? perk.name_ru : perk.name_en;
    const int rank = perk_rank( perk );
    if( perk_max_rank( perk ) > 1 && rank > 0 ) {
        result += " " + rank_roman( rank );
    }
    return result;
}

enum class integration_id {
    none,
    magiclysm,
    mindovermatter,
    xedra_evolved,
    aftershock_exoplanet,
    aftershock_prime,
    secronom,
    secronom_plus
};

integration_id perk_integration( const perk_def &perk )
{
    static const std::map<std::string_view, integration_id> registry = {
        { "mg_arcane_focus", integration_id::magiclysm },
        { "mg_mana_sensitivity", integration_id::magiclysm },
        { "mg_battlemage", integration_id::magiclysm },
        { "mg_wayfarer", integration_id::magiclysm },
        { "mg_mana_regeneration", integration_id::magiclysm },
        { "mg_stable_formula", integration_id::magiclysm },
        { "mg_shaped_evocation", integration_id::magiclysm },
        { "mg_efficient_channels", integration_id::magiclysm },
        { "mg_spellcraft_drills", integration_id::magiclysm },
        { "mg_sustained_weave", integration_id::magiclysm },
        { "mg_deep_reservoir", integration_id::magiclysm },
        { "mg_quick_invocation", integration_id::magiclysm },
        { "mg_arcane_geometry", integration_id::magiclysm },
        { "mg_mana_mastery", integration_id::magiclysm },
        { "mg_ritual_craft", integration_id::magiclysm },
        { "mg_high_thaumaturgy", integration_id::magiclysm },
        { "mg_efficient_theory", integration_id::magiclysm },
        { "mg_combat_weave", integration_id::magiclysm },
        { "mg_resonant_reserve", integration_id::magiclysm },
        { "mg_archmage", integration_id::magiclysm },
        { "mom_mental_focus", integration_id::mindovermatter },
        { "mom_still_mind", integration_id::mindovermatter },
        { "mom_neural_reserve", integration_id::mindovermatter },
        { "mom_kinetic_control", integration_id::mindovermatter },
        { "mom_channel_discipline", integration_id::mindovermatter },
        { "mom_efficient_channel", integration_id::mindovermatter },
        { "mom_psionic_pressure", integration_id::mindovermatter },
        { "mom_metaphysical_method", integration_id::mindovermatter },
        { "mom_controlled_exposure", integration_id::mindovermatter },
        { "mom_extended_pattern", integration_id::mindovermatter },
        { "mom_mental_lattice", integration_id::mindovermatter },
        { "mom_recovery_cycle", integration_id::mindovermatter },
        { "mom_field_shaping", integration_id::mindovermatter },
        { "mom_combat_focus", integration_id::mindovermatter },
        { "mom_nether_discipline", integration_id::mindovermatter },
        { "mom_noetic_projection", integration_id::mindovermatter },
        { "mom_stable_channel", integration_id::mindovermatter },
        { "mom_precise_manifestation", integration_id::mindovermatter },
        { "mom_efficient_force", integration_id::mindovermatter },
        { "mom_transcendent_focus", integration_id::mindovermatter },
        { "xe_anomaly_method", integration_id::xedra_evolved },
        { "xe_field_agent", integration_id::xedra_evolved },
        { "xe_dross_resonance", integration_id::xedra_evolved },
        { "xe_dimensional_hunter", integration_id::xedra_evolved },
        { "xe_gramarye_studies", integration_id::xedra_evolved },
        { "xe_dream_metabolism", integration_id::xedra_evolved },
        { "xe_fast_manifestation", integration_id::xedra_evolved },
        { "xe_dimensional_model", integration_id::xedra_evolved },
        { "xe_efficient_oneiromancy", integration_id::xedra_evolved },
        { "xe_oneiric_force", integration_id::xedra_evolved },
        { "xe_pattern_archive", integration_id::xedra_evolved },
        { "xe_dream_reservoir", integration_id::xedra_evolved },
        { "xe_liminal_persistence", integration_id::xedra_evolved },
        { "xe_occult_engineer", integration_id::xedra_evolved },
        { "xe_dream_economy", integration_id::xedra_evolved },
        { "xe_reality_shaper", integration_id::xedra_evolved },
        { "xe_dream_theorist", integration_id::xedra_evolved },
        { "xe_liminal_engineer", integration_id::xedra_evolved },
        { "xe_oneiric_architect", integration_id::xedra_evolved },
        { "xe_boundary_master", integration_id::xedra_evolved },
        { "af_systems_operator", integration_id::aftershock_exoplanet },
        { "af_targeting_link", integration_id::aftershock_exoplanet },
        { "af_conditioning", integration_id::aftershock_exoplanet },
        { "af_expedition_logistics", integration_id::aftershock_exoplanet },
        { "af_predictive_fire", integration_id::aftershock_exoplanet },
        { "af_metaphysical_training", integration_id::aftershock_exoplanet },
        { "af_telekinetic_geometry", integration_id::aftershock_exoplanet },
        { "af_sensor_fusion", integration_id::aftershock_exoplanet },
        { "af_stable_esper", integration_id::aftershock_exoplanet },
        { "af_esper_force", integration_id::aftershock_exoplanet },
        { "af_combat_technician", integration_id::aftershock_exoplanet },
        { "af_efficient_esper", integration_id::aftershock_exoplanet },
        { "af_sustained_phenomena", integration_id::aftershock_exoplanet },
        { "af_smartgun_mastery", integration_id::aftershock_exoplanet },
        { "af_esper_mastery", integration_id::aftershock_exoplanet },
        { "af_noetic_artillery", integration_id::aftershock_exoplanet },
        { "af_neural_targeting", integration_id::aftershock_exoplanet },
        { "af_psionic_firecontrol", integration_id::aftershock_exoplanet },
        { "af_stable_projection", integration_id::aftershock_exoplanet },
        { "af_posthuman_operator", integration_id::aftershock_exoplanet },
        { "afp_prime_operator", integration_id::aftershock_prime },
        { "afp_smartgun_interface", integration_id::aftershock_prime },
        { "afp_systems_theory", integration_id::aftershock_prime },
        { "afp_translocation_calculus", integration_id::aftershock_prime },
        { "afp_predictive_targeting", integration_id::aftershock_prime },
        { "afp_power_budget", integration_id::aftershock_prime },
        { "afp_spatial_solution", integration_id::aftershock_prime },
        { "afp_sensor_fusion", integration_id::aftershock_prime },
        { "afp_utility_protocols", integration_id::aftershock_prime },
        { "afp_stable_translation", integration_id::aftershock_prime },
        { "afp_combat_technician", integration_id::aftershock_prime },
        { "afp_systems_automation", integration_id::aftershock_prime },
        { "afp_field_projection", integration_id::aftershock_prime },
        { "afp_smartgun_mastery", integration_id::aftershock_prime },
        { "afp_prime_systems_mastery", integration_id::aftershock_prime },
        { "afp_translocation_mastery", integration_id::aftershock_prime },
        { "afp_integrated_firecontrol", integration_id::aftershock_prime },
        { "afp_remote_geometry", integration_id::aftershock_prime },
        { "afp_mobile_platform", integration_id::aftershock_prime },
        { "afp_prime_integrator", integration_id::aftershock_prime },
        { "sec_field_researcher", integration_id::secronom },
        { "sec_hunter_drills", integration_id::secronom },
        { "sec_pathogen_hardening", integration_id::secronom },
        { "sec_crimson_anatomy", integration_id::secronom },
        { "sec_vital_targets", integration_id::secronom },
        { "sec_toxicology", integration_id::secronom },
        { "sec_flesh_patterning", integration_id::secronom },
        { "sec_elite_tracking", integration_id::secronom },
        { "sec_adaptive_response", integration_id::secronom },
        { "sec_crimson_countermeasures", integration_id::secronom },
        { "sec_execution_protocol", integration_id::secronom },
        { "sec_hardened_survivor", integration_id::secronom },
        { "sec_fleshbreaker", integration_id::secronom },
        { "sec_hunter_mastery", integration_id::secronom },
        { "sec_survival_mastery", integration_id::secronom },
        { "sec_crimson_mastery", integration_id::secronom },
        { "sec_apex_hunter", integration_id::secronom },
        { "sec_ultimate_protocol", integration_id::secronom },
        { "sec_red_harvest", integration_id::secronom },
        { "sec_nightmare_specialist", integration_id::secronom },
        { "secx_flesh_initiate", integration_id::secronom_plus },
        { "secx_flesh_weaving", integration_id::secronom_plus },
        { "secx_biomorph_training", integration_id::secronom_plus },
        { "secx_neural_link", integration_id::secronom_plus },
        { "secx_resource_shaping", integration_id::secronom_plus },
        { "secx_armament_drills", integration_id::secronom_plus },
        { "secx_morph_control", integration_id::secronom_plus },
        { "secx_advanced_weaving", integration_id::secronom_plus },
        { "secx_combat_instinct", integration_id::secronom_plus },
        { "secx_flesh_channel", integration_id::secronom_plus },
        { "secx_material_mastery", integration_id::secronom_plus },
        { "secx_bioorganic_mastery", integration_id::secronom_plus },
        { "secx_vessel_resonance", integration_id::secronom_plus },
        { "secx_fleshcraft_mastery", integration_id::secronom_plus },
        { "secx_biomorph_mastery", integration_id::secronom_plus },
        { "secx_flesh_vessel_mastery", integration_id::secronom_plus },
        { "secx_living_arsenal", integration_id::secronom_plus },
        { "secx_adaptive_morph", integration_id::secronom_plus },
        { "secx_artificial_ecology", integration_id::secronom_plus },
        { "secx_flesh_architect", integration_id::secronom_plus },
    };
    const auto it = registry.find( perk.id ? std::string_view( perk.id ) : std::string_view() );
    return it == registry.end() ? integration_id::none : it->second;
}

bool integration_perk( const perk_def &perk )
{
    return perk_integration( perk ) != integration_id::none;
}

const char *integration_mod_id( integration_id integration )
{
    switch( integration ) {
        case integration_id::magiclysm: return "magiclysm";
        case integration_id::mindovermatter: return "mindovermatter";
        case integration_id::xedra_evolved: return "xedra_evolved";
        case integration_id::aftershock_exoplanet: return "aftershock_exoplanet";
        case integration_id::aftershock_prime: return "aftershock_prime";
        case integration_id::secronom: return "secronom";
        case integration_id::secronom_plus: return "secronom_lore_expansion";
        case integration_id::none: break;
    }
    return "";
}

const char *integration_mod_id( const perk_def &perk )
{
    return integration_mod_id( perk_integration( perk ) );
}

std::string integration_mod_name( const perk_def &perk )
{
    switch( perk_integration( perk ) ) {
        case integration_id::magiclysm: return "Magiclysm";
        case integration_id::mindovermatter: return "Mind Over Matter";
        case integration_id::xedra_evolved: return "Xedra Evolved";
        case integration_id::aftershock_exoplanet: return "Aftershock Exoplanet";
        case integration_id::aftershock_prime: return "Aftershock Prime";
        case integration_id::secronom: return "Secronom";
        case integration_id::secronom_plus: return "Secronom+";
        case integration_id::none: break;
    }
    return {};
}

uint32_t branch_theme_color( branch_id branch )
{
    switch( branch ) {
        case branch_id::combat: return NCMM_UI_COLOR_RED;
        case branch_id::survival: return NCMM_UI_COLOR_GREEN;
        case branch_id::mobility: return NCMM_UI_COLOR_CYAN;
        case branch_id::crafting: return NCMM_UI_COLOR_YELLOW;
        case branch_id::scavenging: return NCMM_UI_COLOR_BLUE;
        case branch_id::mastery: return NCMM_UI_COLOR_MAGENTA;
    }
    return NCMM_UI_COLOR_DEFAULT;
}

uint32_t integration_theme_color( const std::string &mod_id )
{
    if( mod_id == "magiclysm" ) return NCMM_UI_COLOR_MAGENTA;
    if( mod_id == "mindovermatter" ) return NCMM_UI_COLOR_CYAN;
    if( mod_id == "xedra_evolved" ) return NCMM_UI_COLOR_GREEN;
    if( mod_id == "aftershock_exoplanet" ) return NCMM_UI_COLOR_BLUE;
    if( mod_id == "aftershock_prime" ) return NCMM_UI_COLOR_MAGENTA;
    if( mod_id == "secronom" ) return NCMM_UI_COLOR_RED;
    if( mod_id == "secronom_lore_expansion" ) return NCMM_UI_COLOR_YELLOW;
    return NCMM_UI_COLOR_DEFAULT;
}

ncmm_ui_theme_v1 branch_ui_theme( branch_id branch )
{
    return { branch_theme_color( branch ),
             NCMM_UI_THEME_STRONG_BORDER | NCMM_UI_THEME_WIDE_NODES,
             30, 46, nullptr, 0 };
}

ncmm_ui_theme_v1 integration_ui_theme( const std::string &mod_id )
{
    return { integration_theme_color( mod_id ),
             NCMM_UI_THEME_STRONG_BORDER | NCMM_UI_THEME_WIDE_NODES,
             30, 46, nullptr, 0 };
}

std::string compact_tree_badge( const perk_def &perk, bool unlocked,
                                int64_t perk_points, int64_t major_points,
                                bool mod_branch )
{
    const int rank = perk_rank( perk );
    const int max_rank = perk_max_rank( perk );
    const bool maxed = rank >= max_rank;
    const bool enough = perk.currency == currency_id::perk ? perk_points > 0 : major_points > 0;

    std::string result;
    if( mod_branch ) {
        result = "MOD";
    }
    const std::string chevrons = rank_chevrons( perk );
    if( !chevrons.empty() ) {
        if( !result.empty() ) result += " | ";
        result += chevrons;
    }
    if( !result.empty() ) result += " | ";
    if( maxed ) {
        result += max_rank > 1 ? tr( "MAX ", "МАКС " ) + std::to_string( rank ) + "/" +
                  std::to_string( max_rank ) : tr( "OWN", "КУП" );
    } else if( rank > 0 ) {
        result += "R" + std::to_string( rank ) + "/" + std::to_string( max_rank );
    } else if( !unlocked ) {
        result += tr( "LOCK", "ЗАКР" );
    } else if( !enough ) {
        result += tr( "NO PTS", "НЕТ ОЧК" );
    } else {
        result += tr( "READY", "ГОТОВ" );
    }
    return result;
}
bool perk_world_available( const perk_def &perk )
{
    const integration_id integration = perk_integration( perk );
    if( integration == integration_id::none ) {
        return true;
    }
    return active_world_mod( integration_mod_id( integration ) );
}

int specialization_root_slot( const char *raw_id )
{
    const std::string_view id = raw_id ? std::string_view( raw_id ) : std::string_view();
    if( id == "spc_c_juggernaut" || id == "spc_s_nomad" || id == "spc_m_sprinter" ||
        id == "spc_f_systems" || id == "spc_g_prospector" || id == "spc_a_specialist" ) return 1;
    if( id == "spc_c_duelist" || id == "spc_s_medic" || id == "spc_m_ghost" ||
        id == "spc_f_improviser" || id == "spc_g_courier" || id == "spc_a_polymath" ) return 2;
    if( id == "spc_c_tactician" || id == "spc_s_quartermaster" || id == "spc_m_pathfinder" ||
        id == "spc_f_researcher" || id == "spc_g_investigator" || id == "spc_a_selfteacher" ) return 3;
    return 0;
}

int specialization_slot( const perk_def &perk )
{
    const int direct = specialization_root_slot( perk.id );
    if( direct > 0 ) {
        return direct;
    }
    return specialization_root_slot( perk.prereq1 );
}

bool specialization_perk( const perk_def &perk )
{
    return specialization_slot( perk ) > 0;
}

bool specialization_root( const perk_def &perk )
{
    return specialization_root_slot( perk.id ) > 0;
}

std::string specialization_state_key( branch_id branch )
{
    switch( branch ) {
        case branch_id::combat: return "spec_combat";
        case branch_id::survival: return "spec_survival";
        case branch_id::mobility: return "spec_mobility";
        case branch_id::crafting: return "spec_crafting";
        case branch_id::scavenging: return "spec_scavenging";
        case branch_id::mastery: return "spec_mastery";
    }
    return "spec_unknown";
}

bool specialization_allowed( const perk_def &perk )
{
    if( !specialization_perk( perk ) ) {
        return true;
    }
    const int slot = specialization_slot( perk );
    const int64_t selected_slot = get_state( specialization_state_key( perk.branch ), 0 );
    if( specialization_root( perk ) ) {
        return selected_slot == 0 || selected_slot == slot;
    }
    return selected_slot == slot;
}

bool owned( const perk_def &perk )
{
    return perk_world_available( perk ) && perk_rank( perk ) > 0;
}

const perk_def *find_perk( const char *id )
{
    if( id == nullptr || *id == '\0' ) {
        return nullptr;
    }
    static const std::map<std::string_view, const perk_def *> index = []() {
        std::map<std::string_view, const perk_def *> result;
        for( const perk_def &perk : perks ) {
            result.emplace( std::string_view( perk.id ), &perk );
        }
        return result;
    }();
    const auto it = index.find( std::string_view( id ) );
    if( it == index.end() || !perk_world_available( *it->second ) ) {
        return nullptr;
    }
    return it->second;
}

int64_t xp_to_next( int64_t level )
{
    level = std::max<int64_t>( 1, level );
    if( level <= 30 ) {
        return 30 + ( level - 1 ) * 15;
    }

    // Keep the proven early curve intact, then transition to a slow quadratic tail.
    // There is no gameplay level cap; the numeric saturation only prevents int64 overflow.
    const long double d = static_cast<long double>( level - 30 );
    const long double required = 465.0L + 12.0L * d + 0.20L * d * d;
    const long double safe_max = static_cast<long double>(
                                     std::numeric_limits<int64_t>::max() / 4 );
    if( required >= safe_max ) {
        return std::numeric_limits<int64_t>::max() / 4;
    }
    return std::max<int64_t>( 1, static_cast<int64_t>( std::llround( required ) ) );
}

const char *branch_name_en( branch_id branch )
{
    switch( branch ) {
        case branch_id::combat: return "Combat";
        case branch_id::survival: return "Survival";
        case branch_id::mobility: return "Mobility";
        case branch_id::crafting: return "Crafting";
        case branch_id::scavenging: return "Scavenging";
        case branch_id::mastery: return "Mastery";
    }
    return "Unknown";
}

const char *branch_name_ru( branch_id branch )
{
    switch( branch ) {
        case branch_id::combat: return "Бой";
        case branch_id::survival: return "Выживание";
        case branch_id::mobility: return "Мобильность";
        case branch_id::crafting: return "Крафт";
        case branch_id::scavenging: return "Добыча";
        case branch_id::mastery: return "Мастерство";
    }
    return "Неизвестно";
}

std::string branch_name( branch_id branch )
{
    return russian() ? branch_name_ru( branch ) : branch_name_en( branch );
}

std::string branch_focus( branch_id branch )
{
    switch( branch ) {
        case branch_id::combat:
            return tr( "Power / accuracy / battle tempo", "Сила / точность / темп боя" );
        case branch_id::survival:
            return tr( "Stamina / healing / carrying", "Выносливость / лечение / груз" );
        case branch_id::mobility:
            return tr( "Speed / movement / endurance", "Скорость / движение / резерв" );
        case branch_id::crafting:
            return tr( "Crafting / study / intelligence", "Крафт / обучение / интеллект" );
        case branch_id::scavenging:
            return tr( "Perception / load / long routes", "Восприятие / груз / маршруты" );
        case branch_id::mastery:
            return tr( "XP / synergy / global growth", "Опыт / синергия / общий рост" );
    }
    return {};
}
const std::array<branch_id, 6> all_branches = {
    branch_id::combat, branch_id::survival, branch_id::mobility,
    branch_id::crafting, branch_id::scavenging, branch_id::mastery
};

const char *branch_tag( branch_id branch )
{
    switch( branch ) {
        case branch_id::combat: return "combat";
        case branch_id::survival: return "survival";
        case branch_id::mobility: return "mobility";
        case branch_id::crafting: return "crafting";
        case branch_id::scavenging: return "scavenging";
        case branch_id::mastery: return "mastery";
    }
    return "unknown";
}

std::string branch_state_key( branch_id branch, const char *suffix )
{
    return std::string( "b_" ) + branch_tag( branch ) + "_" + suffix;
}

int64_t branch_xp_to_next( int64_t level )
{
    level = std::max<int64_t>( 1, level );
    const long double required = 20.0L + static_cast<long double>( level - 1 ) * 10.0L;
    return required >= 1000000.0L ? 1000000 : static_cast<int64_t>( required );
}

int64_t branch_level( branch_id branch )
{
    return std::max<int64_t>( 1, get_state( branch_state_key( branch, "level" ), 1 ) );
}

int64_t branch_xp( branch_id branch )
{
    return std::max<int64_t>( 0, get_state( branch_state_key( branch, "xp" ), 0 ) );
}

std::string branch_xp_source( branch_id branch )
{
    switch( branch ) {
        case branch_id::combat:
            return tr( "Kills; dangerous targets are worth more.",
                       "Убийства; опасные цели дают больше опыта." );
        case branch_id::survival:
            return tr( "Real damage healed.",
                       "Фактически восстановленное здоровье." );
        case branch_id::mobility:
            return tr( "Active movement over the map.",
                       "Активное перемещение по карте." );
        case branch_id::crafting:
            return tr( "Successfully completed crafting activities.",
                       "Успешно завершённый крафт." );
        case branch_id::scavenging:
            return tr( "Entering overmap tiles while exploring.",
                       "Переходы между клетками глобальной карты." );
        case branch_id::mastery:
            return tr( "Skill level-ups plus 10% of other branch XP.",
                       "Рост навыков плюс 10% опыта остальных веток." );
    }
    return {};
}
int64_t branch_fatigue( branch_id branch )
{
    return std::max<int64_t>( 0,
                              std::min<int64_t>( 1000,
                                  get_state( branch_state_key( branch, "fatigue" ), 0 ) ) );
}

int branch_xp_efficiency_pct( branch_id branch )
{
    const int64_t fatigue = branch_fatigue( branch );
    if( fatigue < 70 ) {
        return 100;
    }
    if( fatigue < 160 ) {
        return 80;
    }
    if( fatigue < 280 ) {
        return 60;
    }
    if( fatigue < 430 ) {
        return 40;
    }
    if( fatigue < 620 ) {
        return 20;
    }
    return 10;
}

std::string branch_efficiency_text( branch_id branch )
{
    return tr( "XP efficiency ", "Эффективность XP " ) +
           std::to_string( branch_xp_efficiency_pct( branch ) ) + "%";
}

void decay_branch_fatigue()
{
    for( branch_id branch : all_branches ) {
        const int64_t decay = branch == branch_id::mastery ? 20 : 14;
        set_state( branch_state_key( branch, "fatigue" ),
                   std::max<int64_t>( 0, branch_fatigue( branch ) - decay ) );
    }
}

int64_t anti_farm_adjust( branch_id branch, int64_t raw )
{
    if( raw <= 0 ) {
        set_state( branch_state_key( branch, "streak" ), 0 );
        return 0;
    }

    int64_t streak = std::max<int64_t>( 0,
        get_state( branch_state_key( branch, "streak" ), 0 ) );
    streak = std::min<int64_t>( 12, streak + 1 );
    set_state( branch_state_key( branch, "streak" ), streak );

    const int efficiency = branch_xp_efficiency_pct( branch );
    int64_t adjusted = raw * efficiency / 100;
    if( adjusted == 0 && raw >= 5 && efficiency >= 20 ) {
        adjusted = 1;
    }

    int64_t fatigue_gain = branch == branch_id::mastery ?
                           raw * 3 : raw * 8;
    fatigue_gain += std::max<int64_t>( 0, streak - 2 ) * 6;
    fatigue_gain = std::min<int64_t>( 180, fatigue_gain );

    set_state( branch_state_key( branch, "fatigue" ),
               std::min<int64_t>( 1000, branch_fatigue( branch ) + fatigue_gain ) );
    return adjusted;
}

int branch_owned_count( branch_id branch )
{
    int result = 0;
    for( const perk_def &perk : perks ) {
        if( perk.branch == branch && !integration_perk( perk ) &&
            perk_world_available( perk ) && owned( perk ) ) {
            ++result;
        }
    }
    return result;
}

int branch_total_count( branch_id branch )
{
    int result = 0;
    for( const perk_def &perk : perks ) {
        if( perk.branch == branch && !integration_perk( perk ) &&
            perk_world_available( perk ) ) {
            ++result;
        }
    }
    return result;
}

int visible_perk_count()
{
    int result = 0;
    for( const perk_def &perk : perks ) {
        if( perk_world_available( perk ) ) {
            ++result;
        }
    }
    return result;
}

int owned_count( currency_id currency )
{
    int result = 0;
    for( const perk_def &perk : perks ) {
        if( perk.currency == currency && perk_world_available( perk ) && owned( perk ) ) {
            ++result;
        }
    }
    return result;
}

std::string format_number( double value )
{
    std::ostringstream out;
    const double rounded = std::round( value );
    if( std::abs( value - rounded ) < 0.0001 ) {
        out << static_cast<long long>( rounded );
    } else {
        out << std::fixed << std::setprecision( 2 ) << value;
    }
    return out.str();
}

std::string effect_label( const std::string &id )
{
    if( id == "str_flat" ) return tr( "STR", "СИЛ" );
    if( id == "dex_flat" ) return tr( "DEX", "ЛОВ" );
    if( id == "per_flat" ) return tr( "PER", "ВОС" );
    if( id == "int_flat" ) return tr( "INT", "ИНТ" );
    if( id == "speed_pct" ) return tr( "Speed %", "Скорость %" );
    if( id == "move_cost_pct" ) return tr( "Move cost %", "Стоимость движения %" );
    if( id == "stamina_max_pct" ) return tr( "Max stamina %", "Макс. выносливость %" );
    if( id == "carry_weight_pct" ) return tr( "Carry %", "Грузоподъёмность %" );
    if( id == "dodge_flat" ) return tr( "Dodge", "Уклонение" );
    if( id == "melee_hit_flat" ) return tr( "Melee hit", "Точность ближнего боя" );
    if( id == "healing_pct" ) return tr( "Healing %", "Лечение %" );
    if( id == "read_speed_pct" ) return tr( "Reading %", "Чтение %" );
    if( id == "craft_speed_pct" ) return tr( "Crafting %", "Крафт %" );
    if( id == "mg_spellcraft_flat" ) return "Magiclysm Spellcraft";
    if( id == "mom_metaphysics_flat" ) return "MoM channeling Metaphysics";
    if( id == "xe_deduction_flat" ) return "Xedra Deduction";
    if( id == "xe_gramarye_flat" ) return "Xedra Gramarye";
    if( id == "af_smartgun_flat" ) return "Aftershock Smartgun";
    if( id == "af_metaphysics_flat" ) return "Aftershock Exoplanet channeling Metaphysics";
    if( id == "afp_smartgun_flat" ) return "Aftershock Prime Smartgun";
    if( id == "secx_flesh_craft_flat" ) return "Secronom+ Flesh Weaving";
    if( id == "secx_flesh_combat_flat" ) return "Secronom+ Bio-organic Weapons";
    if( id == "sec_damage_pct" ) return tr( "Damage vs Secronom %", "Урон по Secronom %" );
    if( id == "sec_resist_pct" ) return tr( "Resistance vs Secronom %", "Защита от Secronom %" );
    if( id == "sec_elite_damage_pct" ) return tr( "Damage vs Secronom elites %", "Урон по элите Secronom %" );
    if( id == "sec_elite_resist_pct" ) return tr( "Resistance vs Secronom elites %", "Защита от элиты Secronom %" );
    if( id == "sec_crimson_damage_pct" ) return tr( "Damage vs Crimson Horrors %", "Урон по Crimson Horrors %" );
    if( id == "sec_crimson_resist_pct" ) return tr( "Resistance vs Crimson Horrors %", "Защита от Crimson Horrors %" );
    if( id.find( "spell_cost_pct" ) != std::string::npos ) return tr( "Power cost %", "Стоимость силы %" );
    if( id.find( "cast_time_pct" ) != std::string::npos ) return tr( "Cast time %", "Время применения %" );
    if( id.find( "fail_pct" ) != std::string::npos ) return tr( "Failure %", "Провал %" );
    if( id.find( "spell_xp_pct" ) != std::string::npos ) return tr( "Spell/power XP %", "Опыт сил %" );
    if( id.find( "spell_power_pct" ) != std::string::npos ) return tr( "Spell/power potency %", "Мощность сил %" );
    if( id.find( "range_pct" ) != std::string::npos ) return tr( "Range %", "Дальность %" );
    if( id.find( "aoe_pct" ) != std::string::npos ) return tr( "Area %", "Площадь %" );
    if( id.find( "duration_pct" ) != std::string::npos ) return tr( "Duration %", "Длительность %" );
    return id;
}

std::string ranked_effect_summary( const perk_def &perk, int rank )
{
    if( rank <= 0 ) {
        return {};
    }

    const double multiplier = perk_rank_multiplier_for( perk, rank );
    std::vector<std::string> parts;
    for( int i = 0; i < perk.effect_count; ++i ) {
        if( perk.effects[i].id == nullptr ) {
            continue;
        }
        const double value = perk.effects[i].value * multiplier;
        const std::string sign = value > 0.0 ? "+" : "";
        parts.push_back( effect_label( perk.effects[i].id ) + ": " +
                         sign + format_number( value ) );
    }
    if( perk.xp_bonus_pct != 0 ) {
        const int value = static_cast<int>(
                              std::llround( static_cast<double>( perk.xp_bonus_pct ) * multiplier ) );
        parts.push_back( tr( "Survivor XP: +", "Опыт Survivor: +" ) +
                         std::to_string( value ) + "%" );
    }

    std::string result;
    for( size_t i = 0; i < parts.size(); ++i ) {
        if( i != 0 ) {
            result += ", ";
        }
        result += parts[i];
    }
    return result;
}

std::string perk_description( const perk_def &perk )
{
    std::string result = russian() ? perk.desc_ru : perk.desc_en;
    const int max_rank = perk_max_rank( perk );
    if( max_rank <= 1 ) {
        return result;
    }

    const int rank = perk_rank( perk );
    result += "\n" + tr( "Rank ", "Ранг " ) + std::to_string( rank ) + "/" +
              std::to_string( max_rank );

    if( rank > 0 ) {
        result += "\n" + tr( "Current: ", "Сейчас: " ) +
                  ranked_effect_summary( perk, rank );
    }
    if( rank < max_rank ) {
        result += "\n" + tr( "Next: ", "Следующий: " ) +
                  ranked_effect_summary( perk, rank + 1 );
    }
    return result;
}
struct calculated_effects {
    std::map<std::string, double> modifiers;
    int xp_bonus_pct = 0;
    int active_branches = 0;
    int major_owned = 0;
    std::array<double, 6> branch_amp = {{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 }};
    double global_amp = 1.0;
};

int branch_index( branch_id branch )
{
    switch( branch ) {
        case branch_id::combat: return 0;
        case branch_id::survival: return 1;
        case branch_id::mobility: return 2;
        case branch_id::crafting: return 3;
        case branch_id::scavenging: return 4;
        case branch_id::mastery: return 5;
    }
    return 0;
}

calculated_effects calculate_owned_effects()
{
    calculated_effects result;
    std::array<bool, 6> branch_active = {{ false, false, false, false, false, false }};

    // Pass 1: one ownership lookup per perk.  The old implementation scanned the
    // full catalog once per branch, then again for majors and amplifier effects.
    for( const perk_def &perk : perks ) {
        if( !perk_world_available( perk ) ) {
            continue;
        }
        const int rank = perk_rank( perk );
        if( rank <= 0 ) {
            continue;
        }
        if( !integration_perk( perk ) ) {
            branch_active[branch_index( perk.branch )] = true;
        }
        if( perk.currency == currency_id::major ) {
            ++result.major_owned;
        }
        if( effective_kind( perk ) == perk_kind::effect ) {
            const double rank_scale = perk_rank_multiplier_for( perk, rank );
            result.branch_amp[branch_index( perk.branch )] +=
                perk.branch_amp_pct * rank_scale / 100.0;
            result.global_amp += perk.global_amp_pct * rank_scale / 100.0;
        }
    }
    for( bool active : branch_active ) {
        if( active ) {
            ++result.active_branches;
        }
    }

    // Pass 2: resolve scaling after active-branch and major totals are known.
    for( const perk_def &perk : perks ) {
        if( !perk_world_available( perk ) ) {
            continue;
        }
        const int rank = perk_rank( perk );
        if( rank <= 0 ) {
            continue;
        }

        double scale = 1.0;
        if( perk.scaling == perk_scaling::per_active_branch ) {
            scale = static_cast<double>( result.active_branches );
        } else if( perk.scaling == perk_scaling::per_owned_major ) {
            scale = static_cast<double>( result.major_owned );
        }

        scale *= perk_rank_multiplier_for( perk, rank );

        if( effective_kind( perk ) == perk_kind::stat ) {
            scale *= result.global_amp * result.branch_amp[branch_index( perk.branch )];
        }

        result.xp_bonus_pct += static_cast<int>( std::llround( perk.xp_bonus_pct * scale ) );
        for( int i = 0; i < perk.effect_count; ++i ) {
            if( perk.effects[i].id != nullptr ) {
                result.modifiers[perk.effects[i].id] += perk.effects[i].value * scale;
            }
        }
    }

    result.xp_bonus_pct = std::max( 0, std::min( 5000, result.xp_bonus_pct ) );
    return result;
}

std::map<std::string, double> owned_effect_totals()
{
    return calculate_owned_effects().modifiers;
}

int64_t perk_progression_level( const perk_def &perk )
{
    if( integration_perk( perk ) ) {
        return std::max<int64_t>( 1, get_state( "level", 1 ) );
    }
    return branch_level( perk.branch );
}
bool prerequisites_met( const perk_def &perk )
{
    if( !perk_world_available( perk ) || !specialization_allowed( perk ) ) {
        return false;
    }
    for( const char *id : { perk.prereq1, perk.prereq2 } ) {
        if( id == nullptr || *id == '\0' ) {
            continue;
        }
        const perk_def *required = find_perk( id );
        if( required == nullptr || !owned( *required ) ) {
            return false;
        }
    }
    return true;
}

std::string prereq_text( const perk_def &perk )
{
    std::vector<std::string> names;
    for( const char *id : { perk.prereq1, perk.prereq2 } ) {
        if( id == nullptr || *id == '\0' ) {
            continue;
        }
        const perk_def *required = find_perk( id );
        if( required != nullptr ) {
            names.emplace_back( russian() ? required->name_ru : required->name_en );
        }
    }
    if( names.empty() ) {
        return tr( "none", "нет" );
    }
    if( names.size() == 1 ) {
        return names[0];
    }
    return names[0] + " + " + names[1];
}

void clear_runtime_modifiers()
{
    if( host && host->character_modifier_clear_module ) {
        host->character_modifier_clear_module( module_id );
    }
    current_xp_bonus_pct = 0;
}

void recalculate_effects()
{
    if( !character_available() || !host || !host->character_modifier_set ||
        !host->character_modifier_clear_module ) {
        clear_runtime_modifiers();
        effects_dirty = true;
        return;
    }

    const calculated_effects calculated = calculate_owned_effects();

    host->character_modifier_clear_module( module_id );
    for( const auto &entry : calculated.modifiers ) {
        if( entry.second != 0.0 &&
            !host->character_modifier_set( module_id, entry.first.c_str(), entry.second ) ) {
            if( host->log ) {
                const std::string msg = "Survivor Progression: host rejected modifier " + entry.first;
                host->log( NCMM_LOG_WARN, msg.c_str() );
            }
        }
    }

    current_xp_bonus_pct = calculated.xp_bonus_pct;
    effects_dirty = false;
}

void migrate_state()
{
    if( !character_available() ) {
        return;
    }

    const int64_t schema = get_state( "schema", 0 );
    if( schema >= state_schema ) {
        return;
    }

    int64_t level = std::max<int64_t>( 1, get_state( "level", 1 ) );
    set_state( "level", level );

    int64_t xp = std::max<int64_t>( 0, get_state( "xp", 0 ) );
    int64_t fraction = std::max<int64_t>( 0, get_state( "xp_fraction", 0 ) );
    if( fraction >= 100 ) {
        xp += fraction / 100;
        fraction %= 100;
    }
    set_state( "xp", xp );
    set_state( "xp_fraction", fraction );
    set_state( "perk_points", std::max<int64_t>( 0, get_state( "perk_points", 0 ) ) );
    set_state( "major_points", std::max<int64_t>( 0, get_state( "major_points", 0 ) ) );

    // Preserve the old 0.1.x Fast Learner purchase.
    if( get_state( "fast_learner", 0 ) != 0 ) {
        const perk_def *legacy = find_perk( "a_fast" );
        if( legacy != nullptr && !owned( *legacy ) ) {
            set_state( perk_key( *legacy ), 1 );
        }
    }

    // Base major points continue every five levels forever.
    const int64_t expected_major_awards = level / 5;
    int64_t major_awarded = std::max<int64_t>( 0, get_state( "major_awarded", 0 ) );
    int64_t major_points = get_state( "major_points", 0 );
    if( major_awarded < expected_major_awards ) {
        major_points += expected_major_awards - major_awarded;
        major_awarded = expected_major_awards;
        set_state( "major_points", major_points );
    }
    if( major_awarded > expected_major_awards ) {
        major_awarded = expected_major_awards;
    }
    set_state( "major_awarded", major_awarded );

    for( branch_id branch : all_branches ) {
        set_state( branch_state_key( branch, "level" ),
                   std::max<int64_t>( 1, get_state( branch_state_key( branch, "level" ), 1 ) ) );
        set_state( branch_state_key( branch, "xp" ),
                   std::max<int64_t>( 0, get_state( branch_state_key( branch, "xp" ), 0 ) ) );
        const int64_t selected_spec = get_state( specialization_state_key( branch ), 0 );
        set_state( specialization_state_key( branch ),
                   selected_spec >= 1 && selected_spec <= 3 ? selected_spec : 0 );
    }
    for( const char *key : {
             "metric_combat_kills", "metric_combat_kill_xp", "metric_survival_healing",
             "metric_mobility_steps", "metric_crafting_completed", "metric_scavenging_omt",
             "metric_mastery_skill_levels"
         } ) {
        if( get_state( key, std::numeric_limits<int64_t>::min() ) ==
            std::numeric_limits<int64_t>::min() ) {
            set_state( key, -1 );
        }
    }
    set_state( "survival_heal_remainder",
               std::max<int64_t>( 0, get_state( "survival_heal_remainder", 0 ) ) );
    set_state( "mobility_step_remainder",
               std::max<int64_t>( 0, get_state( "mobility_step_remainder", 0 ) ) );
    set_state( "mastery_share_fraction",
               std::max<int64_t>( 0, get_state( "mastery_share_fraction", 0 ) ) % 100 );

    for( branch_id branch : all_branches ) {
        set_state( branch_state_key( branch, "fatigue" ),
                   std::max<int64_t>( 0,
                       std::min<int64_t>( 1000,
                           get_state( branch_state_key( branch, "fatigue" ), 0 ) ) ) );
        set_state( branch_state_key( branch, "streak" ),
                   std::max<int64_t>( 0,
                       std::min<int64_t>( 12,
                           get_state( branch_state_key( branch, "streak" ), 0 ) ) ) );
    }

    set_state( "schema", state_schema );
    effects_dirty = true;
}

std::string status_prefix( const perk_def &perk, int64_t level, int64_t perk_points, int64_t major_points )
{
    const int rank = perk_rank( perk );
    const int max_rank = perk_max_rank( perk );
    const std::string chevrons = rank_chevrons( perk );
    const std::string rank_prefix = chevrons.empty() ? std::string() : "[" + chevrons + "] ";
    if( rank >= max_rank ) {
        return rank_prefix + "[✓] ";
    }
    if( level < perk.required_level ) {
        return rank_prefix + std::string( russian() ? "[УР " : "[L" ) +
               std::to_string( perk.required_level ) + "] ";
    }
    if( !prerequisites_met( perk ) ) {
        return rank_prefix + ( russian() ? "[ТРЕБ.] " : "[REQ] " );
    }
    const bool enough = perk.currency == currency_id::perk ? perk_points > 0 : major_points > 0;
    if( !enough ) {
        return rank_prefix + ( russian() ? "[НЕТ ОЧКОВ] " : "[NO POINTS] " );
    }
    return rank_prefix + ( perk.currency == currency_id::perk ? "[1P] " : "[1M] " );
}

std::string cost_text( const perk_def &perk )
{
    return perk.currency == currency_id::perk ?
           tr( "1 perk point", "1 очко перка" ) :
           tr( "1 major point", "1 большое очко" );
}

bool purchase_perk( const perk_def &perk )
{
    const int64_t level = perk_progression_level( perk );
    int64_t perk_points = get_state( "perk_points", 0 );
    int64_t major_points = get_state( "major_points", 0 );
    const int rank = perk_rank( perk );
    const int max_rank = perk_max_rank( perk );

    if( !perk_world_available( perk ) ) {
        message( tr( "The required world mod is not active.", "Требуемый мод мира не активен." ) );
        return false;
    }
    if( rank >= max_rank ) {
        message( tr( "This perk is already at maximum rank.",
                     "Этот перк уже максимального ранга." ) );
        return false;
    }
    if( level < perk.required_level ) {
        message( integration_perk( perk ) ?
                 tr( "Your Survivor level is too low for this mod perk.",
                     "Недостаточный уровень Survivor для этого перка мода." ) :
                 tr( "Your branch level is too low.", "Недостаточный уровень этой ветки." ) );
        return false;
    }
    if( !prerequisites_met( perk ) ) {
        if( specialization_perk( perk ) && !specialization_allowed( perk ) ) {
            message( tr( "Another specialization is already committed in this branch. Respec to change it.",
                         "В этой ветке уже выбрана другая специализация. Для смены нужен сброс." ) );
        } else {
            message( tr( "Prerequisites are not met.", "Не выполнены требования предыдущих перков." ) );
        }
        return false;
    }

    int chosen_slot = 0;
    if( specialization_root( perk ) ) {
        chosen_slot = specialization_slot( perk );
        const int64_t existing = get_state( specialization_state_key( perk.branch ), 0 );
        if( existing == 0 ) {
            std::string prompt = tr(
                "Commit to this specialization? The other two paths in this branch will lock until a full respec.\n",
                "Выбрать эту специализацию? Два других пути этой ветки закроются до полного сброса.\n" );
            prompt += perk_display_name( perk );
            std::string yes = tr( "Commit", "Выбрать" );
            std::string no = tr( "Cancel", "Отмена" );
            const char *entries[] = { yes.c_str(), no.c_str() };
            const int choice = host->ui_choose ? host->ui_choose( prompt.c_str(), entries, 2 ) : -1;
            if( choice != 0 ) return false;
        }
    }

    if( perk.currency == currency_id::perk ) {
        if( perk_points <= 0 ) {
            message( tr( "Not enough perk points.", "Недостаточно очков перков." ) );
            return false;
        }
        set_state( "perk_points", perk_points - 1 );
    } else {
        if( major_points <= 0 ) {
            message( tr( "Not enough major points.", "Недостаточно больших очков." ) );
            return false;
        }
        set_state( "major_points", major_points - 1 );
    }

    if( chosen_slot > 0 ) set_state( specialization_state_key( perk.branch ), chosen_slot );
    set_state( perk_key( perk ), rank + 1 );
    effects_dirty = true;
    recalculate_effects();

    std::string text = rank == 0 ? tr( "Perk purchased: ", "Куплен перк: " ) :
                                   tr( "Perk upgraded: ", "Перк улучшен: " );
    text += russian() ? perk.name_ru : perk.name_en;
    if( max_rank > 1 ) text += " " + std::to_string( rank + 1 ) + "/" + std::to_string( max_rank );
    message( text );
    return true;
}

void show_perk_detail( const perk_def &perk )
{
    while( true ) {
        const int level = static_cast<int>( perk_progression_level( perk ) );
        const int rank = perk_rank( perk );
        const int max_rank = perk_max_rank( perk );
        const bool maxed = rank >= max_rank;
        const bool unlocked = level >= perk.required_level && prerequisites_met( perk );

        std::string title = perk_display_name( perk );
        title += "\n" + perk_description( perk );
        title += "\n" + tr( "Tier ", "Тир " ) + std::to_string( perk.tier );
        if( integration_perk( perk ) ) {
            title += " | " + tr( "Requires Survivor level ", "Нужен уровень Survivor " ) +
                     std::to_string( perk.required_level );
        } else {
            title += " | " + tr( "Requires branch level ", "Нужен уровень ветки " ) +
                     std::to_string( perk.required_level );
        }
        title += "\n" + tr( "Prerequisites: ", "Требования: " ) + prereq_text( perk );
        title += "\n" + tr( "Cost per rank: ", "Цена за ранг: " ) + cost_text( perk );
        if( specialization_root( perk ) ) {
            title += "\n" + tr( "Exclusive choice: locks the other two specializations until full respec.",
                                  "Эксклюзивный выбор: две другие специализации закроются до полного сброса." );
        }
        if( integration_perk( perk ) ) {
            title += "\n" + tr( "World mod: ", "Мод мира: " ) + integration_mod_name( perk );
            title += "\n" + tr( "Mod-native effect: does not grant generic Survivor STR/DEX/PER/INT/speed/carry bonuses.",
                                  "Эффект мода: не даёт общих бонусов Survivor к СИЛ/ЛОВ/ВОС/ИНТ/скорости/грузу." );
        }

        std::string buy;
        if( maxed ) buy = tr( "[Maximum rank]", "[Максимальный ранг]" );
        else if( !unlocked ) buy = tr( "Locked", "Закрыто" );
        else if( rank > 0 ) buy = tr( "Upgrade to rank ", "Улучшить до ранга " ) +
                                  std::to_string( rank + 1 ) + "/" + std::to_string( max_rank );
        else buy = tr( "Purchase", "Купить" );

        std::string back = tr( "Back", "Назад" );
        const char *entries[] = { buy.c_str(), back.c_str() };
        const int choice = host->ui_choose ? host->ui_choose( title.c_str(), entries, 2 ) : -1;
        if( choice != 0 ) return;
        if( maxed ) return;
        if( !unlocked ) {
            message( tr( "This perk is locked.", "Этот перк пока закрыт." ) );
            continue;
        }
        purchase_perk( perk );
        return;
    }
}

int branch_unlocked_count( branch_id branch, int64_t )
{
    const int64_t level = branch_level( branch );
    int result = 0;
    for( const perk_def &perk : perks ) {
        if( perk.branch == branch && !integration_perk( perk ) &&
            perk_world_available( perk ) && !perk_maxed( perk ) &&
            level >= perk.required_level && prerequisites_met( perk ) ) {
            ++result;
        }
    }
    return result;
}

struct card_text {
    std::string id;
    std::string title;
    std::string subtitle;
    std::string body;
    std::string badge;
    std::string icon_key;
    uint32_t flags = NCMM_UI_CARD_NONE;
};

std::vector<ncmm_ui_card_v1> bind_cards( std::vector<card_text> &texts )
{
    std::vector<ncmm_ui_card_v1> result;
    result.reserve( texts.size() );
    for( card_text &text : texts ) {
        result.push_back( {
            text.id.c_str(),
            text.title.c_str(),
            text.subtitle.c_str(),
            text.body.c_str(),
            text.badge.c_str(),
            text.icon_key.c_str(),
            text.flags
        } );
    }
    return result;
}

struct tree_node_text {
    card_text card;
    int row = 0;
    int column = 0;
};

std::pair<int, int> branch_tree_position( branch_id branch, size_t branch_index )
{
    // Base 20-node topology is preserved exactly for save/UI familiarity.
    static const std::array<std::pair<int, int>, 20> standard = {{
        { 0, 0 }, { 0, 4 }, { 2, 0 }, { 2, 4 }, { 4, 0 }, { 4, 4 },
        { 6, 0 }, { 6, 4 }, { 8, 2 }, { 10, 2 },
        { 1, 1 }, { 1, 3 }, { 3, 1 }, { 3, 3 }, { 5, 1 }, { 5, 3 },
        { 7, 1 }, { 7, 3 }, { 9, 2 }, { 11, 2 }
    }};
    static const std::array<std::pair<int, int>, 20> mobility = {{
        { 0, 0 }, { 0, 4 }, { 2, 1 }, { 2, 3 }, { 4, 0 }, { 4, 4 },
        { 6, 1 }, { 6, 3 }, { 8, 2 }, { 10, 2 },
        { 1, 1 }, { 1, 3 }, { 3, 0 }, { 3, 4 }, { 5, 1 }, { 5, 3 },
        { 7, 0 }, { 7, 4 }, { 9, 2 }, { 11, 2 }
    }};
    static const std::array<std::pair<int, int>, 20> mastery = {{
        { 0, 1 }, { 0, 3 }, { 2, 0 }, { 2, 4 }, { 4, 1 }, { 4, 3 },
        { 6, 0 }, { 6, 4 }, { 8, 2 }, { 10, 2 },
        { 1, 2 }, { 1, 4 }, { 3, 1 }, { 3, 3 }, { 5, 2 }, { 5, 4 },
        { 7, 1 }, { 7, 3 }, { 9, 2 }, { 11, 2 }
    }};

    if( branch_index < 20 ) {
        if( branch == branch_id::mobility || branch == branch_id::scavenging ) {
            return mobility[branch_index];
        }
        if( branch == branch_id::mastery ) {
            return mastery[branch_index];
        }
        return standard[branch_index];
    }

    // 20..22 are exclusive specialization roots; 23..25 their capstones.
    if( branch_index < 23 ) {
        return { 12, static_cast<int>( ( branch_index - 20 ) * 2 ) };
    }
    if( branch_index < 26 ) {
        return { 14, static_cast<int>( ( branch_index - 23 ) * 2 ) };
    }

    // Conditional mod-integration nodes live below specializations in a compact grid.
    const size_t integration_index = branch_index - 26;
    return { 16 + static_cast<int>( integration_index / 3 ) * 2,
             static_cast<int>( integration_index % 3 ) * 2 };
}

std::vector<ncmm_ui_tree_node_v1> bind_tree_nodes( std::vector<tree_node_text> &texts )
{
    std::vector<ncmm_ui_tree_node_v1> result;
    result.reserve( texts.size() );
    for( tree_node_text &text : texts ) {
        result.push_back( {
            text.card.id.c_str(),
            text.card.title.c_str(),
            text.card.subtitle.c_str(),
            text.card.body.c_str(),
            text.card.badge.c_str(),
            text.card.icon_key.c_str(),
            text.card.flags,
            text.row,
            text.column
        } );
    }
    return result;
}

std::string perk_kind_label( const perk_def &perk )
{
    if( specialization_perk( perk ) ) {
        return tr( "SPECIALIZATION", "СПЕЦИАЛИЗАЦИЯ" );
    }
    if( integration_perk( perk ) ) {
        return tr( "MOD SYNERGY", "СИНЕРГИЯ МОДА" );
    }
    if( perk.currency == currency_id::major ) {
        return tr( "KEYSTONE", "КЛЮЧЕВОЙ" );
    }
    return effective_kind( perk ) == perk_kind::effect ?
           tr( "EFFECT", "ЭФФЕКТ" ) : tr( "STAT", "СТАТ" );
}

std::string branch_icon_key( branch_id branch )
{
    return std::string( "survivor/branch/" ) + branch_name_en( branch );
}

void show_branch( branch_id branch )
{
    bool tree_mode = true;

    while( true ) {
        const int64_t level = branch_level( branch );
        const int64_t perk_points = get_state( "perk_points", 0 );
        const int64_t major_points = get_state( "major_points", 0 );

        std::vector<const perk_def *> branch_perks;
        branch_perks.reserve( 24 );
        std::vector<card_text> texts;
        texts.reserve( 24 );

        for( const perk_def &perk : perks ) {
            if( perk.branch != branch || integration_perk( perk ) || !perk_world_available( perk ) ) {
                continue;
            }
            branch_perks.push_back( &perk );

            const int rank = perk_rank( perk );
            const int max_rank = perk_max_rank( perk );
            const bool maxed = rank >= max_rank;
            const bool unlocked = level >= perk.required_level && prerequisites_met( perk );
            const bool enough = perk.currency == currency_id::perk ?
                                perk_points > 0 : major_points > 0;

            card_text card;
            card.id = perk.id;
            card.title = perk_display_name( perk );
            card.subtitle = "T" + std::to_string( perk.tier ) + " | " +
                            tr( "BLv ", "УрВ " ) + std::to_string( perk.required_level ) +
                            " | " + ( perk.currency == currency_id::perk ? "1P" : "1M" );
            if( max_rank > 1 ) {
                card.subtitle += " | " + tr( "R ", "Р " ) +
                                 std::to_string( rank ) + "/" + std::to_string( max_rank );
            }
            card.body = perk_description( perk );

            card.badge = perk_kind_label( perk );
            const std::string chevrons = rank_chevrons( perk );
            if( !chevrons.empty() ) card.badge += " | " + chevrons;
            card.badge += " | ";
            if( maxed ) {
                card.badge += max_rank > 1 ?
                              tr( "MAX ", "МАКС " ) + std::to_string( rank ) + "/" +
                              std::to_string( max_rank ) :
                              tr( "OWNED", "КУПЛЕНО" );
                card.flags |= NCMM_UI_CARD_OWNED;
            } else if( rank > 0 ) {
                card.badge += tr( "RANK ", "РАНГ " ) + std::to_string( rank ) + "/" +
                              std::to_string( max_rank );
                card.flags |= NCMM_UI_CARD_OWNED;
            } else if( !unlocked ) {
                card.badge += tr( "LOCKED", "ЗАКРЫТО" );
                card.flags |= NCMM_UI_CARD_LOCKED;
            } else if( !enough ) {
                card.badge += tr( "NO POINTS", "НЕТ ОЧКОВ" );
            } else {
                card.badge += tr( "AVAILABLE", "ДОСТУПНО" );
            }

            if( perk.currency == currency_id::major ) {
                card.flags |= NCMM_UI_CARD_MAJOR;
            }
            if( effective_kind( perk ) == perk_kind::effect ) {
                card.flags |= NCMM_UI_CARD_EFFECT;
            }
            card.icon_key = std::string( "survivor/perk/" ) + perk.id;
            texts.push_back( std::move( card ) );
        }

        const int owned_now = branch_owned_count( branch );
        const int total_now = branch_total_count( branch );
        const int unlocked_now = branch_unlocked_count( branch, level );

        std::string title = "Survivor Progression > " + branch_name( branch );
        std::string summary =
            tr( "Purchased ", "Куплено " ) + std::to_string( owned_now ) + "/" +
            std::to_string( total_now ) +
            tr( " | available ", " | доступно " ) + std::to_string( unlocked_now ) +
            " | P " + std::to_string( perk_points ) +
            " | M " + std::to_string( major_points );

        const int64_t blevel = branch_level( branch );
        const int64_t bxp = branch_xp( branch );
        const int64_t bnext = branch_xp_to_next( blevel );
        summary += tr( " | branch L", " | ветка ур." ) + std::to_string( blevel ) +
                   " XP " + std::to_string( bxp ) + "/" + std::to_string( bnext ) +
                   " | " + branch_efficiency_text( branch );

        std::string progress_label =
            branch_name( branch ) + tr( " XP -> L", " XP -> ур." ) +
            std::to_string( blevel + 1 );
        ncmm_ui_progress_v1 progress{
            progress_label.c_str(),
            bxp,
            bnext
        };

        if( tree_mode && host->ui_tree_choose ) {
            std::vector<tree_node_text> tree_texts;
            tree_texts.reserve( branch_perks.size() );
            std::map<std::string, size_t> index_by_id;

            for( size_t i = 0; i < branch_perks.size(); ++i ) {
                const perk_def &perk = *branch_perks[i];
                tree_node_text node;
                node.card = texts[i];
                const int tree_rank = perk_rank( perk );
                const int tree_max_rank = perk_max_rank( perk );
                const bool tree_unlocked = level >= perk.required_level && prerequisites_met( perk );
                node.card.subtitle = "T" + std::to_string( perk.tier ) + " | " +
                                     tr( "L", "ур." ) + std::to_string( perk.required_level ) +
                                     " | " + ( perk.currency == currency_id::perk ? "1P" : "1M" );
                if( tree_max_rank > 1 && tree_rank > 0 ) {
                    node.card.subtitle += " | R" + std::to_string( tree_rank ) + "/" +
                                          std::to_string( tree_max_rank );
                }
                node.card.badge = compact_tree_badge( perk, tree_unlocked,
                                                       perk_points, major_points, false );
                node.card.body += "\n" + tr( "Prerequisites: ", "Требования: " ) +
                                  prereq_text( perk );
                const std::pair<int, int> position = branch_tree_position( branch, i );
                node.row = position.first;
                node.column = position.second;
                index_by_id[perk.id] = i;
                tree_texts.push_back( std::move( node ) );
            }

            std::vector<ncmm_ui_tree_edge_v1> edges;
            auto add_edge = [&]( const char *prereq, size_t to ) {
                if( prereq == nullptr || prereq[0] == '\0' ) {
                    return;
                }
                const auto it = index_by_id.find( prereq );
                if( it != index_by_id.end() ) {
                    edges.push_back( { it->second, to } );
                }
            };
            for( size_t i = 0; i < branch_perks.size(); ++i ) {
                add_edge( branch_perks[i]->prereq1, i );
                add_edge( branch_perks[i]->prereq2, i );
            }

            std::vector<ncmm_ui_tree_node_v1> nodes = bind_tree_nodes( tree_texts );
            const std::string tree_summary =
                summary + tr( " | Routed tree | Tab: cards",
                              " | Разведённое дерево | Tab: карточки" );
            const ncmm_ui_theme_v1 theme = branch_ui_theme( branch );
            const int choice = host->ui_tree_choose_themed(
                                   title.c_str(), tree_summary.c_str(), &progress,
                                   nodes.data(), nodes.size(), edges.data(), edges.size(), &theme );
            if( choice == NCMM_UI_TREE_SHOW_CARDS ) {
                tree_mode = false;
                continue;
            }
            if( choice < 0 || static_cast<size_t>( choice ) >= branch_perks.size() ) {
                return;
            }
            show_perk_detail( *branch_perks[choice] );
            continue;
        }

        std::vector<ncmm_ui_card_v1> cards = bind_cards( texts );
        const std::string card_summary =
            summary + tr( " | Cards | Tab: tree",
                          " | Карточки | Tab: дерево" );
        const ncmm_ui_theme_v1 theme = branch_ui_theme( branch );
        const int choice = host->ui_card_choose_themed ?
                           host->ui_card_choose_themed( title.c_str(), card_summary.c_str(), &progress,
                                                        cards.data(), cards.size(), 2, &theme ) :
                           -1;
        if( choice == NCMM_UI_CARD_SHOW_TREE ) {
            tree_mode = true;
            continue;
        }
        if( choice < 0 || static_cast<size_t>( choice ) >= branch_perks.size() ) {
            return;
        }
        show_perk_detail( *branch_perks[choice] );
    }
}

void show_overview()
{
    const int64_t level = std::max<int64_t>( 1, get_state( "level", 1 ) );
    const int64_t xp = std::max<int64_t>( 0, get_state( "xp", 0 ) );
    const int64_t perk_points = get_state( "perk_points", 0 );
    const int64_t major_points = get_state( "major_points", 0 );
    const int normal_owned = owned_count( currency_id::perk );
    const int major_owned = owned_count( currency_id::major );

    std::string out = "Survivor Progression v0.9.14\n";
    out += tr( "Level ", "Уровень " ) + std::to_string( level );
    out += " | XP " + std::to_string( xp ) + "/" + std::to_string( xp_to_next( level ) );
    out += "\nP " + std::to_string( perk_points ) + " | M " + std::to_string( major_points );
    out += "\n" + tr( "Purchased: ", "Куплено: " ) +
           std::to_string( normal_owned ) + "P / " + std::to_string( major_owned ) + "M";
    out += "\n" + tr( "Major points: every 5 levels, with no level cap.",
                       "Большие очки: каждые 5 уровней, без ограничения уровня." );
    out += "\n" + tr( "Active integrations: ", "Активные интеграции: " );
    std::vector<std::string> integration_names;
    if( active_world_mod( "magiclysm" ) ) integration_names.push_back( "Magiclysm" );
    if( active_world_mod( "mindovermatter" ) ) integration_names.push_back( "Mind Over Matter" );
    if( active_world_mod( "xedra_evolved" ) ) integration_names.push_back( "Xedra Evolved" );
    if( active_world_mod( "aftershock_exoplanet" ) ) integration_names.push_back( "Aftershock Exoplanet" );
    if( active_world_mod( "aftershock_prime" ) ) integration_names.push_back( "Aftershock Prime" );
    if( active_world_mod( "secronom" ) ) integration_names.push_back( "Secronom" );
    if( active_world_mod( "secronom_lore_expansion" ) ) integration_names.push_back( "Secronom+" );
    if( integration_names.empty() ) {
        out += tr( "none", "нет" );
    } else {
        for( size_t i = 0; i < integration_names.size(); ++i ) {
            if( i != 0 ) out += ", ";
            out += integration_names[i];
        }
    }

    for( branch_id branch : { branch_id::combat, branch_id::survival, branch_id::mobility,
                              branch_id::crafting, branch_id::scavenging, branch_id::mastery } ) {
        const int64_t blevel = branch_level( branch );
        out += "\n" + branch_name( branch ) + ": L" +
               std::to_string( blevel ) + " XP " +
               std::to_string( branch_xp( branch ) ) + "/" +
               std::to_string( branch_xp_to_next( blevel ) ) + " | perks " +
               std::to_string( branch_owned_count( branch ) ) + "/" +
               std::to_string( branch_total_count( branch ) ) + " | " +
               branch_efficiency_text( branch );
    }

    out += "\n\n" + tr( "Active effects:", "Активные эффекты:" );
    const std::map<std::string, double> totals = owned_effect_totals();
    if( totals.empty() && current_xp_bonus_pct == 0 ) {
        out += "\n" + tr( "none", "нет" );
    } else {
        for( const auto &entry : totals ) {
            const std::string sign = entry.second > 0.0 ? "+" : "";
            out += "\n" + effect_label( entry.first ) + ": " + sign + format_number( entry.second );
        }
        if( current_xp_bonus_pct != 0 ) {
            out += "\n" + tr( "Survivor XP: +", "Опыт Survivor: +" ) +
                   std::to_string( current_xp_bonus_pct ) + "%";
        }
    }
    message( out );
}

void respec()
{
    int64_t refund_perk = 0;
    int64_t refund_major = 0;
    for( const perk_def &perk : perks ) {
        const int rank = perk_rank( perk );
        if( rank <= 0 ) {
            continue;
        }
        if( perk.currency == currency_id::perk ) {
            refund_perk += rank;
        } else {
            refund_major += rank;
        }
    }

    if( refund_perk == 0 && refund_major == 0 ) {
        message( tr( "No Survivor perks to reset.", "Нет перков Survivor для сброса." ) );
        return;
    }

    std::string title = tr(
        "Respec all Survivor perks?\nRefund: ",
        "Сбросить все перки Survivor?\nВозврат: " );
    title += std::to_string( refund_perk ) + "P / " + std::to_string( refund_major ) + "M";
    title += tr( "\nRanked perks refund every purchased rank.",
                 "\nМногоуровневые перки возвращают очко за каждый купленный ранг." );

    std::string yes = tr( "Respec", "Сбросить" );
    std::string no = tr( "Cancel", "Отмена" );
    const char *entries[] = { yes.c_str(), no.c_str() };
    const int choice = host->ui_choose ? host->ui_choose( title.c_str(), entries, 2 ) : -1;
    if( choice != 0 ) {
        return;
    }

    for( const perk_def &perk : perks ) {
        if( perk_rank( perk ) > 0 ) {
            set_state( perk_key( perk ), 0 );
        }
    }

    set_state( "perk_points", get_state( "perk_points", 0 ) + refund_perk );
    set_state( "major_points", get_state( "major_points", 0 ) + refund_major );
    set_state( "fast_learner", 0 );
    for( branch_id branch : all_branches ) {
        set_state( specialization_state_key( branch ), 0 );
    }
    effects_dirty = true;
    recalculate_effects();

    message( tr( "Survivor perks reset. Refunded: ", "Перки Survivor сброшены. Возвращено: " ) +
             std::to_string( refund_perk ) + "P / " + std::to_string( refund_major ) + "M" );
}

const char *integration_anchor_id( const std::string &mod_id )
{
    if( mod_id == "magiclysm" ) return "mg_arcane_focus";
    if( mod_id == "mindovermatter" ) return "mom_mental_focus";
    if( mod_id == "xedra_evolved" ) return "xe_anomaly_method";
    if( mod_id == "aftershock_exoplanet" ) return "af_systems_operator";
    if( mod_id == "aftershock_prime" ) return "afp_prime_operator";
    if( mod_id == "secronom" ) return "sec_field_researcher";
    if( mod_id == "secronom_lore_expansion" ) return "secx_flesh_initiate";
    return "";
}

std::string integration_mod_display_name( const std::string &mod_id )
{
    if( mod_id == "magiclysm" ) return "Magiclysm";
    if( mod_id == "mindovermatter" ) return "Mind Over Matter";
    if( mod_id == "xedra_evolved" ) return "Xedra Evolved";
    if( mod_id == "aftershock_exoplanet" ) return "Aftershock Exoplanet";
    if( mod_id == "aftershock_prime" ) return "Aftershock Prime";
    if( mod_id == "secronom" ) return "Secronom";
    if( mod_id == "secronom_lore_expansion" ) return "Secronom+";
    return mod_id;
}

std::string integration_mod_focus( const std::string &mod_id )
{
    if( mod_id == "magiclysm" ) return tr(
        "20-node arcane tree: Spellcraft, source-scoped spell economy, casting reliability, XP, potency/range/area/duration.",
        "20 узлов: Spellcraft, экономика заклинаний своего мода, надёжность, опыт, мощность/дальность/площадь/длительность." );
    if( mod_id == "mindovermatter" ) return tr(
        "20-node psionic tree: Metaphysics, stamina cost, reliability, power XP and psionic projection.",
        "20 узлов: Metaphysics, стоимость по выносливости, надёжность, опыт сил и псионическая проекция." );
    if( mod_id == "xedra_evolved" ) return tr(
        "20-node XEDRA tree: Deduction, Gramarye, source-scoped dream/spell economy and dimensional mechanics.",
        "20 узлов: Deduction, Gramarye, экономика сил своего мода и межпространственные механики." );
    if( mod_id == "aftershock_exoplanet" ) return tr(
        "20-node Aftershock Exoplanet tree: Smartgun, Metaphysics and stamina-powered esper mechanics.",
        "20 узлов Aftershock Exoplanet: Smartgun, Metaphysics и механики эспера, работающие от выносливости." );
    if( mod_id == "aftershock_prime" ) return tr(
        "20-node Prime tree: Smartgun plus Prime-sourced systems, translocation and utility-tech abilities; no Esper layer.",
        "20 узлов Prime: Smartgun, системные, трансляционные и утилитарные способности Prime; без слоя Esper." );
    if( mod_id == "secronom" ) return tr(
        "20-node Secronom hunter tree: damage resistance and counter-offense against Secronom species, elites and Crimson Horrors.",
        "20 узлов охотника Secronom: сопротивление и контратака против видов Secronom, элит и Crimson Horrors." );
    if( mod_id == "secronom_lore_expansion" ) return tr(
        "20-node Secronom+ tree: Flesh Weaving, Bio-organic Weapons and source-scoped Flesh Vessel abilities.",
        "20 узлов Secronom+: Flesh Weaving, Bio-organic Weapons и способности Flesh Vessel своего мода." );
    return {};
}

int integration_owned_count( const std::string &mod_id )
{
    int result = 0;
    for( const perk_def &perk : perks ) {
        if( integration_perk( perk ) && perk_world_available( perk ) &&
            mod_id == integration_mod_id( perk ) && owned( perk ) ) ++result;
    }
    return result;
}

int integration_total_count( const std::string &mod_id )
{
    int result = 0;
    for( const perk_def &perk : perks ) {
        if( integration_perk( perk ) && perk_world_available( perk ) &&
            mod_id == integration_mod_id( perk ) ) ++result;
    }
    return result;
}

std::pair<int, int> integration_tree_position( size_t i )
{
    static const std::array<std::pair<int, int>, 20> layout = {{
        { 0, 2 },
        { 2, 0 }, { 2, 2 }, { 2, 4 },
        { 4, 0 }, { 4, 2 }, { 4, 4 },
        { 6, 0 }, { 6, 2 }, { 6, 4 },
        { 8, 0 }, { 8, 2 }, { 8, 4 },
        { 10, 0 }, { 10, 2 }, { 10, 4 },
        { 12, 0 }, { 12, 2 }, { 12, 4 },
        { 14, 2 }
    }};
    return i < layout.size() ? layout[i] : std::make_pair( 16, static_cast<int>( i % 3 ) * 2 );
}

void show_integration_branch( const std::string &mod_id )
{
    if( !active_world_mod( mod_id.c_str() ) ) {
        message( tr( "This integration is not active in the current world.",
                     "Эта интеграция не активна в текущем мире." ) );
        return;
    }

    bool tree_mode = true;
    while( true ) {
        const int64_t survivor_level = std::max<int64_t>( 1, get_state( "level", 1 ) );
        const int64_t survivor_xp = std::max<int64_t>( 0, get_state( "xp", 0 ) );
        const int64_t survivor_next = xp_to_next( survivor_level );
        const int64_t perk_points = get_state( "perk_points", 0 );
        const int64_t major_points = get_state( "major_points", 0 );

        std::vector<const perk_def *> mod_perks;
        mod_perks.reserve( 20 );
        const char *anchor_id = integration_anchor_id( mod_id );
        const perk_def *anchor = find_perk( anchor_id );
        if( anchor != nullptr && integration_perk( *anchor ) && mod_id == integration_mod_id( *anchor ) ) {
            mod_perks.push_back( anchor );
        }
        for( const perk_def &perk : perks ) {
            if( !integration_perk( perk ) || !perk_world_available( perk ) ||
                mod_id != integration_mod_id( perk ) || &perk == anchor ) continue;
            mod_perks.push_back( &perk );
        }
        if( mod_perks.empty() ) {
            message( tr( "No integration perks are available for this mod.",
                         "Для этого мода нет доступных интеграционных перков." ) );
            return;
        }

        std::vector<card_text> texts;
        texts.reserve( mod_perks.size() );
        for( const perk_def *perk_ptr : mod_perks ) {
            const perk_def &perk = *perk_ptr;
            const int rank = perk_rank( perk );
            const int max_rank = perk_max_rank( perk );
            const bool maxed = rank >= max_rank;
            const bool unlocked = survivor_level >= perk.required_level && prerequisites_met( perk );
            const bool enough = perk.currency == currency_id::perk ? perk_points > 0 : major_points > 0;

            card_text card;
            card.id = perk.id;
            card.title = perk_display_name( perk );
            card.subtitle = tr( "Survivor L", "Survivor ур." ) + std::to_string( perk.required_level ) +
                            " | " + ( perk.currency == currency_id::perk ? "1P" : "1M" );
            card.body = perk_description( perk );
            card.badge = perk_kind_label( perk );
            const std::string chevrons = rank_chevrons( perk );
            if( !chevrons.empty() ) card.badge += " | " + chevrons;
            card.badge += " | ";
            if( maxed ) {
                card.badge += tr( "OWNED", "КУПЛЕНО" );
                card.flags |= NCMM_UI_CARD_OWNED;
            } else if( !unlocked ) {
                card.badge += tr( "LOCKED", "ЗАКРЫТО" );
                card.flags |= NCMM_UI_CARD_LOCKED;
            } else if( !enough ) {
                card.badge += tr( "NO POINTS", "НЕТ ОЧКОВ" );
            } else {
                card.badge += tr( "AVAILABLE", "ДОСТУПНО" );
            }
            if( perk.currency == currency_id::major ) card.flags |= NCMM_UI_CARD_MAJOR;
            card.flags |= NCMM_UI_CARD_EFFECT;
            card.icon_key = std::string( "survivor/mod/" ) + mod_id + "/" + perk.id;
            texts.push_back( std::move( card ) );
        }

        const std::string mod_name = integration_mod_display_name( mod_id );
        std::string title = "Survivor Progression > " + mod_name;
        std::string summary = tr( "Audited mod-native branch", "Ветка нативных механик мода" ) +
                              tr( " | purchased ", " | куплено " ) +
                              std::to_string( integration_owned_count( mod_id ) ) + "/" +
                              std::to_string( integration_total_count( mod_id ) ) +
                              " | P " + std::to_string( perk_points ) + " | M " + std::to_string( major_points ) +
                              tr( " | gated by Survivor level", " | требования по уровню Survivor" );
        std::string progress_label = "Survivor XP " + std::to_string( survivor_xp ) + "/" +
                                     std::to_string( survivor_next ) + tr( " -> L", " -> ур." ) +
                                     std::to_string( survivor_level + 1 );
        ncmm_ui_progress_v1 progress{ progress_label.c_str(), survivor_xp, survivor_next };

        if( tree_mode && host->ui_tree_choose ) {
            std::vector<tree_node_text> tree_texts;
            tree_texts.reserve( mod_perks.size() );
            std::map<std::string, size_t> index_by_id;
            for( size_t i = 0; i < mod_perks.size(); ++i ) {
                const perk_def &tree_perk = *mod_perks[i];
                tree_node_text node;
                node.card = texts[i];
                const int tree_rank = perk_rank( tree_perk );
                const int tree_max_rank = perk_max_rank( tree_perk );
                const bool tree_unlocked = survivor_level >= tree_perk.required_level &&
                                           prerequisites_met( tree_perk );
                node.card.subtitle = tr( "L", "ур." ) + std::to_string( tree_perk.required_level ) +
                                     " | " + ( tree_perk.currency == currency_id::perk ? "1P" : "1M" );
                if( tree_max_rank > 1 && tree_rank > 0 ) {
                    node.card.subtitle += " | R" + std::to_string( tree_rank ) + "/" +
                                          std::to_string( tree_max_rank );
                }
                node.card.badge = compact_tree_badge( tree_perk, tree_unlocked,
                                                       perk_points, major_points, true );
                node.card.body += "\n" + tr( "Prerequisites: ", "Требования: " ) +
                                  prereq_text( tree_perk );
                const std::pair<int, int> pos = integration_tree_position( i );
                node.row = pos.first;
                node.column = pos.second;
                index_by_id[mod_perks[i]->id] = i;
                tree_texts.push_back( std::move( node ) );
            }
            std::vector<ncmm_ui_tree_edge_v1> edges;
            auto add_edge = [&]( const char *prereq, size_t to ) {
                if( prereq == nullptr || prereq[0] == '\0' ) return;
                const auto it = index_by_id.find( prereq );
                if( it != index_by_id.end() ) edges.push_back( { it->second, to } );
            };
            for( size_t i = 0; i < mod_perks.size(); ++i ) {
                add_edge( mod_perks[i]->prereq1, i );
                add_edge( mod_perks[i]->prereq2, i );
            }
            std::vector<ncmm_ui_tree_node_v1> nodes = bind_tree_nodes( tree_texts );
            const ncmm_ui_theme_v1 theme = integration_ui_theme( mod_id );
            const int choice = host->ui_tree_choose_themed( title.c_str(), summary.c_str(), &progress,
                               nodes.data(), nodes.size(), edges.data(), edges.size(), &theme );
            if( choice == NCMM_UI_TREE_SHOW_CARDS ) { tree_mode = false; continue; }
            if( choice < 0 || static_cast<size_t>( choice ) >= mod_perks.size() ) return;
            show_perk_detail( *mod_perks[choice] );
            continue;
        }

        std::vector<ncmm_ui_card_v1> cards = bind_cards( texts );
        const ncmm_ui_theme_v1 theme = integration_ui_theme( mod_id );
        const int choice = host->ui_card_choose_themed ?
                           host->ui_card_choose_themed( title.c_str(), summary.c_str(), &progress,
                                                        cards.data(), cards.size(), 2, &theme ) : -1;
        if( choice == NCMM_UI_CARD_SHOW_TREE ) { tree_mode = true; continue; }
        if( choice < 0 || static_cast<size_t>( choice ) >= mod_perks.size() ) return;
        show_perk_detail( *mod_perks[choice] );
    }
}

void open_progression()
{
    if( !character_available() ) {
        message( tr( "Survivor Progression: load a character first.",
                     "Survivor Progression: сначала загрузите персонажа." ) );
        return;
    }

    migrate_state();
    if( effects_dirty ) {
        recalculate_effects();
    }

    while( true ) {
        const int64_t level = std::max<int64_t>( 1, get_state( "level", 1 ) );
        const int64_t xp = std::max<int64_t>( 0, get_state( "xp", 0 ) );
        const int64_t perk_points = get_state( "perk_points", 0 );
        const int64_t major_points = get_state( "major_points", 0 );

        const std::array<branch_id, 6> branches = {
            branch_id::combat, branch_id::survival, branch_id::mobility,
            branch_id::crafting, branch_id::scavenging, branch_id::mastery
        };

        std::vector<card_text> texts;
        texts.reserve( 16 );
        for( branch_id branch : branches ) {
            card_text card;
            card.id = branch_name_en( branch );
            card.title = branch_name( branch );
            const int64_t blevel = branch_level( branch );
            const int64_t bxp = branch_xp( branch );
            const int64_t bnext = branch_xp_to_next( blevel );
            card.subtitle =
                tr( "Branch L", "Ветка ур." ) + std::to_string( blevel ) +
                " | XP " + std::to_string( bxp ) + "/" + std::to_string( bnext ) +
                " | " + std::to_string( branch_owned_count( branch ) ) + "/" +
                std::to_string( branch_total_count( branch ) );
            card.body = branch_focus( branch ) + "\n" + branch_xp_source( branch ) +
                        "\n" + branch_efficiency_text( branch );
            card.badge = tr( "BRANCH", "ВЕТКА" );
            card.icon_key = branch_icon_key( branch );
            card.flags = NCMM_UI_CARD_ACCENT;
            texts.push_back( std::move( card ) );
        }

        std::vector<std::string> mod_branches;
        auto add_mod_branch = [&]( const char *mod_id ) {
            if( !active_world_mod( mod_id ) ) {
                return;
            }
            const std::string id = mod_id;
            mod_branches.push_back( id );

            card_text card;
            card.id = std::string( "mod_" ) + id;
            card.title = integration_mod_display_name( id );
            card.subtitle =
                tr( "Mod branch | ", "Ветка мода | " ) +
                std::to_string( integration_owned_count( id ) ) + "/" +
                std::to_string( integration_total_count( id ) );
            card.body = integration_mod_focus( id ) + "\n" +
                        tr( "Shown only while this mod is active in the current world.",
                            "Показывается только пока этот мод активен в текущем мире." );
            card.badge = tr( "MOD BRANCH", "ВЕТКА МОДА" );
            card.icon_key = std::string( "survivor/mod/" ) + id;
            card.flags = NCMM_UI_CARD_ACCENT;
            texts.push_back( std::move( card ) );
        };
        add_mod_branch( "magiclysm" );
        add_mod_branch( "mindovermatter" );
        add_mod_branch( "xedra_evolved" );
        add_mod_branch( "aftershock_exoplanet" );
        add_mod_branch( "aftershock_prime" );
        add_mod_branch( "secronom" );
        add_mod_branch( "secronom_lore_expansion" );

        const int overview_index = static_cast<int>( texts.size() );
        card_text overview;
        overview.id = "overview";
        overview.title = tr( "Overview", "Обзор" );
        overview.subtitle = tr( "Level / points / active effects", "Уровень / очки / активные эффекты" );
        overview.body = tr( "Inspect the complete Survivor state.",
                            "Полное состояние прогрессии Survivor." );
        overview.badge = tr( "INFO", "ИНФО" );
        overview.icon_key = "survivor/action/overview";
        texts.push_back( std::move( overview ) );

        const int respec_index = static_cast<int>( texts.size() );
        card_text reset;
        reset.id = "respec";
        reset.title = tr( "Respec", "Сброс перков" );
        reset.subtitle = tr( "Refund every purchase", "Вернуть все покупки" );
        reset.body = tr( "Refund perk and major points and clear Survivor modifiers.",
                         "Вернуть очки и снять модификаторы Survivor." );
        reset.badge = tr( "ACTION", "ДЕЙСТВИЕ" );
        reset.icon_key = "survivor/action/respec";
        texts.push_back( std::move( reset ) );

        const int close_index = static_cast<int>( texts.size() );
        card_text close;
        close.id = "close";
        close.title = tr( "Close", "Закрыть" );
        close.subtitle = tr( "Return to game", "Вернуться в игру" );
        close.body = tr( "Keep your build and continue playing.",
                         "Сохранить билд и вернуться в игру." );
        close.badge = tr( "ACTION", "ДЕЙСТВИЕ" );
        close.icon_key = "survivor/action/close";
        texts.push_back( std::move( close ) );

        const int total_owned = owned_count( currency_id::perk ) +
                                owned_count( currency_id::major );
        const int total_perks = visible_perk_count();

        std::string title = "Survivor Progression v0.9.14";
        std::string summary =
            tr( "Level ", "Уровень " ) + std::to_string( level ) +
            " | P " + std::to_string( perk_points ) +
            " | M " + std::to_string( major_points ) +
            tr( " | purchased ", " | куплено " ) +
            std::to_string( total_owned ) + "/" + std::to_string( total_perks );
        if( !mod_branches.empty() ) {
            summary += tr( " | mod branches ", " | ветки модов " ) +
                       std::to_string( mod_branches.size() );
        }

        const int64_t xp_needed = xp_to_next( level );
        std::string progress_label =
            "XP " + std::to_string( xp ) + "/" + std::to_string( xp_needed ) +
            tr( " -> Level ", " -> Уровень " ) + std::to_string( level + 1 );
        ncmm_ui_progress_v1 progress{ progress_label.c_str(), xp, xp_needed };

        std::vector<ncmm_ui_card_v1> cards = bind_cards( texts );
        std::vector<uint32_t> item_accents;
        item_accents.reserve( cards.size() );
        for( branch_id branch : branches ) {
            item_accents.push_back( branch_theme_color( branch ) );
        }
        for( const std::string &mod_id : mod_branches ) {
            item_accents.push_back( integration_theme_color( mod_id ) );
        }
        while( item_accents.size() < cards.size() ) {
            item_accents.push_back( NCMM_UI_COLOR_DEFAULT );
        }
        const ncmm_ui_theme_v1 overview_theme{
            NCMM_UI_COLOR_DEFAULT, NCMM_UI_THEME_STRONG_BORDER, 0, 0,
            item_accents.data(), item_accents.size()
        };
        const int choice = host->ui_card_choose_themed ?
                           host->ui_card_choose_themed( title.c_str(), summary.c_str(), &progress,
                                                        cards.data(), cards.size(), 3, &overview_theme ) :
                           -1;

        if( choice >= 0 && choice < static_cast<int>( branches.size() ) ) {
            show_branch( branches[static_cast<size_t>( choice )] );
            continue;
        }

        const int mod_offset = static_cast<int>( branches.size() );
        const int mod_end = mod_offset + static_cast<int>( mod_branches.size() );
        if( choice >= mod_offset && choice < mod_end ) {
            show_integration_branch( mod_branches[static_cast<size_t>( choice - mod_offset )] );
            continue;
        }
        if( choice == overview_index ) {
            show_overview();
            continue;
        }
        if( choice == respec_index ) {
            respec();
            continue;
        }
        if( choice == close_index || choice < 0 ) {
            return;
        }
    }
}

void award_global_xp( int64_t raw_gained )
{
    if( raw_gained <= 0 || !character_available() ) {
        return;
    }

    int64_t fraction = get_state( "xp_fraction", 0 );
    const int64_t multiplier = std::max<int64_t>( 0, 100 + current_xp_bonus_pct );
    if( raw_gained > ( std::numeric_limits<int64_t>::max() - fraction ) /
        std::max<int64_t>( 1, multiplier ) ) {
        raw_gained = ( std::numeric_limits<int64_t>::max() - fraction ) /
                     std::max<int64_t>( 1, multiplier );
    }
    fraction += raw_gained * multiplier;
    int64_t gained = fraction / 100;
    fraction %= 100;
    set_state( "xp_fraction", fraction );
    if( gained <= 0 ) {
        return;
    }

    int64_t level = std::max<int64_t>( 1, get_state( "level", 1 ) );
    int64_t xp = std::max<int64_t>( 0, get_state( "xp", 0 ) ) + gained;
    int64_t perk_points = get_state( "perk_points", 0 );
    int64_t major_points = get_state( "major_points", 0 );
    int64_t major_awarded = get_state( "major_awarded", 0 );
    int64_t levels_gained = 0;
    int64_t majors_gained = 0;

    while( xp >= xp_to_next( level ) && level < std::numeric_limits<int64_t>::max() ) {
        xp -= xp_to_next( level );
        ++level;
        ++perk_points;
        ++levels_gained;
        if( level % 5 == 0 ) {
            ++major_points;
            ++major_awarded;
            ++majors_gained;
        }
    }

    set_state( "level", level );
    set_state( "xp", xp );
    set_state( "perk_points", perk_points );
    set_state( "major_points", major_points );
    set_state( "major_awarded", major_awarded );

    if( levels_gained > 0 ) {
        std::string text = tr( "Survivor level up! +", "Новый уровень Survivor! +" ) +
                           std::to_string( levels_gained ) +
                           tr( " perk point(s).", " очк. перков." );
        if( majors_gained > 0 ) {
            text += tr( " +", " +" ) + std::to_string( majors_gained ) +
                    tr( " major point(s).", " больших очк." );
        }
        message( text );
    }
}

int64_t award_branch_xp( branch_id branch, int64_t raw_gained )
{
    const int64_t gained = anti_farm_adjust( branch, raw_gained );
    if( gained <= 0 ) {
        return 0;
    }

    const int64_t old_level = branch_level( branch );
    int64_t level = old_level;
    int64_t xp = branch_xp( branch ) + gained;
    while( xp >= branch_xp_to_next( level ) &&
           level < std::numeric_limits<int64_t>::max() ) {
        xp -= branch_xp_to_next( level );
        ++level;
    }
    set_state( branch_state_key( branch, "level" ), level );
    set_state( branch_state_key( branch, "xp" ), xp );

    // Only post-anti-farm branch XP reaches the global Survivor level.
    award_global_xp( gained );

    if( level > old_level ) {
        message( branch_name( branch ) + tr( " branch level up: ", " — новый уровень ветки: " ) +
                 std::to_string( level ) );
    }
    return gained;
}

int64_t metric_now( const char *metric )
{
    return host && host->gameplay_metric_get_i64 ?
           std::max<int64_t>( 0, host->gameplay_metric_get_i64( metric ) ) : 0;
}

void prime_metric_baselines()
{
    const std::array<std::pair<const char *, const char *>, 7> metrics = {{
        { "combat.kills", "metric_combat_kills" },
        { "combat.kill_xp", "metric_combat_kill_xp" },
        { "survival.healing", "metric_survival_healing" },
        { "mobility.steps", "metric_mobility_steps" },
        { "crafting.completed", "metric_crafting_completed" },
        { "scavenging.omt", "metric_scavenging_omt" },
        { "mastery.skill_levels", "metric_mastery_skill_levels" }
    }};
    for( const auto &entry : metrics ) {
        set_state( entry.second, metric_now( entry.first ) );
    }
}

int64_t metric_delta( const char *metric, const char *baseline_key )
{
    const int64_t now = metric_now( metric );
    const int64_t before = get_state( baseline_key, -1 );
    set_state( baseline_key, now );
    if( before < 0 || now < before ) {
        return 0;
    }
    return now - before;
}

int activity_diversity_bonus_pct( int active_branches )
{
    if( active_branches >= 4 ) return 15;
    if( active_branches == 3 ) return 10;
    if( active_branches == 2 ) return 5;
    return 0;
}

int64_t apply_activity_diversity_bonus( branch_id branch, int64_t raw, int bonus_pct )
{
    if( raw <= 0 || bonus_pct <= 0 ) {
        return raw;
    }
    const std::string key = branch_state_key( branch, "diversity_fraction" );
    int64_t scaled = raw * ( 100 + bonus_pct ) +
                     std::max<int64_t>( 0, get_state( key, 0 ) );
    const int64_t result = scaled / 100;
    set_state( key, scaled % 100 );
    return result;
}

int integration_branch_xp_bonus_pct( branch_id branch )
{
    int bonus = 0;
    if( active_world_mod( "magiclysm" ) &&
        ( branch == branch_id::crafting || branch == branch_id::mastery ) ) bonus += 10;
    if( active_world_mod( "mindovermatter" ) &&
        ( branch == branch_id::mobility || branch == branch_id::mastery ) ) bonus += 10;
    if( active_world_mod( "xedra_evolved" ) &&
        ( branch == branch_id::scavenging || branch == branch_id::mastery ) ) bonus += 10;
    if( active_world_mod( "aftershock_exoplanet" ) &&
        ( branch == branch_id::crafting || branch == branch_id::scavenging ) ) bonus += 10;
    return std::min( bonus, 20 );
}

int64_t scale_activity_xp( branch_id branch, int64_t raw, int diversity_bonus_pct )
{
    if( raw <= 0 ) return 0;
    const int total_bonus = diversity_bonus_pct + integration_branch_xp_bonus_pct( branch );
    if( total_bonus <= 0 ) return raw;
    const std::string key = branch_state_key( branch, "activity_bonus_fraction" );
    int64_t scaled = raw * ( 100 + total_bonus ) +
                     std::max<int64_t>( 0, get_state( key, 0 ) );
    const int64_t result = scaled / 100;
    set_state( key, scaled % 100 );
    return result;
}

void poll_branch_xp()
{
    decay_branch_fatigue();

    const int64_t kills = metric_delta( "combat.kills", "metric_combat_kills" );
    const int64_t kill_xp = metric_delta( "combat.kill_xp", "metric_combat_kill_xp" );
    int64_t combat_gain = std::min<int64_t>( std::max<int64_t>( kills, ( kill_xp + 49 ) / 50 ), 25 );

    int64_t healing = metric_delta( "survival.healing", "metric_survival_healing" );
    healing += get_state( "survival_heal_remainder", 0 );
    int64_t survival_gain = std::min<int64_t>( healing / 10, 8 );
    set_state( "survival_heal_remainder", healing % 10 );

    int64_t steps = metric_delta( "mobility.steps", "metric_mobility_steps" );
    steps += get_state( "mobility_step_remainder", 0 );
    int64_t mobility_gain = std::min<int64_t>( steps / 150, 3 );
    set_state( "mobility_step_remainder", steps % 150 );

    const int64_t crafts = metric_delta( "crafting.completed", "metric_crafting_completed" );
    int64_t crafting_gain = std::min<int64_t>( crafts * 3, 12 );
    const int64_t omts = metric_delta( "scavenging.omt", "metric_scavenging_omt" );
    int64_t scavenging_gain = std::min<int64_t>( omts * 4, 8 );
    const int64_t skill_levels = metric_delta( "mastery.skill_levels", "metric_mastery_skill_levels" );
    int64_t mastery_gain = std::min<int64_t>( skill_levels * 6, 18 );

    int active = 0;
    active += combat_gain > 0 ? 1 : 0;
    active += survival_gain > 0 ? 1 : 0;
    active += mobility_gain > 0 ? 1 : 0;
    active += crafting_gain > 0 ? 1 : 0;
    active += scavenging_gain > 0 ? 1 : 0;
    const int diversity_bonus = activity_diversity_bonus_pct( active );

    combat_gain = scale_activity_xp( branch_id::combat, combat_gain, diversity_bonus );
    survival_gain = scale_activity_xp( branch_id::survival, survival_gain, diversity_bonus );
    mobility_gain = scale_activity_xp( branch_id::mobility, mobility_gain, diversity_bonus );
    crafting_gain = scale_activity_xp( branch_id::crafting, crafting_gain, diversity_bonus );
    scavenging_gain = scale_activity_xp( branch_id::scavenging, scavenging_gain, diversity_bonus );
    mastery_gain = scale_activity_xp( branch_id::mastery, mastery_gain, 0 );

    int64_t activity_total = 0;
    activity_total += award_branch_xp( branch_id::combat, combat_gain );
    activity_total += award_branch_xp( branch_id::survival, survival_gain );
    activity_total += award_branch_xp( branch_id::mobility, mobility_gain );
    activity_total += award_branch_xp( branch_id::crafting, crafting_gain );
    activity_total += award_branch_xp( branch_id::scavenging, scavenging_gain );

    int64_t mastery_fraction = get_state( "mastery_share_fraction", 0 );
    mastery_fraction += activity_total * 10;
    mastery_gain += mastery_fraction / 100;
    mastery_fraction %= 100;
    set_state( "mastery_share_fraction", mastery_fraction );
    award_branch_xp( branch_id::mastery, mastery_gain );
}

void tick()
{
    const bool available = character_available();
    if( !available ) {
        if( last_character_available ) {
            clear_runtime_modifiers();
            effects_dirty = true;
        }
        last_character_available = false;
        turn_accumulator = 0;
        return;
    }

    if( !last_character_available ) {
        last_character_available = true;
        migrate_state();
        prime_metric_baselines();
        effects_dirty = true;
    }
    if( effects_dirty ) {
        recalculate_effects();
    }

    ++turn_accumulator;
    if( turn_accumulator < 60 ) {
        return;
    }
    turn_accumulator -= 60;
    poll_branch_xp();
}
int init( const ncmm_host_api_v1 *api )
{
    if( api == nullptr || api->abi_version != NCMM_ABI_VERSION ) {
        return 0;
    }
    if( !api->get_api_version_major || !api->get_api_version_minor ||
        api->get_api_version_major() != NCMM_API_VERSION_MAJOR ||
        api->get_api_version_minor() < NCMM_API_VERSION_MINOR ) {
        return 0;
    }
    for( const char *capability : required_caps ) {
        if( !api->has_capability || !api->has_capability( capability ) ) {
            return 0;
        }
    }
    if( !api->character_state_available || !api->character_state_get_i64 ||
        !api->character_state_set_i64 || !api->character_modifier_set ||
        !api->character_modifier_clear_module || !api->ui_choose || !api->ui_tile_choose ||
        !api->ui_card_choose || !api->ui_tree_choose ||
        !api->gameplay_metric_get_i64 || !api->world_mod_active || !api->ui_card_choose_themed || !api->ui_tree_choose_themed || !api->ui_message ) {
        return 0;
    }

    host = api;
    api->log( NCMM_LOG_INFO,
              "Survivor Progression 0.9.14 initialized: branch bars / exclusive specializations / conditional deep mod integrations." );
    return 1;
}

void shutdown()
{
    clear_runtime_modifiers();
    host = nullptr;
    turn_accumulator = 0;
    last_character_available = false;
    effects_dirty = true;
    current_xp_bonus_pct = 0;
}

const ncmm_mod_descriptor_v1 descriptor = {
    NCMM_ABI_VERSION,
    module_id,
    "Survivor Progression",
    "0.9.14",
    required_caps,
    sizeof( required_caps ) / sizeof( required_caps[0] ),
    &init,
    &shutdown
};
} // namespace

extern "C" NCMM_EXPORT const ncmm_mod_descriptor_v1 *ncmm_get_descriptor_v1()
{
    return &descriptor;
}

extern "C" NCMM_EXPORT int ncmm_migrate_state_v1( const ncmm_host_api_v1 *api,
        uint32_t from_schema, uint32_t to_schema )
{
    if( api == nullptr || to_schema != static_cast<uint32_t>( state_schema ) ||
        from_schema > to_schema ) {
        return 0;
    }
    host = api;
    migrate_state();
    return get_state( "schema", 0 ) == state_schema ? 1 : 0;
}

extern "C" NCMM_EXPORT void ncmm_on_turn_v1( const ncmm_host_api_v1 *api )
{
    if( api != nullptr ) {
        host = api;
    }
    tick();
}

extern "C" NCMM_EXPORT void ncmm_open_ui_v1( const ncmm_host_api_v1 *api )
{
    if( api != nullptr ) {
        host = api;
    }
    open_progression();
}
