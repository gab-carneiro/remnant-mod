import hashlib
import struct
import zlib

PAK_MAGIC = 0x5A6F12E1
PAK_VERSION_INITIAL = 1
PAK_VERSION_COMPRESSION_ENCRYPTION = 3
PAK_VERSION_INDEX_ENCRYPTION = 4
PAK_VERSION_RELATIVE_CHUNK_OFFSETS = 5
PAK_VERSION_ENCRYPTION_KEY_GUID = 7
PAK_VERSION_FNAME_BASED_COMPRESSION = 8
PAK_VERSION_LATEST = 8
COMPRESSION_METHOD_NAME_LEN = 32
MAX_NUM_COMPRESSION_METHODS = 4

PROJECT_NAME = "Remnant"
PROJECT_CONTENT_DIR = "../../../Remnant/Content/"
ENGINE_CONTENT_DIR = "../../../Engine/Content/"
PROJECT_SAVED_DIR = "../../../Remnant/Saved/"


class PakFatal(Exception):
    pass


class Reader:
    def __init__(self, data, offset=0):
        self.data = data
        self.offset = offset

    def take(self, size):
        if size < 0 or self.offset + size > len(self.data):
            raise PakFatal("leitura passou do fim do buffer")
        chunk = self.data[self.offset:self.offset + size]
        self.offset += size
        return chunk

    def unpack(self, fmt):
        values = struct.unpack(fmt, self.take(struct.calcsize(fmt)))
        return values[0] if len(values) == 1 else values

    def fstring(self):
        length = self.unpack('<i')
        if length == 0:
            return ""
        if length > 0:
            return self.take(length)[:-1].decode('latin1')
        return self.take(-2 * length).decode('utf-16-le')[:-1]


def pak_info_serialized_size(version):
    size = 4 + 4 + 8 + 8 + 20 + 1
    if version >= PAK_VERSION_ENCRYPTION_KEY_GUID:
        size += 16
    if version >= PAK_VERSION_FNAME_BASED_COMPRESSION:
        size += COMPRESSION_METHOD_NAME_LEN * MAX_NUM_COMPRESSION_METHODS
    return size


def read_pak_info(data):
    for version in range(PAK_VERSION_LATEST, PAK_VERSION_INITIAL - 1, -1):
        position = len(data) - pak_info_serialized_size(version)
        if position < 0:
            continue
        reader = Reader(data, position)
        guid = bytes(16)
        if version >= PAK_VERSION_ENCRYPTION_KEY_GUID:
            guid = reader.take(16)
        encrypted_index = reader.unpack('<B')
        if reader.unpack('<I') != PAK_MAGIC:
            continue
        file_version = reader.unpack('<i')
        index_offset = reader.unpack('<q')
        index_size = reader.unpack('<q')
        index_hash = reader.take(20)
        if file_version < PAK_VERSION_INDEX_ENCRYPTION:
            encrypted_index = 0
        if file_version < PAK_VERSION_ENCRYPTION_KEY_GUID:
            guid = bytes(16)
        methods = [None]
        if file_version < PAK_VERSION_FNAME_BASED_COMPRESSION:
            methods += ["Zlib", "Gzip", "Oodle"]
        else:
            raw = reader.take(COMPRESSION_METHOD_NAME_LEN * MAX_NUM_COMPRESSION_METHODS)
            for slot in range(MAX_NUM_COMPRESSION_METHODS):
                name = raw[slot * COMPRESSION_METHOD_NAME_LEN:(slot + 1) * COMPRESSION_METHOD_NAME_LEN]
                if name[0] != 0:
                    methods.append(name.split(b'\0', 1)[0].decode('latin1'))
        return {
            "compatible_version": version,
            "version": file_version,
            "encryption_key_guid": guid,
            "encrypted_index": encrypted_index,
            "index_offset": index_offset,
            "index_size": index_size,
            "index_hash": index_hash,
            "compression_methods": methods,
        }
    raise PakFatal("Trailing magic number is different than the expected one")


def read_pak_entry(reader, version):
    entry = {}
    entry["offset"] = reader.unpack('<q')
    entry["size"] = reader.unpack('<q')
    entry["uncompressed_size"] = reader.unpack('<q')
    if version < PAK_VERSION_FNAME_BASED_COMPRESSION:
        entry["compression_method_index"] = 0 if reader.unpack('<i') == 0 else 1
    else:
        entry["compression_method_index"] = reader.unpack('<B')
    if version <= PAK_VERSION_INITIAL:
        reader.take(8)
    entry["hash"] = reader.take(20)
    entry["blocks"] = []
    entry["flags"] = 0
    entry["block_size"] = 0
    if version >= PAK_VERSION_COMPRESSION_ENCRYPTION:
        if entry["compression_method_index"] != 0:
            count = reader.unpack('<i')
            entry["blocks"] = [reader.unpack('<qq') for _ in range(count)]
        entry["flags"] = reader.unpack('<B')
        entry["block_size"] = reader.unpack('<I')
    return entry


