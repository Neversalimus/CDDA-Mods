import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def json_files(root):
    return sorted(root.rglob("*.json"))


def objects_under(root):
    for path in json_files(root):
        data = read_json(path)
        if isinstance(data, list):
            for obj in data:
                if isinstance(obj, dict):
                    yield path, obj
        elif isinstance(data, dict):
            yield path, data


class ExhaustiveModInvariantTests(unittest.TestCase):
    def test_secronom_broken_robot_targets_exist(self):
        root = ROOT / "mods" / "secronom" / "content"
        objects = list(objects_under(root))
        item_ids = {
            obj["id"]
            for _, obj in objects
            if obj.get("type") == "ITEM" and obj.get("id")
        }
        wanted = {
            "mon_bot_secroinforcer": "broken_bot_secroinforcer",
            "mon_bot_secroshocker": "broken_bot_secroshocker",
            "mon_bot_secroriflewalker": "broken_bot_secroriflewalker",
            "mon_bot_secrolauncher": "broken_bot_secrolauncher",
        }
        monsters = {
            obj["id"]: obj
            for _, obj in objects
            if obj.get("type") == "MONSTER" and obj.get("id") in wanted
        }
        self.assertEqual(set(monsters), set(wanted))
        for monster_id, broken_id in wanted.items():
            with self.subTest(monster=monster_id):
                self.assertEqual(monsters[monster_id].get("broken_itype"), broken_id)
                self.assertIn(broken_id, item_ids)

    def test_secronom_current_density_and_detachable_gun_metadata(self):
        root = ROOT / "mods" / "secronom" / "content"
        objects = {
            obj["id"]: obj
            for _, obj in objects_under(root)
            if isinstance(obj.get("id"), str)
        }
        self.assertEqual(objects["corpse_saddler_used"].get("volume"), "43 L")
        self.assertEqual(objects["secro_fweaverfood"].get("volume"), "750 ml")

        expected_magazines = {
            "kacc": "belt223",
            "xm556": "belt223",
            "xm8": "stanag30",
        }
        for gun_id, default_magazine in expected_magazines.items():
            with self.subTest(gun=gun_id):
                gun = objects[gun_id]
                pocket = gun["pocket_data"][0]
                self.assertIsNone(pocket.get("id"))
                self.assertEqual(
                    pocket.get("default_magazine"),
                    default_magazine,
                )
                self.assertNotIn("firing_requirements", gun)
                self.assertIn("NO_TURRET", gun.get("flags", []))
        self.assertEqual(objects["xm556"].get("energy_drain"), "120 kJ")
        self.assertIn("USE_UPS", objects["xm556"].get("flags", []))

    def test_secronom_grenade_effects_use_current_flag_schema(self):
        path = (
            ROOT / "mods" / "secronom" / "content"
            / "Modification_Files" / "Monsters" / "-Essentials"
            / "secro_ammo_zombie.json"
        )
        objects = {
            obj["id"]: obj
            for obj in read_json(path)
            if isinstance(obj.get("id"), str)
        }
        for item_id in ("SSxgrenade", "SSygrenade", "SSzgrenade"):
            with self.subTest(item=item_id):
                obj = objects[item_id]
                self.assertNotIn("CUSTOM_EXPLOSION", obj.get("effects", []))
                self.assertNotIn("NEVER_MISFIRES", obj.get("effects", []))
                self.assertIn("CUSTOM_EXPLOSION", obj.get("flags", []))
                self.assertIn("NO_MANUAL_ACTIVATION", obj.get("flags", []))
                self.assertEqual(obj.get("use_action", {}).get("type"), "explosion")
                self.assertNotIn("target", obj.get("use_action", {}))

    def test_secronom_extends_vanilla_factions_instead_of_replacing_them(self):
        factions = {
            obj["name"]: obj
            for obj in read_json(
                ROOT / "mods" / "secronom" / "content"
                / "Modification_Files" / "Monsters" / "-Essentials"
                / "secro_faction.json"
            )
            if obj.get("type") == "MONSTER_FACTION"
        }
        for name in (
            "human", "animal", "insect", "bot", "zombie",
            "nether", "plant", "science", "small_animal",
        ):
            with self.subTest(faction=name):
                self.assertEqual(factions[name].get("copy-from"), name)

        self.assertNotIn("blob", factions)
        self.assertNotIn("blob", factions["fleshweaver"].get("neutral", []))
        self.assertIn(
            "fleshweaver",
            factions["human"]["extend"]["friendly"],
        )
        self.assertIn(
            "secro_defense_bot",
            factions["human"]["extend"]["friendly"],
        )
        self.assertIn(
            "secro_defense_bot",
            factions["animal"]["extend"]["neutral"],
        )
        self.assertIn(
            "fleshweaver",
            factions["zombie"]["extend"]["neutral"],
        )
        self.assertIn(
            "zombie_weaver",
            factions["zombie"]["extend"]["hate"],
        )
        self.assertIn("cult", factions["zombie_weaver"].get("hate", []))
        self.assertIn(
            "saddler",
            factions["bot"]["extend"]["neutral"],
        )
        self.assertIn(
            "carrion2",
            factions["carrion"]["friendly"],
        )
        self.assertIn(
            "carrion",
            factions["carrion2"]["friendly"],
        )
        self.assertIn(
            "secro_flesh",
            factions["secro_flesh2"]["friendly"],
        )
        self.assertNotIn("by_mood", factions["secro_flesh2"])

    def test_secronom_plus_wip_and_density_migrations(self):
        root = ROOT / "mods" / "secronom_plus" / "content"

        ammo = {
            obj["id"]: obj
            for obj in read_json(
                root / "Modification Files" / "Items" / "secro_ammo_mags.json"
            )
            if isinstance(obj.get("id"), str)
        }
        self.assertEqual(ammo["secro_flesh"].get("stack_size"), 1)
        self.assertEqual(ammo["secro_flesh_large"].get("stack_size"), 1)
        self.assertNotIn("NEVER_MISFIRES", ammo["secro_flesh"].get("effects", []))

        materials = {
            obj["id"]: obj
            for obj in read_json(
                root / "Modification Files" / "Items" / "-Essentials"
                / "secro_mat.json"
            )
            if isinstance(obj.get("id"), str)
        }
        self.assertEqual(materials["secro_flesh_fuel"].get("density"), 1.2)
        self.assertEqual(materials["secro_flesh_reinforced"].get("density"), 3.52)
        self.assertEqual(materials["secro_flesh_artificial"].get("density"), 1.6)

        dna = read_json(
            root / "Modification Files" / "Items" / "secro_dna_cc.json"
        )
        cores = [obj for obj in dna if obj.get("category") == "secro_ccore"]
        self.assertGreaterEqual(len(cores), 6)
        for core in cores:
            with self.subTest(core=core.get("id")):
                self.assertEqual(core.get("material"), ["secro_flesh_reinforced"])

        self.assertEqual(
            next(obj for obj in dna if obj.get("id") == "secro_flesh_splicer").get("material"),
            ["secro_flesh_reinforced", "bone"],
        )
        for sample_id in (
            "secro_flesh_splicer_zombie_blade_dna",
            "secro_flesh_splicer_zombie_WALKINGPOTATO_dna",
            "secro_flesh_splicer_zombie_mouth_dna",
            "secro_flesh_splicer_zombie_tendril_dna",
            "secro_flesh_splicer_zombie_titan_dna",
            "secro_flesh_splicer_zombie_unify_dna",
        ):
            with self.subTest(dna_sample=sample_id):
                self.assertEqual(
                    next(obj for obj in dna if obj.get("id") == sample_id).get("volume"),
                    "200 ml",
                )

        misc_expected = {
            "secro_flesh_amalgam_transmitter": "150 ml",
            "secro_recipe_flesh": "1350 ml",
            "broken_secro_fleshmech_unlink": "560 L",
            "broken_secro_fleshmech": "560 L",
            "secro_id_fvvault": "6 ml",
            "secro_id_frrom": "6 ml",
            "secro_sample_shifter": "200 ml",
            "secro_power_armor_module_core": "300 ml",
            "secro_power_armor_module_vessel": "1100 ml",
            "secro_power_armor_module_vessel_act": "1100 ml",
            "secro_fleshmech_gun_spikes": "16500 ml",
        }
        all_objects = {
            obj["id"]: obj
            for _, obj in objects_under(root)
            if isinstance(obj.get("id"), str)
        }
        for item_id, expected_volume in misc_expected.items():
            with self.subTest(density_item=item_id):
                self.assertEqual(all_objects[item_id].get("volume"), expected_volume)

        mutation = read_json(
            root / "Modification Files" / "Others" / "secro_mutation.json"
        )
        category = next(
            obj for obj in mutation
            if obj.get("type") == "mutation_category"
            and obj.get("id") == "SECRONOM_EX"
        )
        self.assertTrue(category.get("wip"))

    def test_secronom_plus_uses_only_current_ammo_effects(self):
        ammo = read_json(
            ROOT / "mods" / "secronom_plus" / "content"
            / "Modification Files" / "Items" / "secro_ammo_mags.json"
        )
        bone = next(obj for obj in ammo if obj.get("id") == "secro_flesh_boneneedle")
        effects = bone.get("effects", [])
        self.assertIn("NOGIB", effects)
        self.assertIn("NON_FOULING", effects)
        self.assertNotIn("NEVER_MISFIRES", effects)

    def test_tankmod_exhaustive_legacy_fields_are_removed(self):
        root = ROOT / "mods" / "tankmod" / "content"
        item_objects = {
            obj["id"]: obj
            for _, obj in objects_under(root)
            if obj.get("type") == "ITEM" and obj.get("id")
        }
        legacy_to_hit = {
            "25mm_autocannon",
            "25mm_autocannon_sawn",
            "25mm_cannon_crude",
            "tank_gun_manual",
            "tank_gun_auto",
            "tank_gun_crude",
            "tank_gun_manual_105mm",
            "tank_gun_crude_105mm",
            "howitzer_gun",
            "howitzer_gun_crude",
            "atgm_turret",
            "broken_uafv_xm246e1",
            "tread1",
            "tread2",
            "tread3",
        }
        for item_id in legacy_to_hit:
            with self.subTest(item=item_id):
                self.assertIn(item_id, item_objects)
                self.assertNotIn("to_hit", item_objects[item_id])
        self.assertEqual(item_objects["broken_uafv_xm246e1"].get("weight"), "4500 kg")
        self.assertEqual(item_objects["broken_uafv_xm246e1"].get("volume"), "1000 L")
        self.assertEqual(item_objects["electric_primer_120mm"].get("weight"), "45 g")
        self.assertEqual(item_objects["primer_155mm"].get("weight"), "51 g")

        ammo_effects = read_json(root / "ammo_effects.json")
        custom_explosion = [
            obj for obj in ammo_effects
            if obj.get("type") == "ammo_effect"
            and obj.get("id") == "CUSTOM_EXPLOSION"
        ]
        self.assertEqual(len(custom_explosion), 1)

        expected_volumes = {
            "25mm_hei": "3300 ml",
            "25mm_apds": "3300 ml",
            "25mm_autocannon_sawn": "12 L",
            "tank_gun_manual": "400 L",
            "tank_gun_auto": "425 L",
            "tank_gun_crude": "125 L",
            "tank_gun_manual_105mm": "190 L",
            "tank_gun_crude_105mm": "95 L",
            "howitzer_gun": "550 L",
            "howitzer_gun_crude": "190 L",
            "tank_gun_auto_monster": "425 L",
        }
        for item_id, volume in expected_volumes.items():
            with self.subTest(item=item_id):
                self.assertEqual(item_objects[item_id].get("volume"), volume)

        uncraft = {
            obj["result"]: obj
            for obj in read_json(root / "uncraft.json")
            if obj.get("type") == "uncraft" and obj.get("result")
        }
        expected_salvage = {
            "25mm_hei": {"scrap": 6},
            "25mm_apds": {"scrap": 3, "steel_chunk": 1},
            "105mm_heat": {"scrap": 20, "steel_lump": 7},
            "105mm_ap": {"scrap": 33, "steel_lump": 15},
            "120mm_usable_heat": {"scrap": 21, "steel_lump": 4},
            "120mm_usable_ap": {"scrap": 37, "steel_lump": 22},
            "155mm_heat": {"scrap": 26, "steel_lump": 27},
            "155mm_frag": {"scrap": 30, "steel_lump": 29},
        }
        for ammo_id, expected in expected_salvage.items():
            with self.subTest(uncraft=ammo_id):
                actual = {}
                for group in uncraft[ammo_id].get("components", []):
                    for component in group:
                        if component[0] in ("scrap", "steel_chunk", "steel_lump", "uranium"):
                            actual[component[0]] = component[1]
                self.assertEqual(actual, expected)
                self.assertNotIn("uranium", actual)

        for part_id in ("tread1", "tread2", "tread3"):
            with self.subTest(part=part_id):
                part = next(
                    obj
                    for _, obj in objects_under(root)
                    if obj.get("type") == "vehicle_part" and obj.get("id") == part_id
                )
                self.assertIn("movement", part.get("categories", []))

    def test_aftershock_prime_safe_exhaustive_fixes(self):
        root = ROOT / "mods" / "aftershock_prime" / "content"
        objects = list(objects_under(root))
        item_objects = {
            obj["id"]: obj
            for _, obj in objects
            if obj.get("type") == "ITEM" and obj.get("id")
        }
        legacy_to_hit = {
            "broken_afs_eyebot", "broken_shock_mine", "broken_zenit",
            "broken_afs_copbot", "broken_afs_riotbot", "afs_gene_disp",
            "afs_gene_template", "afs_reactor_unstable",
            "enforcer_master_keycard", "mercurial_master_keycard",
            "bot_laserturret_interior", "afs_bot_eyebot", "afs_bot_copbot",
            "afs_bot_riotbot", "afs_mil_ship_plate", "minireactor",
            "afs_antitank_railgun", "afs_mine_shocker",
        }
        for item_id in legacy_to_hit:
            with self.subTest(item=item_id):
                self.assertIn(item_id, item_objects)
                self.assertNotIn("to_hit", item_objects[item_id])

        firmware = item_objects["firmware_overpressure"]
        self.assertEqual(firmware.get("longest_side"), "25 mm")

        for card_id in (
            "crashing_ship_locker_card", "crashing_ship_armory_card",
            "crashing_ship_exobay_card", "tskbem_master_keycard",
            "enforcer_master_keycard", "mercurial_master_keycard",
        ):
            with self.subTest(card=card_id):
                self.assertEqual(item_objects[card_id].get("weight"), "6 g")
                self.assertEqual(item_objects[card_id].get("volume"), "6 ml")

        monsters = {
            obj["id"]: obj
            for _, obj in objects
            if obj.get("type") == "MONSTER" and obj.get("id")
        }
        self.assertEqual(
            monsters["mon_uica_irradiant"].get("broken_itype"),
            "broken_wraitheon_irradiant",
        )
        self.assertEqual(
            monsters["mon_uica_tankbot"].get("broken_itype"),
            "broken_tankbot",
        )
        self.assertEqual(
            monsters["mon_light_hack"].get("broken_itype"),
            "broken_manhack",
        )

    def test_aftershock_prime_extends_core_monster_factions(self):
        factions = {
            obj["name"]: obj
            for obj in read_json(
                ROOT / "mods" / "aftershock_prime" / "content"
                / "monsters" / "monster_faction.json"
            )
            if obj.get("type") == "MONSTER_FACTION"
        }
        for name in ("zombie", "herbivore", "human", "wolf", "bot", "player"):
            with self.subTest(faction=name):
                self.assertEqual(factions[name].get("copy-from"), name)

        self.assertNotIn("neutral", factions["zombie"])
        self.assertIn("moxie", factions["zombie"]["extend"]["neutral"])
        self.assertIn("reavers", factions["zombie"]["extend"]["hate"])
        self.assertNotIn("neutral", factions["human"])
        self.assertIn("bio_machine", factions["human"]["extend"]["neutral"])
        self.assertIn("reavers", factions["human"]["extend"]["by_mood"])
        self.assertIn("reavers", factions["player"]["extend"]["hate"])
        self.assertIn("alien_predator", factions["bot"]["extend"]["neutral"])
        self.assertIn("WraitheonRobotics", factions["reavers"]["hate"])
        self.assertIn("rampant_machine", factions["reavers"]["hate"])
        self.assertIn("rampant_machine", factions["bio_machine"]["hate"])

    def test_aftershock_prime_uses_current_acid_and_faction_semantics(self):
        bioparts = read_json(
            ROOT / "mods" / "aftershock_prime" / "content" / "items"
            / "bioparts.json"
        )
        blaster = next(obj for obj in bioparts if obj.get("id") == "vibrating_blaster")
        self.assertEqual(blaster.get("ammo_effects"), ["ACIDBOMB"])

        factions = {
            obj["name"]: obj
            for obj in read_json(
                ROOT / "mods" / "aftershock_prime" / "content" / "monsters"
                / "monster_faction.json"
            )
            if obj.get("type") == "MONSTER_FACTION"
        }
        self.assertIn("herbivore_domestic", factions["hevel"].get("neutral", []))
        self.assertIn("cop_bot", factions["alien_predator"].get("neutral", []))
        self.assertIn("defense_bot", factions["alien_predator"].get("neutral", []))
        self.assertNotIn("cop_bot", factions["alien_predator"].get("by_mood", []))
        self.assertNotIn("defense_bot", factions["alien_predator"].get("by_mood", []))
        self.assertIn("reavers", factions["robofac"]["extend"]["neutral"])
        self.assertIn("reavers", factions["robofac_spy"]["extend"]["neutral"])

    def test_aftershock_prime_restores_semantic_mutation_overlays(self):
        overlay_path = (
            ROOT / "mods" / "aftershock_prime" / "content" / "mutations"
            / "prime_vanilla_mutation_extensions.json"
        )
        objects = read_json(overlay_path)
        overlays = [
            obj for obj in objects
            if obj.get("type") == "mutation"
            and obj.get("copy-from") == obj.get("id")
        ]
        self.assertEqual(len(overlays), 46)
        overlay_ids = {obj["id"] for obj in overlays}
        for trait_id in (
            "THICKSKIN", "LIGHTFUR", "HUGE_OK", "LEG_TENTACLES",
            "WINGS_STUB", "DISRESISTANT", "DISIMMUNE", "INFRESIST",
        ):
            with self.subTest(trait=trait_id):
                self.assertIn(trait_id, overlay_ids)

        dummy = next(
            obj for obj in objects
            if obj.get("id") == "HUMAN_AFTERSHOCK_PRIME"
        )
        self.assertTrue(dummy.get("dummy"))
        self.assertFalse(dummy.get("player_display"))
        self.assertEqual(dummy.get("category"), ["HUMAN"])
        expected_cancels = {
            "AFS_THROWING_STRENGTH", "AFS_STRONG", "AFS_GOOD_HEAD",
            "AFS_WAR_BUILD", "AFS_COMBAT_DRUG_PRODUCTION",
            "AFS_FAST_BLOOD_PRODUCTION", "AFS_REDUNDANT_ORGANS",
            "MIGO_RAD_ADAPTION", "MIGO_THRESH_RAD_FLUSH", "MIGO_BREATHE",
            "HAULER", "TRUMPET", "AFS_NIGHTVISION", "AFS_UNCARING",
            "AFS_QUICK", "AFS_INFIMMUNE",
        }
        self.assertEqual(set(dummy.get("cancels", [])), expected_cancels)

    def test_aftershock_builder_preserves_self_mutation_overlays(self):
        builder = (
            ROOT / "tools" / "recovery" / "Aftershock.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn("kept_semantic_overlay", builder)
        self.assertIn("[string]$o.'copy-from' -eq $id", builder)
        self.assertIn("[string]$_.'copy-from' -eq $id", builder)

    def test_blazemod_exact_density_volume_repairs_are_stable(self):
        root = ROOT / "mods" / "blazemod" / "content"
        objects = {
            obj["id"]: obj
            for _, obj in objects_under(root)
            if obj.get("type") == "ITEM"
            and isinstance(obj.get("id"), str)
        }
        expected = {
            "bfeedfuel": "400 ml", "bfeed": "1250 ml",
            "canbomb": "550 ml", "canbomb2": "11250 ml",
            "canbombfire": "550 ml", "canbombfire2": "1 L",
            "canbombfrag": "700 ml", "h_projectile": "8 L",
            "harpoon": "17500 ml", "hbolt_boom": "2750 ml",
            "hbolt_boom2": "2750 ml", "hbolt_fire": "2750 ml",
            "hbolt_fire2": "5 L", "hbolt_frag": "3500 ml",
            "hbolt_metal": "2750 ml", "hbolt_nuke": "8 L",
            "hbolt_wood": "10 L", "pebble_mk3": "600 ml",
            "pebble_mk4": "600 ml", "ripdisk": "4 L",
            "slauncher": "4250 ml", "biter": "17 L",
            "clutter": "6 L", "freezie": "20 L", "fuzzle": "21 L",
            "horror": "23 L", "inkie": "14500 ml", "meltie": "14500 ml",
            "razorqueen": "23 L", "sharp": "14500 ml",
            "gelrazor": "14 L", "sparkie": "13500 ml",
            "stickie": "11 L", "torchie": "15500 ml", "voideater": "16500 ml",
            "diamondnova": "6 L", "vortexrifle": "2750 ml",
            "gray_tank": "18 L", "oozle_tank": "15500 ml",
            "bitergrow": "11500 ml", "cluttergrow": "5500 ml",
            "freeziegrow": "14500 ml", "frostie": "6 L",
            "frostiegrow": "3500 ml", "fuzzlegrow": "17 L",
            "gloople": "6500 ml", "gloople_act": "8500 ml",
            "glooplegrow": "3500 ml", "glowiegrow": "3500 ml",
            "gray": "18 L", "gray_act": "18500 ml",
            "horrorgrow": "19 L", "inkiegrow": "11500 ml",
            "meltiegrow": "11500 ml", "oozle_act": "15500 ml",
            "oozlegrow": "12 L", "queengrow": "24 L",
            "razorqueengrow": "17 L", "sharpgrow": "10500 ml",
            "sicklegrow": "11500 ml", "sparkiegrow": "10500 ml",
            "stickiegrow": "8 L", "torchiegrow": "11500 ml",
            "voideatergrow": "11500 ml", "solar_array": "21 L",
            "solar_array_v2": "26 L", "frostie_hull": "6 L",
            "frostie_wheel": "6 L", "gloople_wheel": "28 L",
            "gray_wheel": "50 L", "grinder": "107 L", "oozle_wheel": "47 L",
        }
        self.assertEqual(len(expected), 72)
        for item_id, volume in expected.items():
            with self.subTest(item=item_id):
                self.assertIn(item_id, objects)
                self.assertEqual(objects[item_id].get("volume"), volume)

    def test_blazemod_uncraft_mass_repairs_preserve_intent(self):
        root = ROOT / "mods" / "blazemod" / "content"

        ammo_recipes = {
            obj["result"]: obj
            for obj in read_json(root / "recipes" / "blaze_ammo_recipes.json")
            if obj.get("result")
        }
        lead = ammo_recipes["lead_ball"]["components"][0][0]
        self.assertEqual(lead, ["lead", 80])

        gun_recipes = {
            obj["result"]: obj
            for obj in read_json(root / "recipes" / "blaze_gun_recipes.json")
            if obj.get("result")
        }
        coil = {
            comp[0]: comp[1]
            for group in gun_recipes["blaze_coilgun"]["components"]
            for comp in group
        }
        self.assertEqual(coil["pipe"], 4)

        weapon_recipes = {
            obj["result"]: obj
            for obj in read_json(root / "recipes" / "blaze_weapons_recipes.json")
            if obj.get("result")
        }
        rifle = {
            comp[0]: comp[1]
            for group in weapon_recipes["rifle_308"]["components"]
            for comp in group
        }
        self.assertEqual(
            rifle,
            {
                "pipe": 1,
                "spring_small": 1,
                "lc_steel_chunk": 1,
                "plank_short": 1,
                "scrap": 3,
            },
        )

        blob_recipes = {
            obj["result"]: obj
            for obj in read_json(root / "recipes" / "blob_recipes.json")
            if obj.get("result")
        }
        expected_water = {
            "frostie_wheel": 1,
            "gray_wheel": 137,
            "oozle_wheel": 136,
            "frostie_hull": 1,
        }
        for result, count in expected_water.items():
            with self.subTest(recipe=result):
                water = [
                    comp
                    for group in blob_recipes[result]["components"]
                    for comp in group
                    if comp[0] == "water"
                ]
                self.assertEqual(water, [["water", count]])

        split_pairs = {
            "biter": ("bitergrow", "9166 g"),
            "clutter": ("cluttergrow", "3626 g"),
            "meltie": ("meltiegrow", "7777 g"),
            "frostie": ("frostiegrow", "3056 g"),
            "gray": ("graygrow", "9560 g"),
            "oozle": ("oozlegrow", "8131 g"),
            "glowie": ("glowiegrow", "2566 g"),
        }
        tools = {
            obj["id"]: obj
            for obj in read_json(root / "items" / "tools" / "blob_tools.json")
            if obj.get("id")
        }
        for adult, (grow, weight) in split_pairs.items():
            with self.subTest(adult=adult):
                components = blob_recipes[adult]["components"]
                self.assertEqual(components, [[[grow, 2]]])
                self.assertEqual(tools[grow]["weight"], weight)

    def test_blazemod_exhaustive_vehicle_metadata_is_current(self):
        root = ROOT / "mods" / "blazemod" / "content"
        flagged_ids = {
            "blob_aisle_lights", "blob_directed_floodlight", "blob_floodlight",
            "blob_headlight", "blob_turret_mount", "blob_wide_headlight",
            "frostie_boat_hull", "frostie_ram", "frostie_trunk", "frostie_wall",
            "frostie_wheel", "frostie_wheel_sea", "frostie_windshield",
            "gloople_amalgam", "gloople_belt", "gloople_plate", "gloople_roof",
            "gloople_seat", "gloople_tank", "gloople_tank_large",
            "gloople_trunk", "gloople_trunk_u", "gloople_wheel",
            "gloopledoor", "gloopledoor_opaque", "gloopletread",
            "gray_amalgam", "gray_belt", "gray_plate", "gray_roof",
            "gray_seat", "gray_tank", "gray_tank_large", "gray_trunk",
            "gray_trunk_u", "gray_wheel", "graydoor", "graydoor_opaque",
            "graytread", "grinder", "mounted_biter", "mounted_clutter",
            "mounted_freezie", "mounted_fuzzle", "mounted_gelrazor",
            "mounted_horror", "mounted_inkie", "mounted_meltie",
            "mounted_razorqueen", "mounted_sharp", "mounted_sparkie",
            "mounted_spouterqueen", "mounted_stickie", "mounted_torchie",
            "mounted_voideater", "oozle_amalgam", "oozle_belt",
            "oozle_plate", "oozle_roof", "oozle_seat", "oozle_tank",
            "oozle_tank_large", "oozle_trunk", "oozle_trunk_u",
            "oozle_wheel", "oozledoor", "oozledoor_opaque", "oozletread",
            "plating_diamond", "queen", "stabilized_cargo_portal",
            "tread1", "tread2", "tread3", "vgen", "vgen2",
        }
        vehicle_parts = {
            obj["id"]: obj
            for _, obj in objects_under(root)
            if obj.get("type") == "vehicle_part" and obj.get("id") in flagged_ids
        }
        self.assertEqual(set(vehicle_parts), flagged_ids)
        for part_id, part in vehicle_parts.items():
            with self.subTest(part=part_id):
                self.assertTrue(part.get("categories"), part_id)

        all_vehicle_part_ids = {
            obj["id"]
            for _, obj in objects_under(root)
            if obj.get("type") == "vehicle_part" and obj.get("id")
        }
        for obsolete_part in ("m4_carbine", "mounted_ar15", "mounted_hk_ump45"):
            with self.subTest(obsolete_turret=obsolete_part):
                self.assertNotIn(obsolete_part, all_vehicle_part_ids)

        for door_id in (
            "gloopledoor", "gloopledoor_opaque",
            "graydoor", "graydoor_opaque",
            "oozledoor", "oozledoor_opaque",
        ):
            with self.subTest(door=door_id):
                flags = vehicle_parts[door_id].get("flags", [])
                self.assertIn("OPENABLE", flags)
                self.assertIn("BOARDABLE", flags)
                self.assertIn("DOOR", flags)


if __name__ == "__main__":
    unittest.main()
