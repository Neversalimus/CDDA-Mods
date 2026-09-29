#include <algorithm>
#include <array>
#include <string>
#include <utility>
#include <vector>

#include "avatar.h"
#include "calendar.h"
#include "creature_tracker.h"
#include "cata_catch.h"
#include "coordinates.h"
#include "dialogue.h"
#include "effect_on_condition.h"
#include "item.h"
#include "map.h"
#include "map_helpers.h"
#include "map_helpers_tests.h"
#include "map_scale_constants.h"
#include "mapbuffer.h"
#include "mapgen_helpers.h"
#include "math_parser_diag_value.h"
#include "mission.h"
#include "monster.h"
#include "mtype.h"
#include "npc.h"
#include "omdata.h"
#include "overmapbuffer.h"
#include "player_helpers.h"
#include "point.h"
#include "submap.h"
#include "talker.h"
#include "type_id.h"
#include "vehicle.h"

namespace
{

static const tripoint_abs_omt axiom_origin( 80, 80, 0 );

void reset_axiom_runtime()
{
    get_avatar().move_to( tripoint_abs_ms::zero );
    clear_creatures();
    clear_npcs();
    clear_overmaps();
    clear_map( -2, 2 );
    clear_avatar();
    calendar::turn = calendar::start_of_cataclysm + 7_days;
}

void set_omt( const tripoint_abs_omt &pos, const char *id )
{
    const oter_str_id terrain( id );
    REQUIRE( terrain.is_valid() );
    overmap_buffer.ter_set( pos, terrain.id() );
}

void seed_axiom_layout()
{
    const std::array<std::array<const char *, 3>, 3> surface = { {
            { "axiom_7_nw_north", "axiom_7_n_north", "axiom_7_ne_north" },
            { "axiom_7_w_north", "axiom_7_c_north", "axiom_7_e_north" },
            { "axiom_7_sw_north", "axiom_7_s_north", "axiom_7_se_north" }
        } };
    for( int y = 0; y < 3; ++y ) {
        for( int x = 0; x < 3; ++x ) {
            set_omt( axiom_origin + tripoint( x, y, 0 ), surface[y][x] );
        }
    }

    const std::array<std::array<const char *, 3>, 2> roof = { {
            { "axiom_7_roof_w_north", "axiom_7_roof_c_north", "axiom_7_roof_e_north" },
            { "axiom_7_roof_sw_north", "axiom_7_roof_s_north", "axiom_7_roof_se_north" }
        } };
    const std::array<std::array<const char *, 3>, 2> basement = { {
            { "axiom_7_sub_w_north", "axiom_7_sub_c_north", "axiom_7_sub_e_north" },
            { "axiom_7_sub_sw_north", "axiom_7_sub_s_north", "axiom_7_sub_se_north" }
        } };
    for( int y = 0; y < 2; ++y ) {
        for( int x = 0; x < 3; ++x ) {
            set_omt( axiom_origin + tripoint( x, y + 1, 1 ), roof[y][x] );
            set_omt( axiom_origin + tripoint( x, y + 1, -1 ), basement[y][x] );
        }
    }
}

bool has_terrain( map &m, int z, const ter_str_id &wanted )
{
    for( int x = 0; x < SEEX * 2; ++x ) {
        for( int y = 0; y < SEEY * 2; ++y ) {
            if( m.ter( tripoint_bub_ms( x, y, z ) ) == wanted.id() ) {
                return true;
            }
        }
    }
    return false;
}

bool has_spawned_monster( const mtype_id &wanted )
{
    const auto &monsters = get_creature_tracker().get_monsters_list();
    return std::any_of( monsters.begin(), monsters.end(), [&]( const auto &mon ) {
        return mon && mon->type->id == wanted;
    } );
}

bool omt_has_npc( const tripoint_abs_omt &pos, const npc_template_id &wanted )
{
    const auto nearby = overmap_buffer.get_npcs_near_omt( pos, 0 );
    return std::any_of( nearby.begin(), nearby.end(), [&]( const auto & guy ) {
        return guy && guy->idz == wanted;
    } );
}

bool map_has_vehicle( map &m, const vproto_id &wanted )
{
    const VehicleList vehicles = m.get_vehicles();
    return std::any_of( vehicles.begin(), vehicles.end(), [&]( const wrapped_vehicle & wv ) {
        return wv.v != nullptr && wv.v->type == wanted;
    } );
}

bool saved_omt_has_vehicle( const tripoint_abs_omt &pos, const vproto_id &wanted )
{
    tinymap tm;
    tm.load( pos, true );
    return map_has_vehicle( *tm.cast_to_map(), wanted );
}

void run_mission_end( const char *id )
{
    const mission_type_id mission_id( id );
    REQUIRE( mission_id.is_valid() );
    const mission_type *type = mission_type::get( mission_id );
    REQUIRE( type != nullptr );
    mission instance = type->create( character_id() );
    type->end( &instance );
}

bool avatar_value_is( const std::string &key, const std::string &wanted )
{
    const diag_value *value = get_avatar().maybe_get_value( key );
    return value != nullptr && value->to_string() == wanted;
}

bool avatar_or_ground_has_item( const itype_id &wanted )
{
    avatar &u = get_avatar();
    if( u.has_amount( wanted, 1 ) ) {
        return true;
    }
    map_stack ground = get_map().i_at( u.pos_bub() );
    return std::any_of( ground.begin(), ground.end(), [&]( const item &it ) {
        return it.typeId() == wanted;
    } );
}

} // namespace

