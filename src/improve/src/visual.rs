use crate::{Result, contracts::*, ensure, state::*};
use image::{ImageDecoder, ImageFormat, ImageReader};
use nix::{
    fcntl::{OFlag, open, openat},
    sys::stat::Mode,
    unistd::getuid,
};
use serde_json::{Value, json};
use std::{
    fs::{self, File},
    io::{Cursor, Read},
    os::unix::fs::{MetadataExt, PermissionsExt},
    path::{Path, PathBuf},
};

pub fn read_local(root: &Path, name: &str, limit: u64) -> Result<Vec<u8>> {
    ensure(
        relative_path(&json!(name)),
        "input path must stay within its manifest directory",
    )?;
    let mut directory = open(
        root,
        OFlag::O_RDONLY | OFlag::O_DIRECTORY | OFlag::O_NOFOLLOW,
        Mode::empty(),
    )?;
    let parts: Vec<_> = name.split('/').collect();
    for part in &parts[..parts.len() - 1] {
        directory = openat(
            &directory,
            *part,
            OFlag::O_RDONLY | OFlag::O_DIRECTORY | OFlag::O_NOFOLLOW,
            Mode::empty(),
        )?;
    }
    let fd = openat(
        &directory,
        parts[parts.len() - 1],
        OFlag::O_RDONLY | OFlag::O_NOFOLLOW | OFlag::O_NONBLOCK,
        Mode::empty(),
    )?;
    let mut file = File::from(fd);
    let before = file.metadata()?;
    ensure(
        before.is_file() && before.len() > 0 && before.len() <= limit,
        "input is not a bounded readable regular file",
    )?;
    let mut raw = Vec::new();
    (&mut file)
        .take(limit.saturating_add(1))
        .read_to_end(&mut raw)?;
    let after = file.metadata()?;
    let current = nix::sys::stat::fstatat(
        &directory,
        parts[parts.len() - 1],
        nix::fcntl::AtFlags::AT_SYMLINK_NOFOLLOW,
    )?;
    let identity = |m: &fs::Metadata| {
        (
            m.dev(),
            m.ino(),
            m.len(),
            m.mtime(),
            m.mtime_nsec(),
            m.ctime(),
            m.ctime_nsec(),
        )
    };
    ensure(
        raw.len() as u64 <= limit
            && identity(&before) == identity(&after)
            && (
                after.dev(),
                after.ino(),
                after.len(),
                after.mtime(),
                after.mtime_nsec(),
                after.ctime(),
                after.ctime_nsec(),
            ) == (
                current.st_dev,
                current.st_ino,
                current.st_size as u64,
                current.st_mtime,
                current.st_mtime_nsec,
                current.st_ctime,
                current.st_ctime_nsec,
            ),
        "input changed while reading",
    )?;
    let mut physical = root.to_owned();
    for part in parts {
        physical.push(part);
        ensure(
            !fs::symlink_metadata(&physical)?.is_symlink(),
            "input path contains a symlink",
        )?;
    }
    ensure(
        identity(&fs::metadata(physical)?) == identity(&after),
        "input path changed while reading",
    )?;
    Ok(raw)
}
pub fn decode(raw: &[u8]) -> Result<Value> {
    let format = image::guess_format(raw)?;
    ensure(
        matches!(format, ImageFormat::Png | ImageFormat::Jpeg),
        "only static PNG/JPEG inputs are supported",
    )?;
    if format == ImageFormat::Png {
        ensure(
            !image::codecs::png::PngDecoder::new(Cursor::new(raw))?.is_apng()?,
            "only static PNG/JPEG inputs are supported",
        )?;
    }
    let decoder = ImageReader::with_format(Cursor::new(raw), format).into_decoder()?;
    let (width, height) = decoder.dimensions();
    ensure(
        width > 0 && height > 0 && u64::from(width) * u64::from(height) <= 89_478_485,
        "image exceeds pixel limit",
    )?;
    let mut pixels = vec![0; usize::try_from(decoder.total_bytes())?];
    decoder.read_image(&mut pixels)?;
    Ok(
        json!({"format":if format == ImageFormat::Png { "PNG" } else { "JPEG" },"width":width,"height":height}),
    )
}
pub fn import_images(store: &StateStore, record: &mut Value, manifest: &Path) -> Result<()> {
    let manifest = std::path::absolute(manifest)?;
    let root = manifest.parent().ok_or("missing manifest parent")?;
    let payload = strict_json(&read_local(
        root,
        manifest
            .file_name()
            .ok_or("missing manifest name")?
            .to_str()
            .ok_or("non-UTF8 manifest")?,
        64 * 1024,
    )?)?;
    ensure(
        keys(&payload, &["version", "images"], &[]) && payload["version"].as_u64() == Some(1),
        "invalid image manifest",
    )?;
    let defaults = json!({"count":8,"perImageBytes":20*1024*1024,"totalBytes":50*1024*1024});
    let limits = record["plan_settings"]["routing"]["inputs"]
        .get("imageLimits")
        .unwrap_or(&defaults);
    let images = array(&payload["images"])?;
    ensure(
        !images.is_empty()
            && images.len() as u64 <= limits["count"].as_u64().ok_or("invalid count")?,
        "image count exceeds reviewed limits or is empty",
    )?;
    let location = private_dir(&store.path(string(&record["id"])?)?.join("images"))?;
    let mut snapshots = Vec::new();
    let mut total = 0u64;
    for item in images {
        ensure(
            keys(item, &["path", "purpose", "source"], &["capture"])
                && member(&item["purpose"], &["reference", "candidate"])
                && text(&item["source"]),
            "invalid image entry",
        )?;
        let raw = read_local(
            root,
            string(&item["path"])?,
            limits["perImageBytes"]
                .as_u64()
                .ok_or("invalid byte limit")?,
        )?;
        total = total
            .checked_add(raw.len() as u64)
            .ok_or("image bytes overflow")?;
        ensure(
            total <= limits["totalBytes"].as_u64().ok_or("invalid total limit")?,
            "total image bytes exceed reviewed limits",
        )?;
        let image_id = new_id()?;
        let mut snapshot = decode(&raw)?;
        for (k,v) in json!({"id":image_id,"sha256":digest(&raw),"bytes":raw.len(),"purpose":item["purpose"],"source":item["source"],"bound":false}).as_object().unwrap() { snapshot[k] = v.clone(); }
        if let Some(capture) = item.get("capture").filter(|v| !v.is_null()) {
            ensure(
                item["purpose"] == "candidate"
                    && keys(capture, &["record", "sha256", "verifiedBy"], &[])
                    && text(&capture["verifiedBy"]),
                "invalid verified capture reference",
            )?;
            let captured_raw = read_local(root, string(&capture["record"])?, 1024 * 1024)?;
            let captured = strict_json(&captured_raw)?;
            ensure(
                digest(&captured_raw) == capture["sha256"]
                    && keys(
                        &captured,
                        &[
                            "command",
                            "head",
                            "tree",
                            "scenario",
                            "viewport",
                            "output",
                            "invocation",
                        ],
                        &[],
                    ),
                "capture record digest or fields mismatch",
            )?;
            ensure(
                ["command", "head", "tree", "scenario"]
                    .iter()
                    .all(|k| text(&captured[k]))
                    && captured["viewport"]
                        .as_array()
                        .is_some_and(|a| a.len() == 2 && a.iter().all(|n| integer(n, 1, u64::MAX))),
                "capture lacks command, candidate, scene, or viewport",
            )?;
            ensure(
                captured["output"] == json!({"path":item["path"],"sha256":snapshot["sha256"]}),
                "capture output differs from original image",
            )?;
            let invocation = &captured["invocation"];
            ensure(
                keys(invocation, &["path", "sha256"], &[]),
                "capture requires actual invocation evidence",
            )?;
            let log = read_local(root, string(&invocation["path"])?, 1024 * 1024)?;
            ensure(
                digest(&log) == invocation["sha256"]
                    && [
                        &captured["command"],
                        &captured["head"],
                        &captured["tree"],
                        &snapshot["sha256"],
                    ]
                    .iter()
                    .all(|v| {
                        v.as_str()
                            .is_some_and(|s| log.windows(s.len()).any(|w| w == s.as_bytes()))
                    }),
                "invocation evidence does not support capture",
            )?;
            snapshot["capture"] = capture.clone();
            snapshot["capture"]["metadata"] = captured.clone();
            for (suffix, content) in [("capture", captured_raw), ("invocation", log)] {
                let path = location.join(format!("{image_id}.{suffix}"));
                atomic_private(&path, &content)?;
                fs::set_permissions(path, fs::Permissions::from_mode(0o400))?;
            }
            snapshot["bound"] = (captured["head"] == record["base_head"]
                && captured["tree"] == record["candidate_tree"])
                .into();
        }
        let path = location.join(&image_id);
        atomic_private(&path, &raw)?;
        fs::set_permissions(path, fs::Permissions::from_mode(0o400))?;
        snapshots.push(snapshot);
    }
    record["images"] = snapshots.into();
    store.save(record)
}
pub fn image_paths(store: &StateStore, record: &Value) -> Result<Vec<PathBuf>> {
    let mut paths = Vec::new();
    if let Some(images) = record.get("images") {
        for image in array(images)? {
            let owner = image
                .get("owner")
                .or_else(|| record.get("image_owner"))
                .unwrap_or(&record["id"]);
            let image_id = string(&image["id"])?;
            ensure(id(image_id, 32), "invalid image ID")?;
            let path = store.path(string(owner)?)?.join("images").join(image_id);
            let raw = read_local(
                path.parent().unwrap(),
                image_id,
                image["bytes"].as_u64().ok_or("invalid image bytes")?,
            )?;
            let m = fs::metadata(&path)?;
            ensure(
                m.uid() == getuid().as_raw()
                    && m.mode() & 0o777 == 0o400
                    && digest(&raw) == image["sha256"],
                "original image snapshot changed",
            )?;
            for (suffix, expected) in [
                ("capture", &image["capture"]["sha256"]),
                (
                    "invocation",
                    &image["capture"]["metadata"]["invocation"]["sha256"],
                ),
            ] {
                if !expected.is_null() {
                    ensure(
                        digest(&read_local(
                            path.parent().unwrap(),
                            &format!("{image_id}.{suffix}"),
                            1024 * 1024,
                        )?) == *expected,
                        "capture provenance snapshot changed",
                    )?;
                }
            }
            paths.push(path);
        }
    }
    Ok(paths)
}
pub fn validate_visual(v: &Value, images: &[Value]) -> Result<()> {
    ensure(
        keys(
            v,
            &[
                "status",
                "inputIds",
                "observations",
                "unchecked",
                "stoppedBecause",
            ],
            &[],
        ) && member(&v["status"], &["COMPLETE", "STOPPED"])
            && strings(&v["inputIds"], true)
            && strings(&v["unchecked"], false),
        "invalid visual report",
    )?;
    let ids = array(&v["inputIds"])?;
    ensure(
        ids.len() == images.len() && images.iter().all(|i| ids.contains(&i["id"])),
        "unknown visual input IDs",
    )?;
    let observations = array(&v["observations"])?;
    ensure(
        observations.iter().all(|o| {
            keys(
                o,
                &[
                    "inputId",
                    "location",
                    "observation",
                    "inference",
                    "comparison",
                    "uncertainty",
                ],
                &[],
            ) && ids.contains(&o["inputId"])
                && o.as_object().unwrap().values().all(text)
        }),
        "visual observations require locatable evidence and known IDs",
    )?;
    ensure(
        if v["status"] == "COMPLETE" {
            v["stoppedBecause"].is_null()
                && ids
                    .iter()
                    .all(|i| observations.iter().any(|o| &o["inputId"] == i))
        } else {
            text(&v["stoppedBecause"])
        },
        "visual completion lacks evidence or STOP lacks a reason",
    )
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn original_decode_and_safe_read() {
        let dir = tempfile::tempdir().unwrap();
        let mut bytes = Cursor::new(Vec::new());
        image::DynamicImage::new_rgb8(12, 8)
            .write_to(&mut bytes, ImageFormat::Png)
            .unwrap();
        let raw = bytes.into_inner();
        fs::write(dir.path().join("image"), &raw).unwrap();
        assert_eq!(decode(&raw).unwrap()["width"], 12);
        assert_eq!(
            read_local(dir.path(), "image", raw.len() as u64).unwrap(),
            raw
        );
        std::os::unix::fs::symlink("image", dir.path().join("link")).unwrap();
        for (name, limit) in [("../image", 1024), ("link", 1024), ("image", 1)] {
            assert!(read_local(dir.path(), name, limit).is_err());
        }
        let mut jpeg = Cursor::new(Vec::new());
        image::DynamicImage::new_rgb8(12, 8)
            .write_to(&mut jpeg, ImageFormat::Jpeg)
            .unwrap();
        assert_eq!(decode(jpeg.get_ref()).unwrap()["format"], "JPEG");
        assert!(decode(&raw[..raw.len() / 2]).is_err());
        let report = json!({"status":"COMPLETE","inputIds":["image"],"observations":[{"inputId":"unknown","location":"whole","observation":"pixel","inference":"none","comparison":"none","uncertainty":"none"}],"unchecked":[],"stoppedBecause":null});
        assert!(validate_visual(&report, &[json!({"id":"image"})]).is_err());
        assert!(decode(b"\x89PNG\r\n\x1a\nnot an image").is_err());
    }
}
