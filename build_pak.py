import argparse
import hashlib
import os
import struct

import rebuild_scaling

ROOT = os.path.dirname(os.path.abspath(__file__))
OUTPUT_NAME = "6player_P.pak"
TEST_OUTPUT_NAME = "6player_0_TESTE_P.pak"
MOUNT_POINT = "../../../"
TABLE_PAK_PATH = "Remnant/Content/_Core/Stats/" + rebuild_scaling.TABLE_NAME

PAK_MAGIC = 0x5A6F12E1
PAK_VERSION = 8
COMPRESSION_METHOD_NAME_LEN = 32
MAX_NUM_COMPRESSION_METHODS = 4
NO_COMPRESSION = 0
UNCOMPRESSED_ENTRY_HEADER_SIZE = 50


def _fstring(text):
    encoded = (text + "\0").encode("latin1")
    return struct.pack("<i", len(encoded)) + encoded


def _entry_record(offset, content):
    record = struct.pack("<qqqB", offset, len(content), len(content), NO_COMPRESSION)
    record += hashlib.sha1(content).digest()
    record += struct.pack("<BI", 0, 0)
    assert len(record) == UNCOMPRESSED_ENTRY_HEADER_SIZE
    return record


def _footer(index_offset, index):
    encryption_key_guid = bytes(16)
    encrypted_index = b"\0"
    compression_methods = bytes(COMPRESSION_METHOD_NAME_LEN * MAX_NUM_COMPRESSION_METHODS)
    return (encryption_key_guid + encrypted_index
            + struct.pack("<Iiqq", PAK_MAGIC, PAK_VERSION, index_offset, len(index))
            + hashlib.sha1(index).digest() + compression_methods)


def build_pak(files):
    data = bytearray()
    entries = bytearray()
    for name, content in files:
        record = _entry_record(len(data), content)
        data += record + content
        entries += _fstring(name) + record
    index = _fstring(MOUNT_POINT) + struct.pack("<i", len(files)) + bytes(entries)
    return bytes(data) + index + _footer(len(data), index)


def build_release_pak(test=False):
    uasset, uexp = rebuild_scaling.build_table(*rebuild_scaling.load_original(), test=test)
    return build_pak([(TABLE_PAK_PATH + ".uasset", uasset), (TABLE_PAK_PATH + ".uexp", uexp)])


def main():
    parser = argparse.ArgumentParser(description="Gera o PAK do mod: a DataTable de escala por jogadores (linhas 1 a 6).")
    parser.add_argument("--teste", dest="test", action="store_true",
                        help="gera %s: solo com 3x inimigos, 3x vida e 3x dano, para confirmar que o jogo carrega o PAK" % TEST_OUTPUT_NAME)
    args = parser.parse_args()
    name = TEST_OUTPUT_NAME if args.test else OUTPUT_NAME
    pak = build_release_pak(test=args.test)
    with open(os.path.join(ROOT, name), "wb") as out:
        out.write(pak)
    print("OK: %s (%d bytes)" % (name, len(pak)))


if __name__ == "__main__":
    main()
