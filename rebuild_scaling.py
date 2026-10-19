import argparse
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.abspath(__file__))
TABLE_NAME = "Stats_Scaling_NumPlayers"
TABLE_DIR = os.path.join("Remnant", "Content", "_Core", "Stats")
ORIGINAL_DIR = os.path.join(ROOT, "original", TABLE_DIR)
OUTPUT_DIR = os.path.join(ROOT, "modified", TABLE_DIR)

BASE_PLAYERS = 3
DAMAGE_PER_EXTRA = 0.10
NEW_ROWS = {
    "5": {"SpawnQuantityScalar": 2.33, "SpawnWeightScalar": 1.60},
    "6": {"SpawnQuantityScalar": 2.66, "SpawnWeightScalar": 1.60},
}
NEW_ROW_TEMPLATE = "4"
DAMAGE_SCALARS = ("EnemyDamageScalar", "EliteDamageScalar", "BruteDamageScalar", "BossDamageScalar")
TEST_ROW = "1"
TEST_SCALE = 3.0

PACKAGE_TAG = 0x9E2A83C1
SUPPORTED_LEGACY_VERSION = -7
HEADER_OFFSET_FIELDS = (
    "gatherable_text_offset", "export_offset", "import_offset", "depends_offset",
    "soft_package_references_offset", "searchable_names_offset", "thumbnail_table_offset",
    "asset_registry_data_offset", "world_tile_info_data_offset", "preload_dependency_offset",
)
EXPORT_SERIAL_SIZE_POSITION = 28


def _legacy_crc_table():
    table = []
    for index in range(256):
        crc = index << 24
        for _ in range(8):
            crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if crc & 0x80000000 else (crc << 1) & 0xFFFFFFFF
        table.append(crc)
    return table


_LEGACY_CRC_TABLE = _legacy_crc_table()


def ue4_name_hash(name):
    non_case = 0
    for byte in name.upper().encode("latin1"):
        non_case = ((non_case >> 8) & 0x00FFFFFF) ^ _LEGACY_CRC_TABLE[(non_case ^ byte) & 0xFF]
    case = zlib.crc32(name.encode("utf-32-le"))
    return non_case & 0xFFFF, case & 0xFFFF


class _Cursor:
    def __init__(self, data, offset=0):
        self.data = data
        self.offset = offset

    def i32(self):
        value = struct.unpack_from("<i", self.data, self.offset)[0]
        self.offset += 4
        return value

    def skip(self, size):
        self.offset += size

    def skip_fstring(self):
        length = self.i32()
        self.skip(length if length >= 0 else -2 * length)

    def mark(self, size=4):
        position = self.offset
        self.skip(size)
        return position


def _locate_summary_fields(uasset):
    cursor = _Cursor(uasset)
    if struct.unpack_from("<I", uasset, 0)[0] != PACKAGE_TAG:
        raise ValueError("nao e um .uasset")
    cursor.skip(4)
    if cursor.i32() != SUPPORTED_LEGACY_VERSION:
        raise ValueError("versao de pacote diferente da do Remnant (UE 4.22)")
    cursor.skip(12)
    cursor.skip(cursor.i32() * 20)
    fields = {"total_header_size": cursor.mark()}
    cursor.skip_fstring()
    cursor.skip(4)
    for key in ("name_count", "name_offset", "gatherable_text_count", "gatherable_text_offset",
                "export_count", "export_offset", "import_count", "import_offset", "depends_offset",
                "soft_package_references_count", "soft_package_references_offset",
                "searchable_names_offset", "thumbnail_table_offset"):
        fields[key] = cursor.mark()
    cursor.skip(16)
    generation_count = cursor.i32()
    fields["generations"] = [cursor.offset + 8 * index for index in range(generation_count)]
    cursor.skip(8 * generation_count)
    for _ in range(2):
        cursor.skip(10)
        cursor.skip_fstring()
    cursor.skip(4)
    if cursor.i32() != 0:
        raise ValueError("pacote comprimido nao e suportado")
    cursor.skip(4)
    for _ in range(cursor.i32()):
        cursor.skip_fstring()
    fields["asset_registry_data_offset"] = cursor.mark()
    fields["bulk_data_start_offset"] = cursor.mark(8)
    fields["world_tile_info_data_offset"] = cursor.mark()
    cursor.skip(4 * cursor.i32())
    fields["preload_dependency_count"] = cursor.mark()
    fields["preload_dependency_offset"] = cursor.mark()
    return fields


def _read_names(uasset, offset, count):
    cursor = _Cursor(uasset, offset)
    names = []
    for _ in range(count):
        length = cursor.i32()
        if length < 0:
            raise ValueError("nome UTF-16 nao e suportado")
        names.append(uasset[cursor.offset:cursor.offset + length - 1].decode("latin1"))
        cursor.skip(length + 4)
    return names, cursor.offset


def _name_entry(name):
    encoded = (name + "\0").encode("latin1")
    non_case, case = ue4_name_hash(name)
    return struct.pack("<i", len(encoded)) + encoded + struct.pack("<HH", non_case, case)


