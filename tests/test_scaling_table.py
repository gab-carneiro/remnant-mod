import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
sys.path.insert(0, HERE)

import rebuild_scaling
import ue422

ROW_NAMES = ["1", "2", "3", "4", "5", "6"]
SPAWN_QUANTITY = [1.0, 1.33, 1.66, 2.0, 2.33, 2.66]
SPAWN_WEIGHT = [1.0, 1.5, 1.75, 1.6, 1.6, 1.6]
ENEMY_DAMAGE = [1.0, 1.0, 1.0, 1.10, 1.20, 1.30]
DAMAGE_SCALARS = ["EnemyDamageScalar", "EliteDamageScalar", "BruteDamageScalar", "BossDamageScalar"]
UNTOUCHED_SCALARS = [
    "EnemyHealthScalar", "EliteHealthScalar", "BruteHealthScalar", "BossHealthScalar",
    "CurrencyScalar", "ExperienceScalar", "FriendlyFireDamageScalar",
]
UASSET_TAG = 0x9E2A83C1


def built(test=False):
    return rebuild_scaling.build_table(*rebuild_scaling.load_original(), test=test)


class NameHashTest(unittest.TestCase):
    def test_hash_matches_the_cooker_for_every_original_name(self):
        pkg = ue422.read_package(*rebuild_scaling.load_original())
        for name, non_case, case in pkg["names"]:
            self.assertEqual(rebuild_scaling.ue4_name_hash(name), (non_case, case), name)

    def test_every_name_in_the_built_table_has_its_real_hash(self):
        pkg = ue422.read_package(*built())
        for name, non_case, case in pkg["names"]:
            self.assertEqual((non_case, case), rebuild_scaling.ue4_name_hash(name), name)


class PackageHeaderTest(unittest.TestCase):
    def setUp(self):
        self.original = ue422.read_package(*rebuild_scaling.load_original())
        self.table = ue422.read_package(*built())

    def test_header_and_export_sizes_match_the_files(self):
        export = self.table["exports"][0]
        self.assertEqual(self.table["total_header_size"], self.table["uasset_size"])
        self.assertEqual(export["serial_offset"], self.table["total_header_size"])
        self.assertEqual(export["serial_size"], self.table["uexp_size"] - 4)
        self.assertEqual(self.table["uexp_tag"], UASSET_TAG)

    def test_bulk_data_starts_after_the_export(self):
        export = self.table["exports"][0]
        self.assertEqual(self.table["bulk_data_start_offset"], self.table["total_header_size"] + export["serial_size"])

    def test_generation_counts_follow_the_tables(self):
        self.assertEqual(self.table["generations"], [(self.table["export_count"], self.table["name_count"])])

    def test_original_names_keep_their_indices(self):
        self.assertEqual(self.table["names"][:len(self.original["names"])], self.original["names"])

    def test_preload_dependencies_still_point_to_the_imports(self):
        self.assertEqual(self.table["preload_dependencies"], self.original["preload_dependencies"])
        for index in self.table["preload_dependencies"]:
            self.assertTrue(-self.table["import_count"] <= index <= self.table["export_count"] and index != 0, index)

    def test_everything_but_names_and_sizes_survives(self):
        for key in ("imports", "depends", "asset_registry_object_count", "package_flags", "guid",
                    "package_source", "chunk_ids", "import_count", "export_count", "preload_dependency_count"):
            self.assertEqual(self.table[key], self.original[key], key)
        original_export = dict(self.original["exports"][0])
        table_export = dict(self.table["exports"][0])
        for key in ("serial_size", "serial_offset"):
            original_export.pop(key)
            table_export.pop(key)
        self.assertEqual(table_export, original_export)


class RowsTest(unittest.TestCase):
    def setUp(self):
        uasset, uexp = built()
        self.rows = ue422.read_data_table_rows(ue422.read_package(uasset, uexp), uexp)

    def test_rows_are_1_to_6(self):
        self.assertEqual(list(self.rows), ROW_NAMES)

    def test_spawn_grows_with_each_player(self):
        for name, quantity, weight in zip(ROW_NAMES, SPAWN_QUANTITY, SPAWN_WEIGHT):
            self.assertAlmostEqual(self.rows[name]["SpawnQuantityScalar"], quantity, places=5, msg=name)
            self.assertAlmostEqual(self.rows[name]["SpawnWeightScalar"], weight, places=5, msg=name)

    def test_enemy_damage_grows_from_4_players_on_every_enemy_kind(self):
        for name, damage in zip(ROW_NAMES, ENEMY_DAMAGE):
            for scalar in DAMAGE_SCALARS:
                self.assertAlmostEqual(self.rows[name][scalar], damage, places=5, msg=name + " " + scalar)

    def test_health_rewards_and_friendly_fire_stay_vanilla(self):
        for name in ROW_NAMES:
            for scalar in UNTOUCHED_SCALARS:
                self.assertAlmostEqual(self.rows[name][scalar], 1.0, places=5, msg=name + " " + scalar)

    def test_rows_1_to_3_are_untouched(self):
        uasset, uexp = rebuild_scaling.load_original()
        original = ue422.read_data_table_rows(ue422.read_package(uasset, uexp), uexp)
        for name in ("1", "2", "3"):
            self.assertEqual(self.rows[name], original[name], name)


class TestTableTest(unittest.TestCase):
    def test_solo_gets_triple_spawn_and_damage(self):
        uasset, uexp = built(test=True)
        rows = ue422.read_data_table_rows(ue422.read_package(uasset, uexp), uexp)
        self.assertAlmostEqual(rows["1"]["SpawnQuantityScalar"], 3.0, places=5)
        for scalar in DAMAGE_SCALARS:
            self.assertAlmostEqual(rows["1"][scalar], 3.0, places=5, msg=scalar)

    def test_other_rows_match_the_release_table(self):
        uasset, uexp = built(test=True)
        test_rows = ue422.read_data_table_rows(ue422.read_package(uasset, uexp), uexp)
        uasset, uexp = built()
        release_rows = ue422.read_data_table_rows(ue422.read_package(uasset, uexp), uexp)
        for name in ROW_NAMES[1:]:
            self.assertEqual(test_rows[name], release_rows[name], name)


if __name__ == "__main__":
    unittest.main()
