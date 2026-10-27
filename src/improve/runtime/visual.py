"""Bounded original-image snapshots; collection stays with the authorized caller."""
from __future__ import annotations

import io
import os
import stat
import warnings
from pathlib import Path

from contracts import (BoundaryError, atomic_private, digest, private_dir, relative_path,
                       strict_json, _strings, _text)

DEFAULT_LIMITS = {"count": 8, "perImageBytes": 20 * 1024 * 1024, "totalBytes": 50 * 1024 * 1024}


def read_local(root: Path, name: str, limit: int) -> bytes:
    if not relative_path(name):
        raise BoundaryError("input path must stay within its manifest directory")
    descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        parts = name.split("/")
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        source = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=descriptor)
        try:
            before = os.fstat(source)
            if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= limit:
                raise BoundaryError("input is not a bounded readable regular file")
            with os.fdopen(os.dup(source), "rb") as stream:
                raw = stream.read(limit + 1)
            after = os.fstat(source)
            current = os.stat(parts[-1], dir_fd=descriptor, follow_symlinks=False)
            identity = lambda info: (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)
            if len(raw) > limit or identity(before) != identity(after) or identity(after) != identity(current):
                raise BoundaryError("input changed while reading")
            physical = root
            for part in parts:
                physical = physical / part
                if physical.is_symlink():
                    raise BoundaryError("input path contains a symlink")
            if physical.stat() != current:
                raise BoundaryError("input path changed while reading")
            return raw
        finally:
            os.close(source)
    except OSError as exc:
        raise BoundaryError("input is unreadable or has an unsafe path") from exc
    finally:
        os.close(descriptor)


def decode(raw: bytes) -> dict:
    try:
        from PIL import Image
    except ImportError as exc:
        raise BoundaryError("visual requires Pillow; install requirements-visual.txt in a temporary venv") from exc
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(raw)) as image:
                if image.format not in ("PNG", "JPEG") or getattr(image, "n_frames", 1) != 1:
                    raise BoundaryError("only static PNG/JPEG inputs are supported")
                metadata = {"format": image.format, "width": image.width, "height": image.height}
                image.verify()
            with Image.open(io.BytesIO(raw)) as image:
                image.load()
        return metadata
    except (OSError, ValueError, SyntaxError, Image.DecompressionBombError, Image.DecompressionBombWarning) as exc:
        raise BoundaryError("image is corrupt, animated, unsupported, or a decompression bomb") from exc