def _read_rows(body, names):
    cursor = _Cursor(body)
    while names[cursor.i32()] != "None":
        cursor.skip(12)
        size = cursor.i32()
        cursor.skip(4 + 1 + size)
    cursor.skip(4)
    if cursor.i32() != 0:
        raise ValueError("DataTable com GUID de objeto nao e suportada")
    num_rows_position = cursor.offset
    rows = {}
    for _ in range(cursor.i32()):
        start = cursor.offset
        row_name = names[cursor.i32()]
        cursor.skip(4)
        value_positions = {}
        while True:
            prop = names[cursor.i32()]
            cursor.skip(4)
            if prop == "None":
                break
            if names[cursor.i32()] != "FloatProperty":
                raise ValueError("a linha %s tem propriedade que nao e float" % row_name)
            cursor.skip(4)
            size = cursor.i32()
            cursor.skip(4 + 1)
            value_positions[prop.split("_")[0]] = cursor.offset
            cursor.skip(size)
        rows[row_name] = (start, cursor.offset, value_positions)
    if cursor.offset != len(body):
        raise ValueError("sobraram bytes depois das linhas da DataTable")
    return num_rows_position, rows


def _row_values(row_name, test):
    values = dict(NEW_ROWS.get(row_name, {}))
    damage = 1.0 + max(int(row_name) - BASE_PLAYERS, 0) * DAMAGE_PER_EXTRA
    for scalar in DAMAGE_SCALARS:
        values[scalar] = damage
    if test and row_name == TEST_ROW:
        values["SpawnQuantityScalar"] = TEST_SCALE
        for scalar in DAMAGE_SCALARS:
            values[scalar] = TEST_SCALE
    return values


def _write_values(buffer, base, value_positions, values):
    for scalar, value in values.items():
        struct.pack_into("<f", buffer, value_positions[scalar] - base, value)


def build_table(uasset, uexp, test=False):
    header = bytearray(uasset)
    fields = _locate_summary_fields(header)

    def read(key):
        return struct.unpack_from("<i", header, fields[key])[0]

    def write(key, value):
        struct.pack_into("<i", header, fields[key], value)

    if read("export_count") != 1:
        raise ValueError("esperava uma DataTable com um unico export")
    old_name_count = read("name_count")
    names, name_table_end = _read_names(header, read("name_offset"), old_name_count)

    body = bytearray(uexp[:-4])
    tag = uexp[-4:]
    num_rows_position, rows = _read_rows(body, names)
    if any(name in rows for name in NEW_ROWS):
        raise ValueError("a tabela ja tem as linhas novas; use a tabela original")

    for row_name, (start, _, value_positions) in rows.items():
        _write_values(body, 0, value_positions, _row_values(row_name, test))

    template_start, template_end, template_positions = rows[NEW_ROW_TEMPLATE]
    template = body[template_start:template_end]
    new_names = list(NEW_ROWS)
    for row_name in new_names:
        row = bytearray(template)
        struct.pack_into("<i", row, 0, len(names) + new_names.index(row_name))
        _write_values(row, template_start, template_positions, _row_values(row_name, test))
        body += row
    struct.pack_into("<i", body, num_rows_position, len(rows) + len(new_names))

    inserted = b"".join(_name_entry(name) for name in new_names)
    header[name_table_end:name_table_end] = inserted
    shift = len(inserted)
    new_name_count = old_name_count + len(new_names)
    write("name_count", new_name_count)
    write("total_header_size", read("total_header_size") + shift)
    for key in HEADER_OFFSET_FIELDS:
        if read(key) >= name_table_end:
            write(key, read(key) + shift)
    for position in fields["generations"]:
        export_count, name_count = struct.unpack_from("<ii", header, position)
        if name_count == old_name_count:
            struct.pack_into("<ii", header, position, export_count, new_name_count)

    total_header_size = read("total_header_size")
    serial_position = read("export_offset") + EXPORT_SERIAL_SIZE_POSITION
    struct.pack_into("<qq", header, serial_position, len(body), total_header_size)
    struct.pack_into("<q", header, fields["bulk_data_start_offset"], total_header_size + len(body))

    if len(header) != total_header_size:
        raise ValueError("TotalHeaderSize nao bate com o tamanho do .uasset")
    return bytes(header), bytes(body + tag)


def load_original():
    base = os.path.join(ORIGINAL_DIR, TABLE_NAME)
    with open(base + ".uasset", "rb") as uasset, open(base + ".uexp", "rb") as uexp:
        return uasset.read(), uexp.read()


def main():
    parser = argparse.ArgumentParser(description="Gera a DataTable de escala por jogadores (linhas 1 a 6) em modified/.")
    parser.add_argument("--teste", action="store_true", help="tabela de teste: solo com 3x inimigos e 3x dano")
    args = parser.parse_args()
    uasset, uexp = build_table(*load_original(), test=args.teste)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    base = os.path.join(OUTPUT_DIR, TABLE_NAME)
    with open(base + ".uasset", "wb") as out:
        out.write(uasset)
    with open(base + ".uexp", "wb") as out:
        out.write(uexp)
    print("DataTable gerada em %s (%d + %d bytes)" % (OUTPUT_DIR, len(uasset), len(uexp)))


if __name__ == "__main__":
    main()
