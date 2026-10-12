"""Link resource_fast.S and extend the C-built DLL with the V1.0 fast transport.

Uses Python's standard library and a Zig-produced ELF assembler object. No
precompiled template, downloaded DLL, GNU binutils or private Lua layout is used.
The input hash and three instruction sites are checked before changing bytes.
"""
import hashlib
import pathlib
import struct

BASELINE_SHA256 = "887b364acf5ae07c1b8d320ad693957f20a6df9220b17bbe13a718fde1d83b01"
UPDATED_SHA256 = "409d00d74024296befcb74dc72790202bdc20d68b1604a6c939f208f8242cd16"
TEXT_RVA = 0x7000
EXTERNALS = {
    "original_entry": 0x1020, "original_bind": 0x105d,
    "original_thread_check": 0x139f, "original_format": 0x13e1,
    "original_error_format": 0x13f4, "original_epilogue": 0x1532,
    "native_lock": 0x4008, "native_actor": 0x4018, "native_error": 0x4020,
    "response_buffer": 0x4940, "cached_valid": 0x8000,
    "cached_pawn": 0x8008, "cached_pc": 0x8010, "cached_world": 0x8018,
    "bad_request": 0x3118,
}


def link_text(object_path):
    """Resolve the object's x86-64 PC-relative relocations at module RVA 0x7000."""
    obj = pathlib.Path(object_path).read_bytes()
    header = struct.unpack_from("<16sHHIQQQIHHHHHH", obj)
    if header[0][:7] != b"\x7fELF\x02\x01\x01" or header[1:3] != (1, 62):
        raise ValueError("Expected an ELF64 little-endian x86-64 assembler object")
    shoff, shsize, shcount, names_index = header[6], header[11], header[12], header[13]
    sections = [struct.unpack_from("<IIQQQQIIQQ", obj, shoff+i*shsize) for i in range(shcount)]

    def section_data(index):
        section = sections[index]
        return obj[section[4]:section[4]+section[5]]

    def cstring(table, offset):
        return table[offset:table.index(b"\0", offset)].decode("ascii")

    section_names = section_data(names_index)
    text_index = next(i for i,s in enumerate(sections) if cstring(section_names,s[0]) == ".text")
    text = bytearray(section_data(text_index))
    sym_index = next(i for i,s in enumerate(sections) if s[1] == 2)
    sym_section = sections[sym_index]
    strings = section_data(sym_section[6])
    symbols = []
    addresses = {}
    for offset in range(sym_section[4], sym_section[4]+sym_section[5], sym_section[9]):
        name, _info, _other, index, value, _size = struct.unpack_from("<IBBHQQ", obj, offset)
        name = cstring(strings, name)
        if index == text_index:
            address = TEXT_RVA+value
        elif index == 0xfff1:
            address = value
        elif index == 0:
            address = EXTERNALS.get(name)
        else:
            address = None
        symbols.append((name,address))
        if address is not None: addresses[name] = address
    for section in sections:
        if section[1] != 4 or section[7] != text_index:
            continue
        if section[6] != sym_index:
            raise ValueError("Unexpected relocation symbol table")
        for offset in range(section[4],section[4]+section[5],section[9]):
            place, info, addend = struct.unpack_from("<QQq",obj,offset)
            kind, symbol = info & 0xffffffff, info >> 32
            name, target = symbols[symbol]
            if kind not in (2,4) or target is None:
                raise ValueError("Unsupported relocation: %s type %s" % (name,kind))
            struct.pack_into("<i",text,place,target+addend-(TEXT_RVA+place))
    if addresses["bind_entry"] != TEXT_RVA:
        raise ValueError("Unexpected transport layout")
    return text,addresses


def apply_transport(dll_path, object_path):
    dll_path = pathlib.Path(dll_path)
    image = bytearray(dll_path.read_bytes())
    if hashlib.sha256(image).hexdigest() != BASELINE_SHA256:
        raise ValueError("C-built baseline DLL differs; refusing transport update")
    fast, addresses = link_text(object_path)
    pe = struct.unpack_from("<I",image,60)[0]
    opt = pe+24
    sections = opt+struct.unpack_from("<H",image,pe+20)[0]

    def patch(rva, expected, target):
        offset = rva-0x1000+0x400
        expected = bytes.fromhex(expected)
        if image[offset:offset+len(expected)] != expected:
            raise ValueError("Instruction site differs at RVA %x" % rva)
        image[offset:offset+len(expected)] = b"\xe9"+struct.pack("<i",addresses[target]-(rva+5))+b"\x90"*(len(expected)-5)

    patch(0x1057,"0f85d3040000","dispatch_hook")
    patch(0x13da,"4c8b0d3f2c0000","result_hook")
    patch(0x13ed,"488d0d4c350000","exception_hook")

    def append(data, alignment=1):
        fast.extend(bytes(-len(fast) % alignment))
        rva = TEXT_RVA+len(fast)
        fast.extend(data)
        return rva

    # Added fragments use the C function's existing stack frame. Chained unwind
    # metadata preserves Windows stack walking; the entry thunks are leaf code.
    chain = append(bytes([0x21,0,0,0x85])+struct.pack("<III",0x1020,0x156d,0x3640),4)
    pdata = append(bytes(image[0x1e00:0x1e48])+struct.pack("<III",addresses["dispatch_hook"],addresses["error_rvas"],chain),4)
    struct.pack_into("<II",image,opt+112+3*8,pdata,84)
    export = append(bytes(40),4)
    dllname = append(b"BossLabGauge.dll\0")
    runname = append(b"BossLabRun\0")
    tickname = append(b"BossLabTick\0")
    eat = append(struct.pack("<II",addresses["bind_entry"],addresses["tick_entry"]),4)
    names = append(struct.pack("<II",runname,tickname),4)
    ords = append(struct.pack("<HH",0,1),2)
    struct.pack_into("<IIHHIIIIIII",fast,export-TEXT_RVA,0,0,0,0,dllname,1,2,2,eat,names,ords)
    struct.pack_into("<II",image,opt+112,export,TEXT_RVA+len(fast)-export)
    raw_size = (len(fast)+511)//512*512
    if len(fast) >= 0x1000 or len(image) != 0x2000:
        raise ValueError("Unexpected DLL or extension size")
    struct.pack_into("<8sIIIIIIHHI",image,sections+4*40,b".fast\0\0\0",len(fast),0x7000,raw_size,len(image),0,0,0,0,0x60000020)
    struct.pack_into("<8sIIIIIIHHI",image,sections+5*40,b".cache\0\0",32,0x8000,0,0,0,0,0,0,0xc0000080)
    struct.pack_into("<H",image,pe+6,6)
    struct.pack_into("<I",image,opt+4,0x1200+raw_size)
    struct.pack_into("<I",image,opt+12,32)
    struct.pack_into("<I",image,opt+56,0x9000)
    image.extend(fast+bytes(raw_size-len(fast)))
    if hashlib.sha256(image).hexdigest() != UPDATED_SHA256:
        raise ValueError("Updated DLL does not match the published resource build")
    dll_path.write_bytes(image)
