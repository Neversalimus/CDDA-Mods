#include <algorithm>
#include <iostream>
#include <string>
#include "avatar.h"
#include "calendar.h"
#include "cata_catch.h"
#include "coordinates.h"
#include "creature_tracker.h"
#include "dialogue.h"
#include "effect_on_condition.h"
#include "game.h"
#include "global_vars.h"
#include "item.h"
#include "map.h"
#include "map_helpers.h"
#include "mattack_common.h"
#include "math_parser_diag_value.h"
#include "monster.h"
#include "mtype.h"
#include "overmapbuffer.h"
#include "player_activity.h"
#include "player_helpers.h"
#include "recipe.h"
#include "skill.h"
#include "talker.h"
#include "teleport.h"
#include "type_id.h"
#include "worldfactory.h"

namespace {
void eoc( const char *id )
{
    std::cerr << "IZN stage: " << id << std::endl;
    const effect_on_condition_id e( id );
    REQUIRE( e.is_valid() );
    dialogue d( get_talker_for( get_avatar() ), nullptr );
    e->activate( d );
}
tripoint_abs_ms saved_pos( const char *key )
{
    const diag_value *v = get_avatar().maybe_get_value( key );
    REQUIRE( v != nullptr );
    return v->tripoint();
}
double global_num( const char *key )
{
    const diag_value *v = get_globals().maybe_get_global_value( key );
    return v ? v->dbl() : 0;
}
void warp( const tripoint_abs_ms &p )
{
    REQUIRE( teleport::teleport_to_point( get_avatar(), get_map().get_bub( p ),
                                        true, false, false, false, true ) );
}
int ground_count( const tripoint_abs_ms &p, const char *id )
{
    const auto stack = get_map().i_at( get_map().get_bub( p ) );
    return std::count_if( stack.begin(), stack.end(), [&]( const item & it ) {
        return it.typeId() == itype_id( id );
    } );
}
} // namespace

