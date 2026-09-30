import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AXIOM = ROOT / "mods" / "axiom_7"
CONTENT = AXIOM / "content"

MAP_FILES = (
    "mapgen.json",
    "basement_mapgen.json",
    "roof_mapgen.json",
)

BLOCKING_TERRAIN_TOKENS = (
    "wall",
    "reinforced_glass",
    "open_air",
)


def load_json(name):
    return json.loads((CONTENT / name).read_text(encoding="utf-8-sig"))


def map_object(name):
    data = load_json(name)
    if len(data) != 1 or data[0].get("type") != "mapgen":
        raise AssertionError(f"{name}: expected one composite mapgen object")
    return data[0]["object"], data[0]["om_terrain"]


def terrain_at(obj, x, y):
    rows = obj["rows"]
    if not (0 <= y < len(rows) and 0 <= x < len(rows[y])):
        return None
    symbol = rows[y][x]
    return obj.get("terrain", {}).get(symbol, obj.get("fill_ter"))


def is_blocking(terrain_id):
    if terrain_id is None:
        return True
    if terrain_id == "t_rock":
        return True
    return any(token in terrain_id for token in BLOCKING_TERRAIN_TOKENS)


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def values_for_key(value, key):
    return [node[key] for node in walk(value) if key in node]


def terrain_points(obj, wanted):
    out = []
    for y, row in enumerate(obj["rows"]):
        for x, symbol in enumerate(row):
            if obj.get("terrain", {}).get(symbol, obj.get("fill_ter")) == wanted:
                out.append((x, y))
    return out


def find_omt_origin(matrix, omt_id):
    for row_index, row in enumerate(matrix):
        for col_index, value in enumerate(row):
            if value == omt_id:
                return col_index * 24, row_index * 24
    raise AssertionError(f"OMT {omt_id} not found")