def import_images(store, record: dict, manifest: Path) -> None:
    root = manifest.absolute().parent
    payload = strict_json(read_local(root, manifest.name, 64 * 1024))
    if not isinstance(payload, dict) or set(payload) != {"version", "images"} or type(payload["version"]) is not int or payload["version"] != 1:
        raise BoundaryError("invalid image manifest")
    images = payload["images"]
    limits = record["plan_settings"]["routing"]["inputs"].get("imageLimits", DEFAULT_LIMITS)
    if not isinstance(images, list) or not 1 <= len(images) <= limits["count"]:
        raise BoundaryError("image count exceeds reviewed limits or is empty")
    location = private_dir(store.path(record["id"]) / "images")
    snapshots = []
    total = 0
    for item in images:
        if not isinstance(item, dict) or not {"path", "purpose", "source"} <= set(item) or not set(item) <= {"path", "purpose", "source", "capture"} or item["purpose"] not in ("reference", "candidate") or not _text(item["source"]):
            raise BoundaryError("invalid image entry")
        raw = read_local(root, item["path"], limits["perImageBytes"])
        total += len(raw)
        if total > limits["totalBytes"]:
            raise BoundaryError("total image bytes exceed reviewed limits")
        image_id = store.new_id()
        snapshot = {"id": image_id, "sha256": digest(raw), "bytes": len(raw), **decode(raw),
                    "purpose": item["purpose"], "source": item["source"], "bound": False}
        capture = item.get("capture")
        if capture is not None:
            if item["purpose"] != "candidate" or not isinstance(capture, dict) or set(capture) != {"record", "sha256", "verifiedBy"} or not _text(capture["verifiedBy"]):
                raise BoundaryError("invalid verified capture reference")
            captured_raw = read_local(root, capture["record"], 1024 * 1024)
            captured = strict_json(captured_raw)
            if digest(captured_raw) != capture["sha256"] or not isinstance(captured, dict) or set(captured) != {"command", "head", "tree", "scenario", "viewport", "output", "invocation"}:
                raise BoundaryError("capture record digest or fields mismatch")
            if not all(_text(captured[key]) for key in ("command", "head", "tree", "scenario")) or not isinstance(captured["viewport"], list) or len(captured["viewport"]) != 2 or not all(type(n) is int and n > 0 for n in captured["viewport"]):
                raise BoundaryError("capture lacks command, candidate, scene, or viewport")
            if captured["output"] != {"path": item["path"], "sha256": snapshot["sha256"]}:
                raise BoundaryError("capture output differs from original image")
            invocation = captured["invocation"]
            if not isinstance(invocation, dict) or set(invocation) != {"path", "sha256"}:
                raise BoundaryError("capture requires actual invocation evidence")
            log = read_local(root, invocation["path"], 1024 * 1024)
            if digest(log) != invocation["sha256"] or not all(value.encode() in log for value in (captured["command"], captured["head"], captured["tree"], snapshot["sha256"])):
                raise BoundaryError("invocation evidence does not support capture")
            snapshot["capture"] = {**capture, "metadata": captured}
            for suffix, content in (("capture", captured_raw), ("invocation", log)):
                atomic_private(location / f"{image_id}.{suffix}", content)
                (location / f"{image_id}.{suffix}").chmod(0o400)
            snapshot["bound"] = (captured["head"], captured["tree"]) == (record["base_head"], record["candidate_tree"])
        atomic_private(location / image_id, raw)
        (location / image_id).chmod(0o400)
        snapshots.append(snapshot)
    record["images"] = snapshots
    store.save(record)


def image_paths(store, record: dict) -> list[Path]:
    paths = []
    for image in record.get("images", []):
        path = store.path(image.get("owner", record.get("image_owner", record["id"]))) / "images" / image["id"]
        raw = read_local(path.parent, path.name, image["bytes"])
        if path.stat().st_uid != os.getuid() or stat.S_IMODE(path.stat().st_mode) != 0o400 or digest(raw) != image["sha256"]:
            raise BoundaryError("original image snapshot changed")
        for suffix, expected in (("capture", image.get("capture", {}).get("sha256")),
                                 ("invocation", image.get("capture", {}).get("metadata", {}).get("invocation", {}).get("sha256"))):
            if expected and digest(read_local(path.parent, f"{image['id']}.{suffix}", 1024 * 1024)) != expected:
                raise BoundaryError("capture provenance snapshot changed")
        paths.append(path)
    return paths


def validate_visual(value: object, images: list[dict]) -> dict:
    if not isinstance(value, dict) or set(value) != {"status", "inputIds", "observations", "unchecked", "stoppedBecause"} or value["status"] not in ("COMPLETE", "STOPPED") or not _strings(value["inputIds"], required=True) or set(value["inputIds"]) != {item["id"] for item in images} or not _strings(value["unchecked"]):
        raise BoundaryError("invalid visual report or unknown input IDs")
    observations = value["observations"]
    if not isinstance(observations, list) or any(not isinstance(item, dict) or set(item) != {"inputId", "location", "observation", "inference", "comparison", "uncertainty"} or item["inputId"] not in value["inputIds"] or not all(_text(v) for v in item.values()) for item in observations):
        raise BoundaryError("visual observations require locatable evidence and known IDs")
    if value["status"] == "COMPLETE" and (value["stoppedBecause"] is not None or {item["inputId"] for item in observations} != set(value["inputIds"])):
        raise BoundaryError("visual completion lacks evidence")
    if value["status"] == "STOPPED" and not _text(value["stoppedBecause"]):
        raise BoundaryError("visual STOP lacks a reason")
    return value
