#define NCMM_MOD_BUILD
#include "ncmm_api.h"

#include <cstddef>
#include <string>

namespace
{
const char *required_caps[] = {
    "core.v1",
    "world_options.v1",
    "world_options.layout.v1",
    "locale.v1",
    "module_contract.v1"
};

struct option_desc {
    const char *id;
    const char *name;
    const char *tooltip;
};

const option_desc options_en[] = {
    { "SPAWN_DENSITY", "Monster spawn density",
      "Multiplier for monster spawn density. 1.00 is the vanilla default." },
    { "ITEM_SPAWNRATE", "Item spawn rate",
      "Multiplier for generated item quantity. 1.00 is the vanilla default." },
    { "MONSTER_SPEED", "Monster speed",
      "Global monster speed percentage. 100% is the vanilla default." },
    { "MONSTER_RESILIENCE", "Monster resilience",
      "Global monster health percentage. 100% is the vanilla default." },
    { "EVOLUTION_INVERSE_MULTIPLIER", "Monster evolution time multiplier",
      "Multiplier applied to monster evolution time. Higher values slow evolution; 0 disables upgrades where supported." },

    { "SEASON_LENGTH", "Season length (days)",
      "EXPERIMENTAL. Number of days in each season. CDDA default is 91. Reload the world after changing this so calendar caches are rebuilt." },
    { "CONSTRUCTION_SCALING", "Construction time scaling",
      "EXPERIMENTAL. Percentage of base construction time. 100% is normal, 50% is twice as fast, and 0 scales automatically with season length." },
    { "ETERNAL_SEASON", "Eternal season",
      "EXPERIMENTAL. Stops normal season progression. Reload the world after changing this so calendar caches are rebuilt." },
    { "ETERNAL_TIME_OF_DAY", "Fixed time of day",
      "EXPERIMENTAL. Fixes the world to normal time flow, permanent day, or permanent night. Reload the world after changing this." }
};

const option_desc options_ru[] = {
    { "SPAWN_DENSITY", "Плотность появления монстров",
      "Множитель плотности появления монстров. 1,00 — стандартное значение игры." },
    { "ITEM_SPAWNRATE", "Количество генерируемых предметов",
      "Множитель количества генерируемых предметов. 1,00 — стандартное значение игры." },
    { "MONSTER_SPEED", "Скорость монстров",
      "Глобальная скорость монстров в процентах. 100% — стандартное значение игры." },
    { "MONSTER_RESILIENCE", "Живучесть монстров",
      "Глобальный запас здоровья монстров в процентах. 100% — стандартное значение игры." },
    { "EVOLUTION_INVERSE_MULTIPLIER", "Множитель времени эволюции монстров",
      "Множитель времени эволюции монстров. Большие значения замедляют эволюцию; 0 отключает улучшения там, где это поддерживается." },

    { "SEASON_LENGTH", "Длина сезона (дни)",
      "ЭКСПЕРИМЕНТАЛЬНО. Количество дней в каждом сезоне. Стандарт CDDA — 91. После изменения перезагрузите мир, чтобы обновились календарные кэши." },
    { "CONSTRUCTION_SCALING", "Масштаб времени строительства",
      "ЭКСПЕРИМЕНТАЛЬНО. Процент от базового времени строительства. 100% — стандарт, 50% — вдвое быстрее, 0 — автоматическое масштабирование по длине сезона." },
    { "ETERNAL_SEASON", "Вечный сезон",
      "ЭКСПЕРИМЕНТАЛЬНО. Останавливает обычную смену сезонов. После изменения перезагрузите мир, чтобы обновились календарные кэши." },
    { "ETERNAL_TIME_OF_DAY", "Фиксированное время суток",
      "ЭКСПЕРИМЕНТАЛЬНО. Обычный цикл, постоянный день или постоянная ночь. После изменения перезагрузите мир." }
};

bool russian( const ncmm_host_api_v1 *api )
{
    const char *raw = api && api->get_locale ? api->get_locale() : "en";
    const std::string locale = raw ? raw : "en";
    return locale == "ru" || locale.rfind( "ru_", 0 ) == 0;
}

const option_desc *localized_options( const ncmm_host_api_v1 *api )
{
    return russian( api ) ? options_ru : options_en;
}

bool expose_range( const ncmm_host_api_v1 *api, const option_desc *options,
                   std::size_t begin, std::size_t end,
                   const char *group_id, const char *group_name, const char *group_tooltip )
{
    if( !api->worldgen_group_begin( group_id, group_name, group_tooltip ) ) {
        return false;
    }

    bool ok = true;
    for( std::size_t i = begin; i < end; ++i ) {
        if( !api->expose_worldgen_option( options[i].id, options[i].name, options[i].tooltip ) ) {
            ok = false;
            break;
        }
    }
    api->worldgen_group_end();
    return ok;
}

int expose_all( const ncmm_host_api_v1 *api, bool log_errors )
{
    if( api == nullptr || api->abi_version != NCMM_ABI_VERSION ||
        api->can_expose_worldgen_option == nullptr || api->expose_worldgen_option == nullptr ||
        api->worldgen_group_begin == nullptr || api->worldgen_group_end == nullptr ||
        api->worldgen_set_string_choices == nullptr ) {
        return 0;
    }

    const option_desc *options = localized_options( api );
    const std::size_t count = sizeof( options_en ) / sizeof( options_en[0] );

    for( std::size_t i = 0; i < count; ++i ) {
        if( !api->can_expose_worldgen_option( options[i].id ) ) {
            if( log_errors ) {
                api->log( NCMM_LOG_ERROR, "AWS: preflight failed; no world options were exposed." );
            }
            return 0;
        }
    }

    const char *time_ids[] = { "normal", "day", "night" };
    const char *time_names_en[] = { "Normal", "Day", "Night" };
    const char *time_names_ru[] = { "Обычное", "День", "Ночь" };
    const char *const *time_names = russian( api ) ? time_names_ru : time_names_en;
    if( !api->worldgen_set_string_choices( "ETERNAL_TIME_OF_DAY", time_ids, time_names, 3 ) ) {
        if( log_errors ) {
            api->log( NCMM_LOG_ERROR, "AWS: could not configure the fixed-time selector." );
        }
        return 0;
    }

    const bool ru = russian( api );
    if( !expose_range(
            api, options, 0, 5,
            "aws_advanced",
            ru ? "Расширенные настройки мира" : "Advanced world settings",
            ru ? "Расширенные параметры сложности и генерации мира."
               : "Advanced world difficulty and generation controls." ) ) {
        if( log_errors ) {
            api->log( NCMM_LOG_ERROR, "AWS: advanced group exposure failed." );
        }
        return 0;
    }

    if( !expose_range(
            api, options, 5, count,
            "aws_experimental",
            ru ? "[ЭКСПЕРИМЕНТАЛЬНО] Дополнительные параметры"
               : "[EXPERIMENTAL] Additional world controls",
            ru ? "Скрытые внутренние параметры CDDA. Они могут заметно менять баланс и поведение мира; параметры календаря требуют перезагрузки мира."
               : "Hidden internal CDDA controls. They can substantially change balance/world behavior; calendar controls require a world reload." ) ) {
        if( log_errors ) {
            api->log( NCMM_LOG_ERROR, "AWS: experimental group exposure failed." );
        }
        return 0;
    }

    return 1;
}

int init( const ncmm_host_api_v1 *api )
{
    if( api == nullptr || api->abi_version != NCMM_ABI_VERSION ) {
        return 0;
    }
    for( const char *capability : required_caps ) {
        if( !api->has_capability || !api->has_capability( capability ) ) {
            return 0;
        }
    }
    if( !expose_all( api, true ) ) {
        return 0;
    }

    api->log( NCMM_LOG_INFO, "Advanced World Settings 0.5 initialized: grouped experimental controls active." );
    return 1;
}

void shutdown()
{
}

const ncmm_mod_descriptor_v1 descriptor = {
    NCMM_ABI_VERSION,
    "advanced_world_settings",
    "Advanced World Settings",
    "0.5.0",
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

extern "C" NCMM_EXPORT void ncmm_on_locale_changed_v1( const ncmm_host_api_v1 *api )
{
    expose_all( api, false );
}
