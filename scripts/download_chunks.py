#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Steam CDN 1MB Range 分块下载器

背景: 部分网络环境对 Steam CDN (steamcdn-a.akamaihd.net) 的单连接约 3MB 就断开,
      直接 curl 下载大文件会得到截断结果。本脚本按 1MB 分块请求, 失败自动重试,
      最后拼接为完整文件。

用法:
    python download_chunks.py <url> <total_size> <output_path> [--chunk 1000000] [--retries 12]

示例:
    python download_chunks.py \
        https://steamcdn-a.akamaihd.net/client/bins_win32.zip.<sha> \
        59544006 \
        bins_win32.zip

依赖: 仅 Python 3 标准库 (urllib)。
"""
import argparse
import os
import sys
import time
import urllib.request


def download_chunks(url: str, total: int, outpath: str, chunk: int = 1_000_000, retries: int = 12):
    parts_dir = outpath + ".parts"
    os.makedirs(parts_dir, exist_ok=True)

    for start in range(0, total, chunk):
        end = min(start + chunk - 1, total - 1)
        part = os.path.join(parts_dir, f"part_{start:08d}.bin")
        expected = end - start + 1
        if os.path.exists(part) and os.path.getsize(part) == expected:
            print(f"skip existing {start}-{end}", flush=True)
            continue

        ok = False
        for attempt in range(retries):
            try:
                req = urllib.request.Request(url, headers={
                    "Range": f"bytes={start}-{end}",
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0",
                })
                with urllib.request.urlopen(req, timeout=90) as r:
                    data = r.read()
                if len(data) == expected:
                    with open(part, "wb") as f:
                        f.write(data)
                    print(f"ok {start}-{end}", flush=True)
                    ok = True
                    break
                print(f"short {start}-{end} got {len(data)}, attempt {attempt}", flush=True)
            except Exception as e:
                print(f"err {start}-{end} attempt {attempt}: {e}", flush=True)
            time.sleep(1)
        if not ok:
            print(f"FAILED chunk {start}-{end}", flush=True)
            sys.exit(1)

    print("All chunks done. Concatenating...", flush=True)
    if os.path.exists(outpath):
        os.remove(outpath)
    with open(outpath, "wb") as out:
        for start in range(0, total, chunk):
            part = os.path.join(parts_dir, f"part_{start:08d}.bin")
            with open(part, "rb") as f:
                out.write(f.read())
    print(f"Done. Size: {os.path.getsize(outpath)}", flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("url", help="文件完整 URL")
    ap.add_argument("total", type=int, help="文件总字节数 (Content-Length)")
    ap.add_argument("output", help="输出文件路径")
    ap.add_argument("--chunk", type=int, default=1_000_000, help="分块大小, 默认 1MB")
    ap.add_argument("--retries", type=int, default=12, help="每块最大重试次数")
    args = ap.parse_args()
    download_chunks(args.url, args.total, args.output, args.chunk, args.retries)


if __name__ == "__main__":
    main()