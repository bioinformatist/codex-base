use std::{env, error::Error, fs, io::Write, os::unix::fs::PermissionsExt, path::Path};
use toml_edit::{DocumentMut, Item, TableLike};

type Result<T> = std::result::Result<T, Box<dyn Error>>;

fn merge(dst: &mut dyn TableLike, src: &dyn TableLike) {
    for (key, value) in src.iter() {
        if let Some((old_key, old)) = dst.get_key_value_mut(key) {
            if let (Some(dst), Some(src)) = (old.as_table_like_mut(), value.as_table_like()) {
                merge(dst, src);
                continue;
            }
            // Keep the user's comment on a key whose managed value changes.
            let decor = old
                .as_value()
                .map(|v| v.decor().clone())
                .or_else(|| old.as_table().map(|t| t.decor().clone()));
            let key_decor = (old_key.leaf_decor().clone(), old_key.dotted_decor().clone());
            dst.insert(key, value.clone());
            let (mut key, old) = dst.get_key_value_mut(key).unwrap();
            *key.leaf_decor_mut() = key_decor.0;
            *key.dotted_decor_mut() = key_decor.1;
            if let Some(decor) = decor {
                match old {
                    Item::Value(v) => *v.decor_mut() = decor,
                    Item::Table(t) => *t.decor_mut() = decor,
                    _ => {}
                }
            }
        } else {
            dst.insert(key, value.clone());
        }
    }
}

fn merge_file(managed: &Path, target: &Path) -> Result<()> {
    let managed = fs::read_to_string(managed)?.parse::<DocumentMut>()?;
    let mut document = match fs::read_to_string(target) {
        Ok(text) => text.parse::<DocumentMut>()?,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => DocumentMut::new(),
        Err(e) => return Err(e.into()),
    };
    merge(document.as_table_mut(), managed.as_table());
    let parent = target
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    fs::create_dir_all(parent)?;
    let mut temporary = tempfile::Builder::new()
        .prefix(".config.toml.")
        .tempfile_in(parent)?;
    temporary
        .as_file()
        .set_permissions(fs::Permissions::from_mode(0o600))?;
    temporary.write_all(document.to_string().as_bytes())?;
    temporary.as_file().sync_all()?;
    temporary.persist(target)?;
    Ok(())
}

fn main() {
    let args: Vec<_> = env::args_os().collect();
    let result = if args.len() == 3 {
        merge_file(Path::new(&args[1]), Path::new(&args[2]))
    } else {
        Err("usage: merge-codex-base-config MANAGED TARGET".into())
    };
    if let Err(e) = result {
        eprintln!("merge-codex-base-config: {e}");
        std::process::exit(2);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn comments_nested_dotted_inline_and_toml11() {
        let mut target = "# header\nmodel = 'old' # model choice\nkeep = 'user'\n[features] # features\ncontext.experimental = false # experiment\ninline = { enabled = false, delay = 250 } # tuning\n".parse::<DocumentMut>().unwrap();
        let managed = "model = 'new'\n[features]\ncontext.experimental = true\ninline = { enabled = true }\nunicode = \"\\e\"\ntime = 07:32\n".parse::<DocumentMut>().unwrap();
        merge(target.as_table_mut(), managed.as_table());
        let text = target.to_string();
        for comment in [
            "# header",
            "# model choice",
            "# features",
            "# experiment",
            "# tuning",
        ] {
            assert!(text.contains(comment), "{text}");
        }
        assert_eq!(target["keep"].as_str(), Some("user"));
        assert_eq!(
            target["features"]["inline"]["delay"].as_integer(),
            Some(250)
        );
        assert_eq!(
            target["features"]["context"]["experimental"].as_bool(),
            Some(true)
        );
        assert_eq!(
            target["features"]["inline"]["enabled"].as_bool(),
            Some(true)
        );
        let first = target.to_string();
        merge(target.as_table_mut(), managed.as_table());
        assert_eq!(first, target.to_string());
        target.to_string().parse::<DocumentMut>().unwrap();
    }

    #[test]
    fn inline_entry_replaced_by_array_of_tables() {
        let tmp = tempfile::tempdir().unwrap();
        let managed = tmp.path().join("managed.toml");
        let target = tmp.path().join("config.toml");
        fs::write(&managed, "[[settings.items]]\nname = 'new'\n").unwrap();
        fs::write(
            &target,
            "# settings\nsettings = {\n# items\nitems = [{ name = 'old' }], # item choice\nkeep = 'user', # user sibling\n} # tuning\n",
        )
        .unwrap();
        merge_file(&managed, &target).unwrap();
        let text = fs::read_to_string(&target).unwrap();
        let saved = text.parse::<DocumentMut>().unwrap();
        let items = &saved["settings"]["items"];
        assert_eq!(items.as_array().unwrap().len(), 1);
        assert_eq!(items[0]["name"].as_str(), Some("new"));
        assert_eq!(saved["settings"]["keep"].as_str(), Some("user"));
        for comment in [
            "# settings",
            "# items",
            "# item choice",
            "# user sibling",
            "# tuning",
        ] {
            assert!(text.contains(comment), "{text}");
        }
    }

    #[test]
    fn new_file_private_and_invalid_input_preserves_target() {
        let tmp = tempfile::tempdir().unwrap();
        let managed = tmp.path().join("managed.toml");
        let target = tmp.path().join("nested/config.toml");
        fs::write(&managed, "model = 'managed'\n").unwrap();
        merge_file(&managed, &target).unwrap();
        assert_eq!(
            fs::metadata(&target).unwrap().permissions().mode() & 0o777,
            0o600
        );
        let original = fs::read(&target).unwrap();
        merge_file(&managed, &target).unwrap();
        assert_eq!(fs::read(&target).unwrap(), original);
        fs::write(&managed, "broken = [").unwrap();
        assert!(merge_file(&managed, &target).is_err());
        assert_eq!(fs::read(&target).unwrap(), original);
        fs::write(&managed, "ok = true").unwrap();
        fs::write(&target, "invalid = [").unwrap();
        assert!(merge_file(&managed, &target).is_err());
        assert_eq!(fs::read_to_string(&target).unwrap(), "invalid = [");
    }
}