def mount_pak(data):
    info = read_pak_info(data)
    version = info["version"]
    if not (PAK_VERSION_INITIAL <= version <= info["compatible_version"]):
        raise PakFatal("Invalid pak file version")
    if info["encrypted_index"] == 1:
        raise PakFatal("Index of pak file is encrypted, but this executable doesn't have any valid decryption keys")
    if not (0 <= info["index_offset"] < len(data)):
        raise PakFatal("Index offset is invalid")
    if not (0 <= info["index_offset"] + info["index_size"] <= len(data)):
        raise PakFatal("Index end offset is invalid")
    if any(info["encryption_key_guid"]):
        return {"mounted": False, "deferred_for_key": info["encryption_key_guid"].hex(), "info": info, "files": {}}
    index = data[info["index_offset"]:info["index_offset"] + info["index_size"]]
    if hashlib.sha1(index).digest() != info["index_hash"]:
        raise PakFatal("Corrupted index in pak file (CRC mismatch)")
    reader = Reader(index)
    mount_point = reader.fstring()
    files = {}
    for _ in range(reader.unpack('<i')):
        name = reader.fstring()
        files[name] = read_pak_entry(reader, version)
    if reader.offset != len(index):
        raise PakFatal("bytes sobrando no indice")
    return {"mounted": True, "mount_point": mount_point, "info": info, "files": files}


def pak_entry_serialized_size(entry, version):
    size = 8 + 8 + 8 + 20
    size += 1 if version >= PAK_VERSION_FNAME_BASED_COMPRESSION else 4
    if version >= PAK_VERSION_COMPRESSION_ENCRYPTION:
        size += 1 + 4
        if entry["compression_method_index"] != 0:
            size += 16 * len(entry["blocks"]) + 4
    if version < 2:
        size += 8
    return size


def read_pak_file(data, mounted, name):
    entry = mounted["files"][name]
    version = mounted["info"]["version"]
    inline_reader = Reader(data, entry["offset"])
    inline = read_pak_entry(inline_reader, version)
    for key in ("size", "uncompressed_size", "compression_method_index", "hash", "blocks", "flags", "block_size"):
        if inline[key] != entry[key]:
            raise PakFatal("Serialized hash mismatch: cabecalho inline difere do indice em " + key)
    if entry["flags"] & 1:
        raise PakFatal("entrada criptografada")
    header_size = pak_entry_serialized_size(entry, version)
    if inline_reader.offset - entry["offset"] != header_size:
        raise PakFatal("cabecalho inline com tamanho diferente de GetSerializedSize")
    stored = data[entry["offset"] + header_size:entry["offset"] + header_size + entry["size"]]
    if hashlib.sha1(stored).digest() != entry["hash"]:
        raise PakFatal("Hash mismatch: o hash nao e o dos bytes gravados (FPakFile::Check)")
    method = mounted["info"]["compression_methods"][entry["compression_method_index"]]
    if method is None:
        payload = stored
    elif method == "Zlib":
        base = entry["offset"] if version >= PAK_VERSION_RELATIVE_CHUNK_OFFSETS else 0
        payload = b"".join(zlib.decompress(data[base + start:base + end]) for start, end in entry["blocks"])
    else:
        raise PakFatal("metodo de compressao inesperado: " + str(method))
    if len(payload) != entry["uncompressed_size"]:
        raise PakFatal("tamanho descomprimido difere")
    return payload


def pak_read_order(pak_path):
    if pak_path.startswith("%sPaks/%s-" % (PROJECT_CONTENT_DIR, PROJECT_NAME)):
        order = 4
    elif pak_path.startswith(PROJECT_CONTENT_DIR):
        order = 3
    elif pak_path.startswith(ENGINE_CONTENT_DIR):
        order = 2
    elif pak_path.startswith(PROJECT_SAVED_DIR):
        order = 1
    else:
        order = 0
    if pak_path.endswith("_P.pak"):
        chunk_version = 1
        version_end = pak_path.rfind("_")
        if version_end > 0:
            version_start = pak_path.rfind("_", 0, version_end)
            if version_start != -1:
                version_string = pak_path[version_start + 1:version_end]
                if version_string.isdigit() and int(version_string) >= 1:
                    chunk_version = int(version_string) + 1
        order += 100 * chunk_version
    return order


def pak_lookup_order(pak_paths):
    found = sorted(pak_paths, key=lambda path: path.lower(), reverse=True)
    mounted = sorted(enumerate(found), key=lambda item: (-pak_read_order(item[1]), item[0]))
    return [path for _, path in mounted]