class Axiom7IntegrityTests(unittest.TestCase):
    def test_composite_mapgen_dimensions_match_omt_matrices(self):
        for name in MAP_FILES:
            with self.subTest(name=name):
                obj, matrix = map_object(name)
                self.assertTrue(matrix)
                columns = len(matrix[0])
                self.assertTrue(all(len(row) == columns for row in matrix))
                expected_width = columns * 24
                expected_height = len(matrix) * 24
                self.assertEqual(len(obj["rows"]), expected_height)
                self.assertTrue(
                    all(len(row) == expected_width for row in obj["rows"]),
                    f"{name}: inconsistent row width",
                )

    def test_all_static_spawns_are_inside_their_composite_map(self):
        for name in MAP_FILES:
            with self.subTest(name=name):
                obj, _ = map_object(name)
                height = len(obj["rows"])
                width = len(obj["rows"][0])
                for key in ("place_npcs", "place_monster", "place_vehicles", "place_traps"):
                    for entry in obj.get(key, []):
                        x, y = entry["x"], entry["y"]
                        self.assertTrue(
                            0 <= x < width and 0 <= y < height,
                            f"{name}: {key} spawn outside map at {(x, y)}",
                        )

    def test_patrol_points_use_cdda_local_omt_semantics(self):
        # CDDA interprets spawn_data.patrol from the local (0, 0) of the
        # 24x24 OMT containing the monster, not from the composite map origin.
        for name in MAP_FILES:
            obj, _ = map_object(name)
            height = len(obj["rows"])
            width = len(obj["rows"][0])
            for monster in obj.get("place_monster", []):
                patrol = monster.get("spawn_data", {}).get("patrol", [])
                if not patrol:
                    continue
                origin_x = (monster["x"] // 24) * 24
                origin_y = (monster["y"] // 24) * 24
                for point in patrol:
                    self.assertIsInstance(point["x"], int)
                    self.assertIsInstance(point["y"], int)
                    x = origin_x + point["x"]
                    y = origin_y + point["y"]
                    self.assertTrue(
                        0 <= x < width and 0 <= y < height,
                        (
                            f"{name}: patrol for {monster['monster']} at "
                            f"{(monster['x'], monster['y'])} resolves outside "
                            f"the composite map: relative {point} -> {(x, y)}"
                        ),
                    )
                    terrain = terrain_at(obj, x, y)
                    self.assertFalse(
                        is_blocking(terrain),
                        (
                            f"{name}: patrol for {monster['monster']} at "
                            f"{(monster['x'], monster['y'])} resolves onto "
                            f"blocked terrain {terrain} at {(x, y)}"
                        ),
                    )

    def test_reader_locations_have_a_controlled_lock_in_range(self):
        for name in MAP_FILES:
            obj, _ = map_object(name)
            readers = []
            locks = terrain_points(obj, "t_door_metal_locked")
            for y, row in enumerate(obj["rows"]):
                for x, symbol in enumerate(row):
                    terrain = obj.get("terrain", {}).get(symbol, obj.get("fill_ter"))
                    if terrain and terrain.startswith("t_axiom_reader_"):
                        readers.append((x, y, terrain))
            for x, y, terrain in readers:
                self.assertTrue(
                    any(max(abs(x - lx), abs(y - ly)) <= 3 for lx, ly in locks),
                    f"{name}: {terrain} at {(x, y)} has no locked metal door in radius 3",
                )

    def test_vertical_stairs_align_between_levels(self):
        surface, _ = map_object("mapgen.json")
        basement, _ = map_object("basement_mapgen.json")
        roof, _ = map_object("roof_mapgen.json")

        surface_down = {(x % 24, y % 24) for x, y in terrain_points(surface, "t_stairs_down")}
        surface_up = {(x % 24, y % 24) for x, y in terrain_points(surface, "t_stairs_up")}
        basement_up = {(x % 24, y % 24) for x, y in terrain_points(basement, "t_stairs_up")}
        roof_down = {(x % 24, y % 24) for x, y in terrain_points(roof, "t_stairs_down")}

        self.assertEqual(surface_down, basement_up)
        self.assertEqual(surface_up, roof_down)
        self.assertEqual(surface_down, {(14, 15)})
        self.assertEqual(surface_up, {(16, 15)})

    def test_kx91_footprints_fit_the_flight_deck_for_every_stage(self):
        roof, roof_matrix = map_object("roof_mapgen.json")
        vehicles = {entry["id"]: entry for entry in load_json("vehicles.json")}
        project = load_json("kx91_project.json")
        ownership = load_json("kx91_ownership.json")

        initial = next(
            entry for entry in roof["place_vehicles"]
            if entry["vehicle"] == "axiom_kx91_dormant"
        )

        def check_vehicle(vehicle_id, base_x, base_y, local_only=False):
            vehicle = vehicles[vehicle_id]
            for cell in vehicle.get("parts", []):
                local_x = base_x + cell["x"]
                local_y = base_y + cell["y"]
                if local_only:
                    self.assertTrue(
                        0 <= local_x < 24 and 0 <= local_y < 24,
                        f"{vehicle_id}: footprint escapes update-mapgen OMT at {(local_x, local_y)}",
                    )
                else:
                    self.assertTrue(
                        0 <= local_x < len(roof["rows"][0])
                        and 0 <= local_y < len(roof["rows"]),
                        f"{vehicle_id}: footprint escapes roof map at {(local_x, local_y)}",
                    )
                    terrain = terrain_at(roof, local_x, local_y)
                    self.assertFalse(
                        is_blocking(terrain),
                        f"{vehicle_id}: footprint overlaps {terrain} at {(local_x, local_y)}",
                    )

        check_vehicle(
            initial["vehicle"],
            initial["x"],
            initial["y"],
            local_only=False,
        )

        flight_origin = find_omt_origin(roof_matrix, "axiom_7_roof_s")
        updates = [
            entry
            for entry in project + ownership
            if entry.get("type") == "mapgen" and entry.get("update_mapgen_id")
        ]
        self.assertEqual(len(updates), 6)
        for update in updates:
            placements = update["object"].get("place_vehicles", [])
            self.assertEqual(
                len(placements),
                1,
                f"{update['update_mapgen_id']}: expected one KX-91 replacement",
            )
            placement = placements[0]
            check_vehicle(
                placement["vehicle"],
                placement["x"],
                placement["y"],
                local_only=True,
            )
            vehicle = vehicles[placement["vehicle"]]
            for cell in vehicle.get("parts", []):
                global_x = flight_origin[0] + placement["x"] + cell["x"]
                global_y = flight_origin[1] + placement["y"] + cell["y"]
                terrain = terrain_at(roof, global_x, global_y)
                self.assertFalse(
                    is_blocking(terrain),
                    (
                        f"{update['update_mapgen_id']}: {placement['vehicle']} "
                        f"overlaps {terrain} at {(global_x, global_y)}"
                    ),
                )

    def test_kx91_state_transitions_have_matching_mapgen_updates(self):
        project = load_json("kx91_project.json")
        ownership = load_json("kx91_ownership.json")
        objects = project + ownership
        missions = {
            entry["id"]: entry
            for entry in objects
            if entry.get("type") == "mission_definition"
        }
        defined_updates = {
            entry["update_mapgen_id"]
            for entry in objects
            if entry.get("type") == "mapgen" and entry.get("update_mapgen_id")
        }

        expected = {
            "MISSION_AXIOM_KX91_DIAGNOSTIC": (
                "axiom_kx91_stage_diag",
                "AXIOM_KX91_SWAP_DORMANT",
            ),
            "MISSION_AXIOM_KX91_POWER": (
                "axiom_kx91_stage_power",
                "AXIOM_KX91_SWAP_POWERED",
            ),
            "MISSION_AXIOM_KX91_NAVIGATION": (
                "axiom_kx91_stage_nav",
                "AXIOM_KX91_SWAP_AVIONICS",
            ),
            "MISSION_AXIOM_KX91_SECURITY_VALIDATION": (
                "axiom_kx91_stage_security",
                "AXIOM_KX91_SWAP_WEAPONS_READY",
            ),
            "MISSION_AXIOM_KX91_FINAL_INTEGRATION": (
                "axiom_kx91_restored",
                "AXIOM_KX91_SWAP_OPERATIONAL_AXIOM",
            ),
            "MISSION_AXIOM_KX91_CUSTODY": (
                "axiom_kx91_owned",
                "AXIOM_KX91_SWAP_OPERATIONAL_PLAYER",
            ),
        }

        for mission_id, (state_var, update_id) in expected.items():
            mission = missions[mission_id]
            vars_added = set(values_for_key(mission, "u_add_var"))
            updates_used = set(values_for_key(mission, "mapgen_update"))
            self.assertIn(state_var, vars_added, mission_id)
            self.assertIn(update_id, updates_used, mission_id)
            self.assertIn(update_id, defined_updates, mission_id)

    def test_kx91_offer_chain_is_gated_by_previous_state(self):
        objects = (
            load_json("kx91_project.json")
            + load_json("kx91_ownership.json")
            + load_json("kx91_operations.json")
        )
        eocs = {
            entry["id"]: entry
            for entry in objects
            if entry.get("type") == "effect_on_condition"
        }
        gates = {
            "EOC_AXIOM_KX91_OFFER_POWER": "axiom_kx91_stage_diag",
            "EOC_AXIOM_KX91_OFFER_NAV": "axiom_kx91_stage_power",
            "EOC_AXIOM_KX91_OFFER_SECURITY": "axiom_kx91_stage_nav",
            "EOC_AXIOM_KX91_OFFER_INTEGRATION": "axiom_kx91_stage_security",
            "EOC_AXIOM_KX91_OFFER_CUSTODY": "axiom_kx91_restored",
            "EOC_AXIOM_KX91_OP_OFFER_LONG_REACH": "axiom_kx91_owned",
            "EOC_AXIOM_KX91_OP_OFFER_CORRIDOR": "axiom_kx91_op1",
            "EOC_AXIOM_KX91_OP_OFFER_TELEMETRY": "axiom_kx91_op2",
            "EOC_AXIOM_KX91_OP_OFFER_RECOVERY": "axiom_kx91_op3",
        }
        for eoc_id, required_var in gates.items():
            condition = json.dumps(eocs[eoc_id].get("condition"), sort_keys=True)
            self.assertIn(required_var, condition, eoc_id)

    def test_every_offer_eoc_targets_a_real_mission_and_is_wired_to_npcs(self):
        files = (
            "contracts.json",
            "kx91_project.json",
            "kx91_ownership.json",
            "kx91_operations.json",
        )
        objects = [entry for name in files for entry in load_json(name)]
        missions = {
            entry["id"]
            for entry in objects + load_json("missions.json")
            if entry.get("type") == "mission_definition"
        }
        npc_text = json.dumps(load_json("npcs.json"), sort_keys=True)
        offers = [
            entry
            for entry in objects
            if entry.get("type") == "effect_on_condition"
            and "OFFER" in entry.get("id", "")
        ]
        self.assertTrue(offers)
        for offer in offers:
            targets = values_for_key(offer.get("effect"), "offer_mission")
            self.assertEqual(len(targets), 1, offer["id"])
            self.assertIn(targets[0], missions, offer["id"])
            self.assertIn(offer["id"], npc_text, offer["id"])

    def test_access_cards_use_current_item_fields_and_safe_density(self):
        items = {
            entry["id"]: entry
            for entry in load_json("items.json")
            if entry.get("id", "").startswith("axiom_card_")
        }
        self.assertEqual(
            set(items),
            {
                "axiom_card_contractor",
                "axiom_card_specialist",
                "axiom_card_prototype",
            },
        )
        for item_id, item in items.items():
            with self.subTest(item=item_id):
                self.assertEqual(item["weight"], "6 g")
                self.assertEqual(item["volume"], "6 ml")
                self.assertNotIn("to_hit", item)

    def test_security_bot_does_not_declare_one_way_ecology_wars(self):
        faction = next(
            entry
            for entry in load_json("robots.json")
            if entry.get("type") == "MONSTER_FACTION"
            and entry.get("name") == "axiom_security_bot"
        )
        self.assertNotIn("fungus", faction.get("hate", []))
        self.assertNotIn("triffid", faction.get("hate", []))
        self.assertEqual(
            set(faction.get("hate", [])),
            {"zombie", "zombie_aquatic", "nether"},
        )

    def test_security_character_events_cover_every_axiom_level(self):
        facility_ids = {
            entry["id"] for entry in load_json("overmap_terrain.json")
            if entry.get("type") == "overmap_terrain"
        }
        security = {
            entry["id"]: entry
            for entry in load_json("security_system.json")
            if entry.get("type") == "effect_on_condition"
        }
        event_ids = (
            "EOC_AXIOM_CHARACTER_MELEE_ATTACKS_CHARACTER",
            "EOC_AXIOM_CHARACTER_RANGED_ATTACKS_CHARACTER",
            "EOC_AXIOM_CHARACTER_KILLS_CHARACTER",
            "EOC_AXIOM_SECURITY_REARM",
        )
        for event_id in event_ids:
            covered = set(values_for_key(security[event_id].get("condition"), "u_at_om_location"))
            self.assertEqual(covered, facility_ids, event_id)

    def test_airframe_alarm_respects_temporary_and_player_authorization(self):
        security = {
            entry["id"]: entry
            for entry in load_json("security_system.json")
            if entry.get("type") == "effect_on_condition"
        }
        intrusion = security["EOC_AXIOM_AIRFRAME_INTRUSION"]
        condition = json.dumps(intrusion["condition"], sort_keys=True)
        self.assertIn("axiom_kx91_service_authorized", condition)
        self.assertIn("axiom_kx91_operator_authorized", condition)
        self.assertIn("axiom_security_hostile", condition)
        self.assertIn(
            "EOC_AXIOM_SECURITY_ALARM",
            values_for_key(intrusion.get("effect"), "run_eocs"),
        )

    def test_security_alarm_targets_only_axiom_security_assets(self):
        security = {
            entry["id"]: entry
            for entry in load_json("security_system.json")
            if entry.get("type") == "effect_on_condition"
        }
        alarm = security["EOC_AXIOM_SECURITY_ALARM"]
        target_sets = values_for_key(alarm.get("effect"), "mtype_ids")
        self.assertEqual(len(target_sets), 1)
        self.assertEqual(
            set(target_sets[0]),
            {"mon_axiom_patrol_sentry", "mon_axiom_security_turret"},
        )

    def test_manifest_and_modinfo_versions_match(self):
        manifest = json.loads(
            (AXIOM / "manifest.json").read_text(encoding="utf-8-sig")
        )
        modinfo = load_json("modinfo.json")
        info = next(entry for entry in modinfo if entry.get("type") == "MOD_INFO")
        self.assertEqual(manifest["variants"][-1]["version"], info["version"])


if __name__ == "__main__":
    unittest.main()
