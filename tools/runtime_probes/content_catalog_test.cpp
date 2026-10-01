#include <cstddef>
#include <string>
#include <vector>

#include "calendar.h"
#include "cata_catch.h"
#include "item.h"
#include "item_factory.h"
#include "itype.h"
#include "omdata.h"
#include "recipe.h"
#include "recipe_dictionary.h"
#include "veh_type.h"
#include "vehicle.h"

TEST_CASE( "cdda_mods_all_loaded_items_construct", "[cdda_mods_content][content_items]" )
{
    std::size_t count = 0;
    for( const itype *type : item_controller->all() ) {
        REQUIRE( type != nullptr );
        CAPTURE( type->get_id().str() );
        item sample( type, calendar::turn_zero, item::solitary_tag {} );
        CHECK( sample.typeId() == type->get_id() );
        ++count;
    }
    INFO( "loaded item types: " << count );
    CHECK( count > 0 );
}

TEST_CASE( "cdda_mods_all_loaded_recipes_materialize_results",
           "[cdda_mods_content][content_recipes]" )
{
    std::size_t count = 0;
    std::size_t materialized = 0;
    std::size_t non_item_results = 0;
    for( const auto &entry : recipe_dict ) {
        const recipe_id &id = entry.first;
        const recipe &rec = entry.second;
        CAPTURE( id.str() );
        CHECK( rec.ident() == id );
        CHECK( rec.was_loaded );
        CHECK( rec.get_consistency_error().empty() );

        const itype_id result_id = rec.result();
        const bool item_producing =
            !rec.is_practice() && !rec.is_nested() && !rec.is_blueprint() &&
            !result_id.is_null() && result_id.is_valid();
        if( item_producing ) {
            const std::vector<item> results = rec.create_results( 1 );
            CHECK_FALSE( results.empty() );
            for( const item &result : results ) {
                CHECK_FALSE( result.typeId().is_null() );
                CHECK( result.typeId().is_valid() );
            }
            const std::vector<item> byproducts = rec.create_byproducts( 1 );
            for( const item &byproduct : byproducts ) {
                CHECK_FALSE( byproduct.typeId().is_null() );
                CHECK( byproduct.typeId().is_valid() );
            }
            ++materialized;
        } else {
            ++non_item_results;
        }
        ++count;
    }
    INFO( "loaded recipes: " << count );
    INFO( "materialized recipe outputs: " << materialized );
    INFO( "non-item/sentinel recipe entries: " << non_item_results );
    CHECK( count > 0 );
    CHECK( materialized > 0 );
}

TEST_CASE( "cdda_mods_all_loaded_vehicle_content_resolves",
           "[cdda_mods_content][content_vehicles]" )
{
    std::size_t part_count = 0;
    for( const vpart_info &part : vehicles::parts::get_all() ) {
        CAPTURE( part.id.str() );
        CHECK( part.id.is_valid() );
        if( !part.base_item.is_null() ) {
            CHECK( part.base_item.is_valid() );
        }
        ++part_count;
    }

    std::size_t prototype_count = 0;
    for( const vehicle_prototype &prototype : vehicles::get_all_prototypes() ) {
        // CDDA keeps an internal "none" prototype with an intentionally empty
        // blueprint.  It is a runtime sentinel, not playable vehicle content.
        if( prototype.id.is_null() || prototype.id == vproto_id( "none" ) ) {
            continue;
        }
        CAPTURE( prototype.id.str() );
        CHECK( prototype.id.is_valid() );
        REQUIRE( prototype.blueprint );
        CHECK( prototype.blueprint->part_count() > 0 );
        ++prototype_count;
    }

    INFO( "loaded vehicle parts: " << part_count );
    INFO( "loaded vehicle prototypes: " << prototype_count );
    CHECK( part_count > 0 );
    CHECK( prototype_count > 0 );
}

TEST_CASE( "cdda_mods_all_loaded_overmap_content_resolves",
           "[cdda_mods_content][content_overmap]" )
{
    std::size_t terrain_count = 0;
    for( const oter_t &terrain : overmap_terrains::get_all() ) {
        if( terrain.id.is_null() ) {
            continue;
        }
        CAPTURE( terrain.id.str() );
        CHECK( terrain.get_type_id().is_valid() );
        ++terrain_count;
    }

    std::size_t special_count = 0;
    for( const overmap_special &special : overmap_specials::get_all() ) {
        if( special.id.is_null() ) {
            continue;
        }
        CAPTURE( special.id.str() );
        CHECK( special.id.is_valid() );
        for( const oter_type_id &terrain_id : special.get_terrain_type_ids() ) {
            CAPTURE( terrain_id.id().str() );
            CHECK( terrain_id.id().is_valid() );
        }
        ++special_count;
    }

    INFO( "loaded overmap terrains: " << terrain_count );
    INFO( "loaded overmap specials: " << special_count );
    CHECK( terrain_count > 0 );
    CHECK( special_count > 0 );
}