def read_package(uasset, uexp):
    r = Reader(uasset)
    pkg = {}
    pkg["tag"] = r.unpack('<I')
    pkg["legacy_version"] = r.unpack('<i')
    r.take(12)
    r.take(r.unpack('<i') * 20)
    pkg["total_header_size"] = r.unpack('<i')
    pkg["folder_name"] = r.fstring()
    pkg["package_flags"] = r.unpack('<I')
    for key in ("name_count", "name_offset", "gatherable_text_count", "gatherable_text_offset",
                "export_count", "export_offset", "import_count", "import_offset", "depends_offset",
                "soft_package_references_count", "soft_package_references_offset",
                "searchable_names_offset", "thumbnail_table_offset"):
        pkg[key] = r.unpack('<i')
    pkg["guid"] = r.take(16)
    pkg["generations"] = [r.unpack('<ii') for _ in range(r.unpack('<i'))]
    for key in ("saved_by_engine_version", "compatible_with_engine_version"):
        pkg[key] = (r.unpack('<HHH'), r.unpack('<I'), r.fstring())
    pkg["compression_flags"] = r.unpack('<I')
    pkg["compressed_chunks"] = r.unpack('<i')
    pkg["package_source"] = r.unpack('<I')
    pkg["additional_packages_to_cook"] = [r.fstring() for _ in range(r.unpack('<i'))]
    pkg["asset_registry_data_offset"] = r.unpack('<i')
    pkg["bulk_data_start_offset"] = r.unpack('<q')
    pkg["world_tile_info_data_offset"] = r.unpack('<i')
    pkg["chunk_ids"] = [r.unpack('<i') for _ in range(r.unpack('<i'))]
    pkg["preload_dependency_count"] = r.unpack('<i')
    pkg["preload_dependency_offset"] = r.unpack('<i')

    r = Reader(uasset, pkg["name_offset"])
    pkg["names"] = []
    for _ in range(pkg["name_count"]):
        name = r.fstring()
        non_case, case = r.unpack('<HH')
        pkg["names"].append((name, non_case, case))
    pkg["name_table_end"] = r.offset

    r = Reader(uasset, pkg["import_offset"])
    pkg["imports"] = [r.unpack('<iiiiiii') for _ in range(pkg["import_count"])]

    r = Reader(uasset, pkg["export_offset"])
    pkg["exports"] = []
    for _ in range(pkg["export_count"]):
        export = {}
        export["class_index"], export["super_index"], export["template_index"], export["outer_index"] = r.unpack('<iiii')
        export["object_name"] = r.unpack('<ii')
        export["object_flags"] = r.unpack('<I')
        export["serial_size"], export["serial_offset"] = r.unpack('<qq')
        export["forced_export"], export["not_for_client"], export["not_for_server"] = r.unpack('<iii')
        export["package_guid"] = r.take(16)
        export["package_flags"] = r.unpack('<I')
        export["not_always_loaded_for_editor_game"], export["is_asset"] = r.unpack('<ii')
        export["preload_dependencies"] = r.unpack('<iiiii')
        pkg["exports"].append(export)

    r = Reader(uasset, pkg["depends_offset"])
    pkg["depends"] = [[r.unpack('<i') for _ in range(r.unpack('<i'))] for _ in range(pkg["export_count"])]

    r = Reader(uasset, pkg["asset_registry_data_offset"])
    pkg["asset_registry_object_count"] = r.unpack('<i')

    r = Reader(uasset, pkg["preload_dependency_offset"])
    pkg["preload_dependencies"] = [r.unpack('<i') for _ in range(pkg["preload_dependency_count"])]

    pkg["uasset_size"] = len(uasset)
    pkg["uexp_size"] = len(uexp)
    pkg["uexp_tag"] = struct.unpack_from('<I', uexp, len(uexp) - 4)[0]
    return pkg


def read_data_table_rows(pkg, uexp):
    names = [entry[0] for entry in pkg["names"]]
    r = Reader(uexp, 0)
    while True:
        name_index, _ = r.unpack('<ii')
        if names[name_index] == "None":
            break
        r.take(8)
        size, _ = r.unpack('<ii')
        r.take(1)
        r.take(size)
    if r.unpack('<i') != 0:
        raise ValueError("objeto com GUID inesperado")
    rows = {}
    for _ in range(r.unpack('<i')):
        row_index, _ = r.unpack('<ii')
        values = {}
        while True:
            prop_index, _ = r.unpack('<ii')
            prop = names[prop_index]
            if prop == "None":
                break
            type_index, _ = r.unpack('<ii')
            if names[type_index] != "FloatProperty":
                raise ValueError("propriedade inesperada: " + names[type_index])
            r.unpack('<ii')
            r.take(1)
            values[prop.split('_')[0]] = r.unpack('<f')
        rows[names[row_index]] = values
    serial_size = pkg["exports"][0]["serial_size"]
    if r.offset != serial_size:
        raise ValueError("export termina em %d mas SerialSize e %d" % (r.offset, serial_size))
    return rows
