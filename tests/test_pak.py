import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
sys.path.insert(0, HERE)

import build_pak
import rebuild_scaling
import ue422

TABLE_FILES = [
    "Remnant/Content/_Core/Stats/Stats_Scaling_NumPlayers.uasset",
    "Remnant/Content/_Core/Stats/Stats_Scaling_NumPlayers.uexp",
]
BASE_GAME_PAK = "../../../Remnant/Content/Paks/Remnant-WindowsNoEditor.pak"
MODS_DIR = "../../../Remnant/Content/Paks/~mods/"


class PakFormatTest(unittest.TestCase):
    def test_ue422_mounts_the_pak_instead_of_waiting_for_an_encryption_key(self):
        pak = build_pak.build_pak([("Remnant/Config/teste.txt", b"conteudo")])
        mounted = ue422.mount_pak(pak)
        self.assertTrue(mounted["mounted"], "montagem adiada, GUID lido: %s" % mounted.get("deferred_for_key"))

    def test_files_come_back_byte_for_byte(self):
        files = [("a/um.bin", bytes(range(256)) * 20), ("b/dois.bin", b"remnant" * 300)]
        pak = build_pak.build_pak(files)
        mounted = ue422.mount_pak(pak)
        self.assertEqual(mounted["mount_point"], "../../../")
        for name, content in files:
            self.assertEqual(ue422.read_pak_file(pak, mounted, name), content)

    def test_mod_pak_overrides_the_base_game_pak(self):
        base = ue422.pak_read_order(BASE_GAME_PAK)
        for name in (build_pak.OUTPUT_NAME, build_pak.TEST_OUTPUT_NAME):
            self.assertGreater(ue422.pak_read_order(MODS_DIR + name), base, name)


class ReleasePakTest(unittest.TestCase):
    def test_committed_pak_is_the_current_build(self):
        with open(os.path.join(ROOT, build_pak.OUTPUT_NAME), "rb") as committed:
            self.assertEqual(committed.read(), build_pak.build_release_pak())

    def test_pak_carries_only_the_scaling_table(self):
        mounted = ue422.mount_pak(build_pak.build_release_pak())
        self.assertEqual(sorted(mounted["files"]), sorted(TABLE_FILES))

    def test_pak_blocks_fit_the_engine_chunk_size(self):
        mounted = ue422.mount_pak(build_pak.build_release_pak())
        for name, entry in mounted["files"].items():
            self.assertLessEqual(entry["block_size"], 64 * 1024, name)

    def test_pak_table_is_the_built_table(self):
        self.assert_pak_has_table(build_pak.build_release_pak(), rebuild_scaling.build_table(*rebuild_scaling.load_original()))

    def test_test_pak_table_is_the_built_test_table(self):
        self.assert_pak_has_table(
            build_pak.build_release_pak(test=True),
            rebuild_scaling.build_table(*rebuild_scaling.load_original(), test=True),
        )

    def assert_pak_has_table(self, pak, table):
        mounted = ue422.mount_pak(pak)
        self.assertEqual(ue422.read_pak_file(pak, mounted, TABLE_FILES[0]), table[0])
        self.assertEqual(ue422.read_pak_file(pak, mounted, TABLE_FILES[1]), table[1])


if __name__ == "__main__":
    unittest.main()
