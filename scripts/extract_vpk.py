#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CS2 精简服务端复刻 - VPK v2 解析与 loose files 提取脚本

原理：
  Source 2 文件系统优先级：loose files > addon VPK > game VPK。
  把服务器需要的文件从 VPK 编号包中提取到 csgo/ 对应路径（loose files），
  之后移走 pak01_dir.vpk 及所有编号包，引擎就从 loose files 加载，不再触碰编号包。

用法：
  python extract_vpk.py --dir-vpk game/csgo/pak01_dir.vpk \
      --archives-dir game/csgo \
      --output ../cs2_loose/game/csgo

VPK v2 目录树格式（ValvePak / ValvePython-vpk 确认）：
  树是三层嵌套结构，按 (扩展名, 路径, 文件名) 分组：
    while True:
        ext = read_cstring()          # 空串 => 整棵树结束
        if not ext: break
        while True:
            path = read_cstring()     # 空串 => 该扩展名下路径结束
            if not path: break
            while True:
                name = read_cstring() # 空串 => 该路径下文件结束
                if not name: break
                uint32 crc
                uint16 preloadLength
                uint16 archiveIndex
                uint32 entryOffset
                uint32 entryLength
                uint16 terminator (0xffff)
                [preloadLength 字节 preload data]

筛选规则（默认）：
  排除扩展名：.vtex .vtex_c .vsnd .vsnd_c （纹理/音频采样，纯客户端）
  排除目录：  panorama/ stickers/ patches/ sprays/ shaders/
  其余全部保留（models/materials/particles/resource/scripts/weapons/characters/soundevents...）