TEST_CASE( "axiom7_composite_mapgen_runtime", "[axiom7_lifecycle][mapgen]" )
{
    reset_axiom_runtime();
    seed_axiom_layout();

    SECTION( "surface central atrium generates with AXIOM entities" ) {
        const tripoint_abs_omt pos = axiom_origin + tripoint( 1, 1, 0 );
        MAPBUFFER.clear_outside_reality_bubble();
        smallmap tm;
        tm.generate( pos, calendar::turn, false, true );
        map &m = *tm.cast_to_map();

        CHECK( has_terrain( m, 0, ter_str_id( "t_linoleum_whitefloor_olight" ) ) );
        m.spawn_monsters( true );
        CHECK( has_spawned_monster( mtype_id( "mon_axiom_patrol_sentry" ) ) );
        CHECK( has_spawned_monster( mtype_id( "mon_axiom_security_turret" ) ) );
        CHECK( omt_has_npc( pos, npc_template_id( "axiom_7_liaison" ) ) );

        tm.delete_unmerged_submaps();
    }

    SECTION( "basement security operations generates" ) {
        const tripoint_abs_omt pos = axiom_origin + tripoint( 1, 2, -1 );
        MAPBUFFER.clear_outside_reality_bubble();
        smallmap tm;
        tm.generate( pos, calendar::turn, false, true );
        map &m = *tm.cast_to_map();

        CHECK( has_terrain( m, -1, ter_str_id( "t_thconc_floor_olight" ) ) );
        CHECK( omt_has_npc( pos, npc_template_id( "axiom_7_security_director" ) ) );

        tm.delete_unmerged_submaps();
    }

    SECTION( "roof flight deck and support annex generate" ) {
        const tripoint_abs_omt deck = axiom_origin + tripoint( 1, 2, 1 );
        MAPBUFFER.clear_outside_reality_bubble();
        smallmap deck_map;
        deck_map.generate( deck, calendar::turn, false, true );
        map &m = *deck_map.cast_to_map();

        CHECK( has_terrain( m, 1, ter_str_id( "t_metal_floor_olight" ) ) );
        CHECK( map_has_vehicle( m, vproto_id( "axiom_kx91_dormant" ) ) );
        deck_map.delete_unmerged_submaps();

        const tripoint_abs_omt support = axiom_origin + tripoint( 2, 2, 1 );
        MAPBUFFER.clear_outside_reality_bubble();
        smallmap support_map;
        support_map.generate( support, calendar::turn, false, true );
        CHECK( omt_has_npc( support, npc_template_id( "axiom_7_flight_tech" ) ) );
        support_map.delete_unmerged_submaps();
    }
}

TEST_CASE( "axiom7_clearance_mission_end_effects", "[axiom7_lifecycle][mission]" )
{
    reset_axiom_runtime();
    avatar &u = get_avatar();

    run_mission_end( "MISSION_AXIOM_SENSOR_RELAY" );
    CHECK( avatar_value_is( "axiom_clearance_contractor", "yes" ) );
    CHECK( avatar_or_ground_has_item( itype_id( "axiom_card_contractor" ) ) );

    run_mission_end( "MISSION_AXIOM_POWER_STACK" );
    CHECK( avatar_value_is( "axiom_clearance_specialist", "yes" ) );
    CHECK( avatar_or_ground_has_item( itype_id( "axiom_card_specialist" ) ) );

    run_mission_end( "MISSION_AXIOM_ROGUE_SENTINEL" );
    CHECK( avatar_value_is( "axiom_clearance_prototype", "yes" ) );
    CHECK( avatar_or_ground_has_item( itype_id( "axiom_card_prototype" ) ) );
}

TEST_CASE( "axiom7_kx91_vehicle_swap_lifecycle", "[axiom7_lifecycle][kx91][mapgen]" )
{
    reset_axiom_runtime();
    seed_axiom_layout();
    const tripoint_abs_omt deck = axiom_origin + tripoint( 1, 2, 1 );

    MAPBUFFER.clear_outside_reality_bubble();
    {
        smallmap initial;
        initial.generate( deck, calendar::turn, true, true );
        CHECK( map_has_vehicle( *initial.cast_to_map(), vproto_id( "axiom_kx91_dormant" ) ) );
    }

    const std::vector<std::pair<const char *, const char *>> stages = {
        { "AXIOM_KX91_SWAP_POWERED", "axiom_kx91_powered" },
        { "AXIOM_KX91_SWAP_AVIONICS", "axiom_kx91_avionics" },
        { "AXIOM_KX91_SWAP_WEAPONS_READY", "axiom_kx91_weapons_ready" },
        { "AXIOM_KX91_SWAP_OPERATIONAL_AXIOM", "axiom_combat_helicopter" },
        { "AXIOM_KX91_SWAP_OPERATIONAL_PLAYER", "axiom_combat_helicopter" }
    };

    for( const auto &stage : stages ) {
        const update_mapgen_id update( stage.first );
        REQUIRE( update.is_valid() );
        manual_mapgen( deck, manual_update_mapgen, update );
        CHECK( saved_omt_has_vehicle( deck, vproto_id( stage.second ) ) );
    }

    clear_overmaps();
}

TEST_CASE( "axiom7_security_alarm_runtime", "[axiom7_lifecycle][security][eoc]" )
{
    reset_axiom_runtime();
    clear_map_without_vision( -1, 1 );

    avatar &u = get_avatar();
    u.remove_value( "axiom_security_hostile" );
    monster &bot = spawn_test_monster(
                       "mon_axiom_patrol_sentry",
                       u.pos_bub() + tripoint::east,
                       false
                   );
    bot.anger = 0;

    dialogue d( get_talker_for( u ), nullptr );
    const effect_on_condition_id alarm( "EOC_AXIOM_SECURITY_ALARM" );
    REQUIRE( alarm.is_valid() );
    REQUIRE( alarm->activate( d ) );

    CHECK( avatar_value_is( "axiom_security_hostile", "yes" ) );
    CHECK( bot.anger == 100 );
}
