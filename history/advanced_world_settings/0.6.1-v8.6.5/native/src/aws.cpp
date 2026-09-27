#define NCMM_MOD_BUILD
#include "ncmm_api.h"

#include <cstddef>
#include <string>

namespace
{
constexpr const char *module_id = "advanced_world_settings";
const char *required_caps[] = {
    "core.v1", "world_options.v1", "world_options.layout.v1", "world_settings.v2",
    "world_options.experimental.v1", "locale.v1", "module_contract.v1", "api.versioning.v1"
};

struct option_desc {
    const char *id;
    const char *name;
    const char *tooltip;
};

const option_desc options_en[] = {
    { "SPAWN_DENSITY", "Monster spawn density", "Multiplier for monster spawn density. 1.00 is the vanilla default." },
    { "ITEM_SPAWNRATE", "Item spawn rate", "Multiplier for generated item quantity. 1.00 is the vanilla default." },
    { "MONSTER_SPEED", "Monster speed", "Global monster speed percentage. 100% is the vanilla default." },
    { "MONSTER_RESILIENCE", "Monster resilience", "Global monster health percentage. 100% is the vanilla default." },
    { "EVOLUTION_INVERSE_MULTIPLIER", "Monster evolution time multiplier", "Higher values slow evolution; 0 disables upgrades where supported." },
    { "SEASON_LENGTH", "Season length (days)", "[RELOAD] Number of days in each season. CDDA default is 91." },
    { "CONSTRUCTION_SCALING", "Construction time scaling", "Percentage of base construction time. 100% is normal; 50% is twice as fast." },
    { "ETERNAL_SEASON", "Eternal season", "[RELOAD] Stops normal season progression." },
    { "ETERNAL_TIME_OF_DAY", "Fixed time of day", "[RELOAD] Normal time flow, permanent day, or permanent night." }
};
const option_desc options_ru[] = {
    { "SPAWN_DENSITY", "Плотность монстров", "Множитель плотности появления монстров. 1,00 — стандарт." },
    { "ITEM_SPAWNRATE", "Количество предметов", "Множитель количества генерируемых предметов. 1,00 — стандарт." },
    { "MONSTER_SPEED", "Скорость монстров", "Глобальная скорость монстров в процентах. 100% — стандарт." },
    { "MONSTER_RESILIENCE", "Живучесть монстров", "Глобальный запас здоровья монстров в процентах. 100% — стандарт." },
    { "EVOLUTION_INVERSE_MULTIPLIER", "Время эволюции монстров", "Большие значения замедляют эволюцию; 0 отключает улучшения там, где это поддерживается." },
    { "SEASON_LENGTH", "Длина сезона (дни)", "[ПЕРЕЗАГРУЗКА] Количество дней в сезоне. Стандарт CDDA — 91." },
    { "CONSTRUCTION_SCALING", "Время строительства", "Процент от базового времени. 100% — стандарт; 50% — вдвое быстрее." },
    { "ETERNAL_SEASON", "Вечный сезон", "[ПЕРЕЗАГРУЗКА] Останавливает обычную смену сезонов." },
    { "ETERNAL_TIME_OF_DAY", "Фиксированное время суток", "[ПЕРЕЗАГРУЗКА] Обычный цикл, постоянный день или постоянная ночь." }
};

bool russian( const ncmm_host_api_v1 *api ) {
    const char *raw = api && api->get_locale ? api->get_locale() : "en";
    const std::string locale = raw ? raw : "en";
    return locale == "ru" || locale.rfind( "ru_", 0 ) == 0;
}
const char *tr( bool ru, const char *en, const char *ru_text ) { return ru ? ru_text : en; }

bool expose_range( const ncmm_host_api_v1 *api, const option_desc *options, std::size_t begin,
                   std::size_t end, const char *group_id, const char *group_name,
                   const char *group_tooltip ) {
    if( !api->worldgen_group_begin( group_id, group_name, group_tooltip ) ) return false;
    bool ok = true;
    for( std::size_t i = begin; i < end; ++i ) {
        if( !api->expose_worldgen_option( options[i].id, options[i].name, options[i].tooltip ) ) {
            ok = false; break;
        }
    }
    api->worldgen_group_end();
    return ok;
}

bool reg_bool( const ncmm_host_api_v1 *api, bool ru, const char *id, const char *en,
               const char *ru_name, const char *en_tip, const char *ru_tip, bool def ) {
    return api->world_setting_register_bool( module_id, id, tr( ru, en, ru_name ),
            tr( ru, en_tip, ru_tip ), def ? 1 : 0, NCMM_WORLD_SETTING_NEW_MAP ) != 0;
}
bool reg_int( const ncmm_host_api_v1 *api, bool ru, const char *id, const char *en,
              const char *ru_name, const char *en_tip, const char *ru_tip,
              int minv, int maxv, int def ) {
    return api->world_setting_register_int( module_id, id, tr( ru, en, ru_name ),
            tr( ru, en_tip, ru_tip ), minv, maxv, def, NCMM_WORLD_SETTING_NEW_MAP ) != 0;
}
bool reg_float( const ncmm_host_api_v1 *api, bool ru, const char *id, const char *en,
                const char *ru_name, const char *en_tip, const char *ru_tip,
                double minv, double maxv, double def, double step ) {
    return api->world_setting_register_float( module_id, id, tr( ru, en, ru_name ),
            tr( ru, en_tip, ru_tip ), minv, maxv, def, step, NCMM_WORLD_SETTING_NEW_MAP ) != 0;
}

bool geography( const ncmm_host_api_v1 *api, bool ru ) {
    bool ok = true;
    auto begin = [&]( const char *id, const char *en, const char *ru_name, const char *en_tip, const char *ru_tip ) {
        return api->worldgen_experimental_group_begin( id, tr( ru, en, ru_name ),
                tr( ru, en_tip, ru_tip ) ) != 0;
    };
    auto end = [&]() { api->worldgen_group_end(); };

    if( !begin( "aws_geo_city", "Cities and infrastructure", "Города и инфраструктура",
                "[NEW MAP] Affects only overmaps generated after the change.",
                "[НОВАЯ КАРТА] Влияет только на овермапы, созданные после изменения." ) ) return false;
    ok &= reg_bool( api,ru,"NCMM_AWS_CUSTOM_GEOGRAPHY","Use custom geography","Использовать свою географию","OFF preserves the active region/mod geography exactly. Turn ON to apply the controls below to newly generated default-region overmaps.","ВЫКЛ сохраняет географию активного региона/модов без изменений. Включите, чтобы применять параметры ниже к новым овермапам стандартного региона.",false );
    ok &= reg_int( api,ru,"NCMM_AWS_CITY_SIZE","Base city size","Базовый размер города","0 disables random cities; vanilla 8.","0 отключает случайные города; стандарт 8.",0,32,8 );
    ok &= reg_int( api,ru,"NCMM_AWS_CITY_SPACING","City spacing","Расстояние между городами","Higher values produce fewer cities; vanilla 4.","Чем выше значение, тем реже города; стандарт 4.",0,8,4 );
    ok &= reg_int( api,ru,"NCMM_AWS_MAX_URBANITY","Maximum urbanity multiplier","Максимальная урбанизация","Caps regional city-size amplification; vanilla 8.","Ограничивает региональное увеличение городов; стандарт 8.",1,16,8 );
    ok &= reg_bool( api,ru,"NCMM_AWS_MEGACITY","Megacity generation","Мегаполис","Uses CDDA megacity placement for newly generated overmaps. Very dense and heavier to generate.","Использует режим мегаполиса CDDA для новых овермапов. Очень плотная и более тяжёлая генерация.",false );
    ok &= reg_int( api,ru,"NCMM_AWS_SHOP_RADIUS","Shop radius","Радиус магазинов","Controls how far shop candidates extend from the city center; larger values generally produce shops across more of the city. 0 effectively disables shop selection through this radius check. CDDA 0546 default is 30.","Управляет тем, насколько далеко от центра города могут выбираться магазины; большие значения обычно распространяют магазины на большую часть города. 0 фактически отключает выбор магазинов через эту проверку радиуса. Стандарт CDDA 0546 — 30.",0,200,30 );
    ok &= reg_int( api,ru,"NCMM_AWS_SHOP_SIGMA","Shop distribution sigma","Разброс магазинов","Random spread for shop radius. CDDA 0546 default is 50.","Случайный разброс радиуса магазинов. Стандарт CDDA 0546 — 50.",0,200,50 );
    ok &= reg_int( api,ru,"NCMM_AWS_PARK_RADIUS","Park radius","Радиус парков","Controls how far park candidates extend from the city center; larger values generally produce parks across more of the city. 0 effectively disables park selection through this radius check. CDDA 0546 default is 20.","Управляет тем, насколько далеко от центра города могут выбираться парки; большие значения обычно распространяют парки на большую часть города. 0 фактически отключает выбор парков через эту проверку радиуса. Стандарт CDDA 0546 — 20.",0,200,20 );
    ok &= reg_int( api,ru,"NCMM_AWS_PARK_SIGMA","Park distribution sigma","Разброс парков","Random spread for park radius. CDDA 0546 default is 80.","Случайный разброс радиуса парков. Стандарт CDDA 0546 — 80.",0,200,80 );
    ok &= reg_bool( api,ru,"NCMM_AWS_PLACE_ROADS","Generate roads","Генерировать дороги","Disables new inter-city roads when off.","Отключает новые межгородские дороги.",true );
    ok &= reg_bool( api,ru,"NCMM_AWS_PLACE_RAILROADS","Generate railroads","Генерировать железные дороги","Disables new railroads when off.","Отключает новые железные дороги.",true );
    ok &= reg_bool( api,ru,"NCMM_AWS_PLACE_SPECIALS","Generate overmap specials","Генерировать особые локации","Controls placement of new overmap specials.","Управляет размещением новых особых локаций.",true );
    ok &= reg_bool( api,ru,"NCMM_AWS_NEIGHBOR_CONNECTIONS","Connect neighboring overmaps","Связывать соседние овермапы","Keeps roads/rails/rivers continuous across overmap borders.","Сохраняет непрерывность дорог, рельсов и рек между овермапами.",true );
    end(); if( !ok ) return false;

    if( !begin( "aws_geo_forest", "Forests, swamps and trails", "Леса, болота и тропы",
                "[NEW MAP] Lower noise thresholds create more of that terrain.",
                "[НОВАЯ КАРТА] Чем ниже порог шума, тем больше соответствующего ландшафта." ) ) return false;
    ok &= reg_bool( api,ru,"NCMM_AWS_ENABLE_FORESTS","Generate forests","Генерировать леса","Master switch for new forests.","Главный переключатель новых лесов.",true );
    ok &= reg_float( api,ru,"NCMM_AWS_FOREST_THRESHOLD","Forest threshold","Порог леса","Lower = more forest. CDDA 0546 default is 0.20.","Ниже = больше леса. Стандарт CDDA 0546 — 0,20.",0.0,1.0,0.20,0.01 );
    ok &= reg_float( api,ru,"NCMM_AWS_FOREST_THICK_THRESHOLD","Dense forest threshold","Порог густого леса","Lower = more dense forest. CDDA 0546 default is 0.25.","Ниже = больше густого леса. Стандарт CDDA 0546 — 0,25.",0.0,1.0,0.25,0.01 );
    ok &= reg_bool( api,ru,"NCMM_AWS_ENABLE_SWAMPS","Generate swamps","Генерировать болота","Master switch for new swamps.","Главный переключатель новых болот.",true );
    ok &= reg_float( api,ru,"NCMM_AWS_SWAMP_ADJ_THRESHOLD","Floodplain swamp threshold","Порог пойменных болот","Lower = more river-adjacent swamp. Vanilla 0.30.","Ниже = больше болот у рек. Стандарт 0,30.",0.0,1.0,0.30,0.01 );
    ok &= reg_float( api,ru,"NCMM_AWS_SWAMP_ISOLATED_THRESHOLD","Isolated swamp threshold","Порог изолированных болот","Lower = more isolated swamp. Vanilla 0.60.","Ниже = больше отдельных болот. Стандарт 0,60.",0.0,1.0,0.60,0.01 );
    ok &= reg_int( api,ru,"NCMM_AWS_FLOODPLAIN_MIN","Floodplain radius minimum","Минимальный радиус поймы","Minimum river floodplain buffer. Vanilla 3.","Минимальный буфер поймы реки. Стандарт 3.",0,30,3 );
    ok &= reg_int( api,ru,"NCMM_AWS_FLOODPLAIN_MAX","Floodplain radius maximum","Максимальный радиус поймы","Maximum river floodplain buffer. Vanilla 15.","Максимальный буфер поймы реки. Стандарт 15.",0,60,15 );
    ok &= reg_bool( api,ru,"NCMM_AWS_ENABLE_TRAILS","Generate forest trails","Генерировать лесные тропы","Master switch for new forest trails and trailheads.","Главный переключатель новых лесных троп и входов.",true );
    ok &= reg_int( api,ru,"NCMM_AWS_TRAIL_CHANCE","Forest trail chance (1 in X)","Шанс лесной тропы (1 из X)","1 means every qualifying forest; CDDA 0546 default is 2.","1 означает каждый подходящий лес; стандарт CDDA 0546 — 2.",1,32,2 );
    ok &= reg_int( api,ru,"NCMM_AWS_TRAIL_MIN_FOREST","Minimum forest size for trails","Минимальный лес для троп","Minimum contiguous forest tiles; CDDA 0546 default is 100.","Минимальный размер связного леса; стандарт CDDA 0546 — 100.",1,1000,100 );
    ok &= reg_int( api,ru,"NCMM_AWS_TRAILHEAD_CHANCE","Trailhead chance (1 in X)","Шанс входа на тропу (1 из X)","1 means every eligible trail end; vanilla 1.","1 означает каждый подходящий конец тропы; стандарт 1.",1,32,1 );
    ok &= reg_int( api,ru,"NCMM_AWS_TRAILHEAD_ROAD_DISTANCE","Trailhead road distance","Дистанция тропы до дороги","Maximum road-search radius for a trailhead; vanilla 6.","Радиус поиска дороги для входа на тропу; стандарт 6.",1,30,6 );
    end(); if( !ok ) return false;

    if( !begin( "aws_geo_water", "Rivers, lakes and oceans", "Реки, озёра и океаны",
                "[NEW MAP] Water-generation controls for newly generated overmaps.",
                "[НОВАЯ КАРТА] Настройки воды для новых овермапов." ) ) return false;
    ok &= reg_bool( api,ru,"NCMM_AWS_ENABLE_RIVERS","Generate rivers","Генерировать реки","Master switch for new rivers.","Главный переключатель новых рек.",true );
    ok &= reg_int( api,ru,"NCMM_AWS_RIVER_SCALE","River width scale","Масштаб ширины рек","0 disables rivers; vanilla region value is 1.","0 отключает реки; стандарт региона 1.",0,5,1 );
    ok &= reg_float( api,ru,"NCMM_AWS_RIVER_FREQUENCY","River frequency divisor","Редкость рек","Higher = fewer new major rivers. Vanilla 1.5.","Выше = меньше новых крупных рек. Стандарт 1,5.",1.0,8.0,1.5,0.1 );
    ok &= reg_int( api,ru,"NCMM_AWS_RIVER_BRANCH_CHANCE","River branch chance (1 in X)","Ветвление рек (1 из X)","Lower = more branches. Vanilla 64.","Ниже = больше ответвлений. Стандарт 64.",1,256,64 );
    ok &= reg_int( api,ru,"NCMM_AWS_RIVER_REMERGE_CHANCE","Branch remerge chance (1 in X)","Слияние ответвлений (1 из X)","Lower = branches rejoin more often. Vanilla 2.","Ниже = ответвления чаще сливаются. Стандарт 2.",1,64,2 );
    ok &= reg_float( api,ru,"NCMM_AWS_RIVER_BRANCH_SCALE_DECREASE","Branch width decrease","Уменьшение ширины ответвлений","Width removed from child branches. Vanilla 1.0.","Насколько уже дочерние ответвления. Стандарт 1,0.",0.0,5.0,1.0,0.25 );
    ok &= reg_bool( api,ru,"NCMM_AWS_ENABLE_LAKES","Generate lakes","Генерировать озёра","Master switch for new lakes.","Главный переключатель новых озёр.",true );
    ok &= reg_float( api,ru,"NCMM_AWS_LAKE_THRESHOLD","Lake threshold","Порог озёр","Lower = more lake terrain. Vanilla 0.25.","Ниже = больше озёр. Стандарт 0,25.",0.0,1.0,0.25,0.01 );
    ok &= reg_int( api,ru,"NCMM_AWS_LAKE_MIN_SIZE","Minimum lake size","Минимальный размер озера","Rejects smaller lake blobs. Vanilla 20.","Отбрасывает меньшие озёра. Стандарт 20.",1,1000,20 );
    ok &= reg_bool( api,ru,"NCMM_AWS_ENABLE_OCEANS","Generate oceans","Генерировать океаны","Master switch where the current region supports oceans.","Главный переключатель там, где регион поддерживает океан.",true );
    ok &= reg_float( api,ru,"NCMM_AWS_OCEAN_THRESHOLD","Ocean threshold","Порог океана","Lower = ocean expands more easily where coastline generation is active. Vanilla 0.25.","Ниже = океан легче расширяется там, где активна береговая генерация. Стандарт 0,25.",0.0,1.0,0.25,0.01 );
    ok &= reg_int( api,ru,"NCMM_AWS_OCEAN_MIN_SIZE","Minimum ocean body size","Минимальный размер океана","Rejects smaller ocean blobs. Vanilla 100.","Отбрасывает меньшие океанские области. Стандарт 100.",1,5000,100 );
    end(); if( !ok ) return false;

    if( !begin( "aws_geo_transport", "Highways and ravines", "Шоссе и овраги",
                "[NEW MAP] Large-scale transport grid and ravine generation.",
                "[НОВАЯ КАРТА] Сетка шоссе и генерация оврагов." ) ) return false;
    ok &= reg_bool( api,ru,"NCMM_AWS_ENABLE_HIGHWAYS","Generate highways","Генерировать шоссе","Master switch for new highways.","Главный переключатель новых шоссе.",true );
    ok &= reg_int( api,ru,"NCMM_AWS_HIGHWAY_GRID_ROW","Highway row separation","Расстояние между горизонтальными шоссе","Overmap-grid separation. Vanilla 8.","Шаг сетки овермапов. Стандарт 8.",2,32,8 );
    ok &= reg_int( api,ru,"NCMM_AWS_HIGHWAY_GRID_COLUMN","Highway column separation","Расстояние между вертикальными шоссе","Overmap-grid separation. Vanilla 10.","Шаг сетки овермапов. Стандарт 10.",2,32,10 );
    ok &= reg_int( api,ru,"NCMM_AWS_HIGHWAY_GRID_VARIANCE","Highway grid variance","Отклонение сетки шоссе","Intersection displacement; automatically clamped to a safe value. Vanilla 2.","Смещение перекрёстков; автоматически ограничивается безопасным значением. Стандарт 2.",0,7,2 );
    ok &= reg_float( api,ru,"NCMM_AWS_HIGHWAY_STRAIGHTNESS","Highway straightness chance","Прямолинейность шоссе","Chance for new highway endpoints to align. Vanilla 0.60.","Шанс выравнивания новых участков шоссе. Стандарт 0,60.",0.0,1.0,0.60,0.05 );
    ok &= reg_bool( api,ru,"NCMM_AWS_ENABLE_RAVINES","Generate ravines","Генерировать овраги","Master switch for ravines where the region supports them.","Главный переключатель оврагов там, где регион их поддерживает.",true );
    ok &= reg_int( api,ru,"NCMM_AWS_RAVINE_COUNT","Ravines per overmap","Оврагов на овермап","0 disables ravines. Vanilla default region is 0.","0 отключает овраги. В стандартном регионе по умолчанию 0.",0,16,0 );
    ok &= reg_int( api,ru,"NCMM_AWS_RAVINE_RANGE","Ravine length range","Длина оврага","Path displacement range. Vanilla 45.","Диапазон смещения пути. Стандарт 45.",1,120,45 );
    ok &= reg_int( api,ru,"NCMM_AWS_RAVINE_WIDTH","Ravine width","Ширина оврага","Ravine width control. CDDA 0546 default is 3.","Управление шириной оврага. Стандарт CDDA 0546 — 3.",1,10,3 );
    ok &= reg_int( api,ru,"NCMM_AWS_RAVINE_DEPTH","Ravine depth Z-level","Глубина оврага по Z","Negative Z-level for ravine floor. Vanilla -3.","Отрицательный Z-уровень дна оврага. Стандарт -3.",-20,-1,-3 );
    end();
    return ok;
}

int expose_all( const ncmm_host_api_v1 *api, bool log_errors ) {
    if( api == nullptr || api->abi_version != NCMM_ABI_VERSION || !api->has_capability ||
        !api->has_capability( "world_settings.v2" ) ||
        !api->has_capability( "world_options.experimental.v1" ) ||
        !api->can_expose_worldgen_option || !api->expose_worldgen_option ||
        !api->worldgen_group_begin || !api->worldgen_experimental_group_begin ||
        !api->worldgen_group_end || !api->worldgen_set_string_choices ||
        !api->world_setting_register_bool ||
        !api->world_setting_register_int || !api->world_setting_register_float ) return 0;
    const option_desc *options = russian( api ) ? options_ru : options_en;
    const std::size_t count = sizeof( options_en ) / sizeof( options_en[0] );
    for( std::size_t i = 0; i < count; ++i ) {
        if( !api->can_expose_worldgen_option( options[i].id ) ) {
            if( log_errors ) api->log( NCMM_LOG_ERROR, "AWS: vanilla option preflight failed." );
            return 0;
        }
    }
    const char *time_ids[] = { "normal", "day", "night" };
    const char *time_en[] = { "Normal", "Day", "Night" };
    const char *time_ru[] = { "Обычное", "День", "Ночь" };
    if( !api->worldgen_set_string_choices( "ETERNAL_TIME_OF_DAY", time_ids,
            russian( api ) ? time_ru : time_en, 3 ) ) return 0;
    const bool ru = russian( api );
    if( !expose_range( api, options, 0, 5, "aws_difficulty",
            tr(ru,"Difficulty and population","Сложность и население"),
            tr(ru,"Independent controls that replace the single coarse difficulty preset.","Независимые настройки вместо одного грубого пресета сложности.") ) ) return 0;
    if( !expose_range( api, options, 5, count, "aws_time",
            tr(ru,"Time and calendar","Время и календарь"),
            tr(ru,"Calendar controls. Some require a world reload.","Настройки календаря. Некоторые требуют перезагрузки мира.") ) ) return 0;
    if( !geography( api, ru ) ) {
        if( log_errors ) api->log( NCMM_LOG_ERROR, "AWS: geography registration failed." );
        return 0;
    }
    return 1;
}

int init( const ncmm_host_api_v1 *api ) {
    if( api == nullptr || api->abi_version != NCMM_ABI_VERSION ) return 0;
    for( const char *capability : required_caps ) {
        if( !api->has_capability || !api->has_capability( capability ) ) return 0;
    }
    if( api->get_api_version_major && api->get_api_version_minor ) {
        if( api->get_api_version_major() != 1 || api->get_api_version_minor() < 7 ) return 0;
    }
    if( !expose_all( api, true ) ) return 0;
    api->log( NCMM_LOG_INFO, "Advanced World Settings 0.6.1 initialized: vanilla controls + experimental geography page active." );
    return 1;
}
void shutdown() {}

const ncmm_mod_descriptor_v1 descriptor = {
    NCMM_ABI_VERSION, module_id, "Advanced World Settings", "0.6.1",
    required_caps, sizeof( required_caps ) / sizeof( required_caps[0] ), &init, &shutdown
};
}

extern "C" NCMM_EXPORT const ncmm_mod_descriptor_v1 *ncmm_get_descriptor_v1() { return &descriptor; }
extern "C" NCMM_EXPORT void ncmm_on_locale_changed_v1( const ncmm_host_api_v1 *api ) { expose_all( api, false ); }