TEST_CASE( "iznanka_expedition_persists_and_returns", "[iznanka_lifecycle]" )
{
    clear_creatures();
    clear_map();
    clear_avatar();
    avatar &u = get_avatar();
    u.name = "Iznanka runtime QA";
    calendar::turn = calendar::start_of_cataclysm + 7_days;
    const tripoint_abs_ms home = u.pos_abs();
    const tripoint_abs_ms blocked_home = home + tripoint( 30, 0, 0 );
    for( int x = -6; x <= 6; ++x ) {
        for( int y = -6; y <= 6; ++y ) {
            get_map().ter_set( get_map().get_bub( blocked_home + tripoint( x, y, 0 ) ), ter_str_id( "t_rock" ) );
        }
    }
    get_map().furn_set( u.pos_bub(), furn_str_id( "f_izn_entry" ) );
    get_map().add_item_or_charges( u.pos_bub(), item( itype_id( "izn_resin" ), calendar::turn ) );
    eoc( "IZN_ENTER" );
    REQUIRE( g->get_dimension_prefix() == dimension_id( "iznanka" ) );
    const tripoint_abs_ms hub = saved_pos( "izn_hub" );
    CHECK( rl_dist( u.pos_abs(), hub ) <= 5 );
    CHECK( get_map().furn( get_map().get_bub( hub ) ) == furn_str_id( "f_izn_exit" ) );
    CHECK( ground_count( hub, "izn_resin" ) == 0 );
    const tripoint_abs_ms stash = hub + tripoint( -2, 1, 0 );
    CHECK( ground_count( stash, "izn_detector" ) == 1 );
    CHECK( ground_count( stash, "izn_seal" ) == 2 );
    // Remove the generated cache and leave our own item. Neither may reset on entry.
    get_map().i_clear( get_map().get_bub( stash ) );
    get_map().add_item_or_charges( get_map().get_bub( stash ), item( itype_id( "izn_glassbone" ), calendar::turn ) );
    u.set_value( "izn_resonance", diag_value( 50 ) );
    eoc( "IZN_RESONANCE" );
    CHECK( u.get_value( "izn_resonance" ).dbl() == 40 );
    eoc( "IZN_RETURN" );
    REQUIRE( g->get_dimension_prefix() == dimension_id( "default" ) );
    CHECK( rl_dist( u.pos_abs(), home ) <= 5 );
    CHECK( ground_count( home, "izn_resin" ) == 1 );
    eoc( "IZN_RESONANCE" );
    CHECK( u.get_value( "izn_resonance" ).dbl() == 40 );
    eoc( "IZN_ENTER" );
    REQUIRE( g->get_dimension_prefix() == dimension_id( "iznanka" ) );
    CHECK( saved_pos( "izn_hub" ) == hub );
    CHECK( ground_count( stash, "izn_detector" ) == 0 );
    CHECK( ground_count( stash, "izn_glassbone" ) == 1 );

    // The second branch works before the pump; deleting only its discovery marker
    // simulates a pre-extension save without overwriting any authored v0.1 maps.
    u.wear_item( item( itype_id( "debug_backpack" ), calendar::turn ), false );
    const diag_value *town_var = get_globals().maybe_get_global_value( "izn_town" );
    REQUIRE( town_var != nullptr );
    const tripoint_abs_ms town = town_var->tripoint();
    get_globals().remove_global_value( "izn_town" );
    eoc( "IZN_DETECT" );
    REQUIRE( get_globals().maybe_get_global_value( "izn_town" ) != nullptr );
    CHECK( get_globals().maybe_get_global_value( "izn_town" )->tripoint() == town );
    const tripoint_abs_ms town_origin = project_to<coords::ms>( project_to<coords::omt>( town ) );
    const tripoint_abs_ms radio = town_origin + tripoint( 12, 60, 0 );
    warp( radio + tripoint::west );
    REQUIRE( get_map().furn( get_map().get_bub( radio ) ) == furn_str_id( "f_izn_radio" ) );
    eoc( "IZN_RADIO" );
    CHECK( global_num( "izn_radio_done" ) == 0 );
    CHECK( global_num( "izn_node_done" ) == 0 );
    // A technical route with interrupted and repeated console use.
    const tripoint_abs_ms consoles[] = {
        town_origin + tripoint( -20, 29, 0 ),
        town_origin + tripoint( 28, 29, 0 ),
        town_origin + tripoint( -20, 53, 0 )
    };
    const char *begins[] = { "IZN_TUNE_A_BEGIN", "IZN_TUNE_B_BEGIN", "IZN_TUNE_C_BEGIN" };
    const char *flags[] = { "izn_tuned_a", "izn_tuned_b", "izn_tuned_c" };
    u.set_skill_level( skill_id( "electronics" ), 2 );
    for( int i = 0; i < 3; ++i ) {
        warp( consoles[i] + tripoint::west );
        eoc( begins[i] );
        CHECK_FALSE( u.activity.is_null() );
        u.cancel_activity();
        CHECK( global_num( flags[i] ) == 0 );
        eoc( begins[i] );
        u.activity.moves_left = 0;
        u.activity.do_turn( u );
        CHECK( global_num( flags[i] ) == 1 );
        const int before = u.amount_of( itype_id( "izn_suppressor" ) );
        eoc( begins[i] );
        CHECK( u.activity.is_null() );
        CHECK( u.amount_of( itype_id( "izn_suppressor" ) ) == before );
    }
    warp( radio + tripoint::west );
    CHECK( global_num( "izn_voices_dead" ) == 0 );
    eoc( "IZN_RADIO" );
    REQUIRE( global_num( "izn_radio_done" ) == 1 );
    CHECK( global_num( "izn_node_done" ) == 0 );
    CHECK( global_num( "izn_voices_dead" ) == 3 );
    CHECK( u.has_amount( itype_id( "izn_suppressor" ), 1 ) );
    CHECK( u.knows_recipe( &recipe_id( "izn_suppressor" ).obj() ) );
    eoc( "IZN_RADIO" );
    CHECK_FALSE( u.has_amount( itype_id( "izn_suppressor" ), 2 ) );
    u.i_add( item( itype_id( "izn_resin" ), calendar::turn ) );
    const int resin = u.amount_of( itype_id( "izn_resin" ) );
    eoc( "IZN_SUPPRESS" );
    CHECK( u.amount_of( itype_id( "izn_resin" ) ) == resin - 1 );
    u.set_value( "izn_resonance", diag_value( 20 ) );
    eoc( "IZN_RESONANCE" );
    CHECK( u.get_value( "izn_resonance" ).dbl() == 22 );
    eoc( "IZN_SUPPRESS" );
    CHECK( u.amount_of( itype_id( "izn_resin" ) ) == resin - 1 );
    u.remove_effect( efftype_id( "izn_suppressed" ) );
    eoc( "IZN_RESONANCE" );
    CHECK( u.get_value( "izn_resonance" ).dbl() == 26 );
    // Exercise the actual support attack, including its allied target filter.
    clear_creatures();
    monster *orderly = g->place_critter_at( mtype_id( "mon_izn_orderly" ),
                                         get_map().get_bub( radio + tripoint( 3, 0, 0 ) ) );
    monster *patient = g->place_critter_at( mtype_id( "mon_izn_walker" ),
                                         get_map().get_bub( radio + tripoint( 4, 0, 0 ) ) );
    REQUIRE( orderly != nullptr );
    REQUIRE( patient != nullptr );
    patient->set_hp( 100 );
    const mtype_special_attack &mend = orderly->type->special_attacks.at( "izn_orderly_mend" );
    REQUIRE( mend->call( *orderly ) );
    CHECK( patient->get_hp() == 115 );
    // Reset only the town fixture to test the combat route without any tuned consoles.
    clear_creatures();
    get_globals().set_global_value( "izn_radio_done", diag_value( 0 ) );
    get_globals().set_global_value( "izn_voices_dead", diag_value( 0 ) );
    for( const char *flag : flags ) {
        get_globals().set_global_value( flag, diag_value( 0 ) );
    }
    get_map().furn_set( get_map().get_bub( radio ), furn_str_id( "f_izn_radio" ) );
    for( int i = 0; i < 3; ++i ) {
        monster *voice = g->place_critter_at( mtype_id( "mon_izn_voice" ),
                                            get_map().get_bub( radio + tripoint( 3, i - 1, 0 ) ) );
        REQUIRE( voice != nullptr );
        voice->die( &get_map(), &u );
    }
    CHECK( global_num( "izn_voices_dead" ) == 3 );
    const int suppressors = u.amount_of( itype_id( "izn_suppressor" ) );
    eoc( "IZN_RADIO" );
    CHECK( global_num( "izn_radio_done" ) == 1 );
    CHECK( u.amount_of( itype_id( "izn_suppressor" ) ) == suppressors + 1 );

    // Authored special: pump two OMTs south; cache east of the central trail.
    const tripoint_abs_ms pump = hub + tripoint( 0, 49, 0 );
    warp( pump + tripoint::west );
    REQUIRE( get_map().furn( get_map().get_bub( pump ) ) == furn_str_id( "f_izn_pump" ) );
    eoc( "IZN_PUMP" );
    CHECK( global_num( "izn_node_done" ) == 0 );
    bool found_warden = false;
    for( monster &m : g->all_monsters() ) {
        if( m.type->id == mtype_id( "mon_izn_warden" ) ) {
            found_warden = true;
            m.die( &get_map(), &u );
        }
    }
    REQUIRE( found_warden );
    CHECK( global_num( "izn_warden_dead" ) == 1 );
    clear_creatures();
    for( int n = 0; n < 2; ++n ) {
        u.i_add( item( itype_id( "izn_glassbone" ), calendar::turn ) );
        u.i_add( item( itype_id( "izn_thread" ), calendar::turn ) );
    }
    eoc( "IZN_PUMP" );
    CHECK( global_num( "izn_node_done" ) == 1 );
    CHECK( get_map().furn( get_map().get_bub( pump ) ) == furn_str_id( "f_izn_pump_active" ) );
    CHECK( u.has_amount( itype_id( "izn_heart" ), 1 ) );
    CHECK_FALSE( u.has_amount( itype_id( "izn_glassbone" ), 1 ) );
    eoc( "IZN_PUMP" );
    CHECK_FALSE( u.has_amount( itype_id( "izn_heart" ), 2 ) );
    u.set_value( "izn_resonance", diag_value( 99 ) );
    eoc( "IZN_RESONANCE" );
    CHECK( u.get_value( "izn_resonance" ).dbl() == 100 );
    eoc( "IZN_HEART" );
    CHECK( u.get_value( "izn_resonance" ).dbl() == 60 );
    eoc( "IZN_HEART" );
    CHECK( u.get_value( "izn_resonance" ).dbl() == 60 );

    // A blocked landing cancels the return and retains the seal.
    const int before_blocked = u.amount_of( itype_id( "izn_seal" ) );
    u.set_value( "izn_home", diag_value( blocked_home ) );
    eoc( "IZN_SEAL_BEGIN" );
    u.activity.moves_left = 0;
    u.activity.do_turn( u );
    REQUIRE( g->get_dimension_prefix() == dimension_id( "iznanka" ) );
    CHECK( u.amount_of( itype_id( "izn_seal" ) ) == before_blocked );
    u.set_value( "izn_home", diag_value( home ) );

    // Interrupted activity consumes nothing; successful completion consumes exactly one.
    const int seals = u.amount_of( itype_id( "izn_seal" ) );
    REQUIRE( seals >= 1 );
    eoc( "IZN_SEAL_BEGIN" );
    CHECK( u.activity.id() == activity_id( "ACT_IZN_RETURN" ) );
    u.cancel_activity();
    CHECK( u.amount_of( itype_id( "izn_seal" ) ) == seals );
    eoc( "IZN_SEAL_BEGIN" );
    u.activity.moves_left = 0;
    u.activity.do_turn( u );
    REQUIRE( g->get_dimension_prefix() == dimension_id( "default" ) );
    CHECK( rl_dist( u.pos_abs(), home ) <= 5 );
    CHECK( u.amount_of( itype_id( "izn_seal" ) ) == seals - 1 );
    eoc( "IZN_ENTER" );
    REQUIRE( g->get_dimension_prefix() == dimension_id( "iznanka" ) );
    warp( pump + tripoint::west );
    CHECK( get_map().furn( get_map().get_bub( pump ) ) == furn_str_id( "f_izn_pump_active" ) );
    CHECK( global_num( "izn_node_done" ) == 1 );
    for( const monster &m : g->all_monsters() ) {
        CHECK( m.type->id != mtype_id( "mon_izn_warden" ) );
    }
    // Destroy the old game before reloading factories, as on a fresh process start.
    const std::string save = world_generator->active_world->world_name;
    REQUIRE( g->save() );
    g->uquit = QUIT_SAVED;
    REQUIRE( turn_handler::cleanup_at_end() );
    g = std::make_unique<game>();
    get_globals().clear_global_values();
    std::cerr << "IZN stage: reload into fresh game" << std::endl;
    REQUIRE( g->load( save ) );
    CHECK( saved_pos( "izn_hub" ) == hub );
    CHECK( saved_pos( "izn_home" ) == home );
    warp( hub );
    CHECK( ground_count( stash, "izn_detector" ) == 0 );
    CHECK( ground_count( stash, "izn_glassbone" ) == 1 );
    CHECK( global_num( "izn_node_done" ) == 1 );
    CHECK( global_num( "izn_radio_done" ) == 1 );
    CHECK( get_globals().maybe_get_global_value( "izn_town" )->tripoint() == town );
    warp( radio + tripoint::west );
    CHECK( get_map().furn( get_map().get_bub( radio ) ) == furn_str_id( "f_izn_radio_active" ) );
    eoc( "IZN_RADIO" );
    CHECK( get_avatar().amount_of( itype_id( "izn_suppressor" ) ) == suppressors + 1 );
    eoc( "IZN_RETURN" );
    CHECK( g->get_dimension_prefix() == dimension_id( "default" ) );
}
