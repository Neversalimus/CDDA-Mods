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
        for part_id in ("tread1", "tread2", "tread3"):
            with self.subTest(part=part_id):
                part = next(
                    obj
                    for _, obj in objects_under(root)
                    if obj.get("type") == "vehicle_part" and obj.get("id") == part_id
                )
                self.assertIn("movement", part.get("categories", []))

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