"""

import argparse
import os
import struct
import sys
from collections import Counter, OrderedDict

VPK_MAGIC = 0x55AA1234
TERMINATOR = 0xFFFF
EMBEDDED = 0x7FFF  # archiveIndex 表示数据内联在 dir.vpk

DEFAULT_EXCLUDE_DIRS = (
    "panorama/",
    "stickers/",
    "patches/",
    "sprays/",
    "shaders/",
)

DEFAULT_EXCLUDE_EXTS = (
    ".vtex",
    ".vtex_c",
    ".vsnd",
    ".vsnd_c",
)


def read_null_string(buf, offset):
    """读取以 \\x00 结尾的字符串，返回 (字符串, 下一个偏移)。"""
    end = buf.find(b"\x00", offset)
    if end == -1:
        raise ValueError(f"未找到字符串结束符，偏移 {offset}")
    return buf[offset:end].decode("utf-8", errors="replace"), end + 1


def parse_vpk_tree(buf):
    """解析 VPK v2 目录树（三层嵌套结构）。

    Header (v2, 28 字节):
      uint32 magic
      uint32 version
      uint32 treeSize
      uint32 fileDataSectionSize
      uint32 archiveMd5SectionSize
      uint32 otherMd5SectionSize
      uint32 signatureSectionSize

    返回 dict，entries 为按树序排列的条目列表。
    """
    if len(buf) < 12:
        raise ValueError("VPK 文件过小")
    magic, version, tree_size = struct.unpack_from("<III", buf, 0)
    if magic != VPK_MAGIC:
        raise ValueError(f"不是有效的 VPK 文件 (magic=0x{magic:08x})")

    file_data_section_size = 0
    if version == 2:
        if len(buf) < 28:
            raise ValueError("VPK v2 文件过小")
        (file_data_section_size,
         archive_md5_section_size,
         other_md5_section_size,
         signature_section_size) = struct.unpack_from("<IIII", buf, 12)
        header_size = 28
    elif version == 1:
        header_size = 12
    else:
        raise ValueError(f"不支持的 VPK 版本: {version}")

    pos = header_size
    entries = []

    while True:
        ext, pos = read_null_string(buf, pos)
        if not ext:
            break  # 整棵树结束

        while True:
            path, pos = read_null_string(buf, pos)
            if not path:
                break  # 该扩展名下所有路径结束

            while True:
                name, pos = read_null_string(buf, pos)
                if not name:
                    break  # 该路径下所有文件结束

                if pos + 18 > len(buf):
                    raise ValueError("目录树意外结束（越界）")
                (crc, preload_len, archive_idx,
                 entry_off, entry_len, term) = struct.unpack_from("<IHHIIH", buf, pos)
                pos += 18
                if term != TERMINATOR:
                    raise ValueError(
                        f"条目终结符异常: {term:#x} (ext={ext!r}, path={path!r}, name={name!r})"
                    )

                preload = b""
                if preload_len > 0:
                    preload = buf[pos : pos + preload_len]
                    pos += preload_len

                entries.append({
                    "extension": ext,
                    "path": path,
                    "name": name,
                    "crc": crc,
                    "preload": preload,
                    "archive_index": archive_idx,
                    "entry_offset": entry_off,
                    "entry_length": entry_len,
                })

    return {
        "version": version,
        "tree_size": tree_size,
        "file_data_section_size": file_data_section_size,
        "header_size": header_size,
        "entries": entries,
    }


def normalize_path(path):
    """规范化 VPK 中的路径。Valve 用单个空格 " " 表示根目录。"""
    if path == " ":
        return ""
    return path.strip().replace("\\", "/")


def make_full_path(path, name, ext):
    """组合完整相对路径。"""
    p = normalize_path(path)
    if p:
        return f"{p}/{name}.{ext}"
    return f"{name}.{ext}"


def should_exclude(full_path):
    """应用排除规则。返回 True 表示排除。"""
    lower = full_path.lower()
    for d in DEFAULT_EXCLUDE_DIRS:
        if lower.startswith(d):
            return True
    for d in DEFAULT_EXCLUDE_DIRS:
        if f"/{d}" in lower:
            return True
    for e in DEFAULT_EXCLUDE_EXTS:
        if lower.endswith(e):
            return True
    return False


# LRU 句柄缓存：限制同时打开的编号包句柄数，避免大量 VPK 包时触及 ulimit -n
archive_handles = OrderedDict()
_ARCHIVE_HANDLE_MAX = 32


def read_archive_data(archive_index, entry_offset, entry_length, archives_dir):
    """随机访问读取编号包指定范围数据。LRU 句柄缓存避免重复打开文件，同时限制句柄数。"""
    if archive_index == EMBEDDED:
        return None  # 数据在 dir.vpk 内联区，由调用方处理
    if archive_index not in archive_handles:
        archive_path = os.path.join(archives_dir, f"pak01_{archive_index:03d}.vpk")
        if not os.path.exists(archive_path):
            archive_handles[archive_index] = None
        else:
            archive_handles[archive_index] = open(archive_path, "rb")
            # 超过上限：关闭并移除最久未使用的已打开句柄
            if len(archive_handles) > _ARCHIVE_HANDLE_MAX:
                for idx in list(archive_handles.keys()):
                    h = archive_handles[idx]
                    if h is not None:
                        h.close()
                        del archive_handles[idx]
                        break
    else:
        archive_handles.move_to_end(archive_index)
    h = archive_handles[archive_index]
    if h is None:
        return None
    h.seek(entry_offset)
    return h.read(entry_length)


def main():
    parser = argparse.ArgumentParser(description="CS2 VPK loose files 提取脚本")
    parser.add_argument("--dir-vpk", required=True, help="pak01_dir.vpk 路径")
    parser.add_argument("--archives-dir", default=None,
                        help="编号包所在目录（默认与 dir-vpk 同目录）")
    parser.add_argument("--output", required=True, help="提取输出目录")
    parser.add_argument("--no-preload", action="store_true",
                        help="不提取 preload 数据（仅编号包数据）")
    args = parser.parse_args()

    with open(args.dir_vpk, "rb") as f:
        buf = f.read()

    print(f"解析 VPK: {args.dir_vpk}")
    info = parse_vpk_tree(buf)
    print(f"VPK 版本: {info['version']}, 目录树大小: {info['tree_size']/1024/1024:.1f} MB, "
          f"条目数: {len(info['entries'])}")

    archives_dir = args.archives_dir or os.path.dirname(args.dir_vpk)
    output_dir = args.output
    os.makedirs(output_dir, exist_ok=True)

    kept = 0
    excluded = 0
    missing_archive = 0
    total_bytes = 0
    ext_counter = Counter()
    embedded_base = info["header_size"] + info["tree_size"]

    for idx, e in enumerate(info["entries"]):
        full_path = make_full_path(e["path"], e["name"], e["extension"])
        if should_exclude(full_path):
            excluded += 1
            continue

        # 组装文件数据 = preload(内联前缀) + 归档/内联数据
        data_parts = []
        if not args.no_preload and e["preload"]:
            data_parts.append(e["preload"])

        if e["archive_index"] == EMBEDDED:
            # 数据内联在 dir.vpk 的 embedded data section
            start = embedded_base + e["entry_offset"]
            if start + e["entry_length"] <= len(buf):
                data_parts.append(buf[start : start + e["entry_length"]])
            else:
                missing_archive += 1
                continue
        else:
            archive_data = read_archive_data(
                e["archive_index"], e["entry_offset"], e["entry_length"], archives_dir
            )
            if archive_data is None:
                missing_archive += 1
                continue
            data_parts.append(archive_data)

        if not data_parts:
            continue
        data = b"".join(data_parts)

        out_path = os.path.join(output_dir, full_path)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "wb") as f:
            f.write(data)

        kept += 1
        total_bytes += len(data)
        ext = os.path.splitext(full_path)[1]
        ext_counter[ext] += 1

        if (idx + 1) % 5000 == 0:
            print(f"  进度: {idx+1}/{len(info['entries'])} 条目, 已保留 {kept} 文件")

    print()
    print("===== 提取完成 =====")
    print(f"总条目: {len(info['entries'])}")
    print(f"保留: {kept} 文件, {total_bytes/1024/1024:.1f} MB")
    print(f"排除: {excluded} 文件")
    print(f"跳过(缺编号包/无数据): {missing_archive}")
    print("扩展名 Top 15:")
    for ext, cnt in ext_counter.most_common(15):
        print(f"  {ext or '(无)'}: {cnt}")


if __name__ == "__main__":
    sys.exit(main())