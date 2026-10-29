use crate::{Result, ensure};
use serde::{
    Deserialize,
    de::{self, MapAccess, SeqAccess, Visitor},
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{collections::BTreeSet, fmt, fs, path::Path};

pub const CONTRACT: &str = "1.0.0-codex.19";
pub const WRITE_LANES: [&str; 4] = ["economy", "standard", "deep", "writer"];
pub const FINAL_LIMIT: usize = 64 * 1024;

// serde_json's Value accepts duplicate keys; every external JSON boundary must reject them.
struct Strict(Value);
impl<'de> Deserialize<'de> for Strict {
    fn deserialize<D: de::Deserializer<'de>>(d: D) -> std::result::Result<Self, D::Error> {
        struct StrictVisitor;
        impl<'de> Visitor<'de> for StrictVisitor {
            type Value = Strict;
            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("strict JSON")
            }
            fn visit_bool<E: de::Error>(self, v: bool) -> std::result::Result<Strict, E> {
                Ok(Strict(v.into()))
            }
            fn visit_i64<E: de::Error>(self, v: i64) -> std::result::Result<Strict, E> {
                Ok(Strict(v.into()))
            }
            fn visit_u64<E: de::Error>(self, v: u64) -> std::result::Result<Strict, E> {
                Ok(Strict(v.into()))
            }
            fn visit_f64<E: de::Error>(self, v: f64) -> std::result::Result<Strict, E> {
                serde_json::Number::from_f64(v)
                    .map(|n| Strict(n.into()))
                    .ok_or_else(|| E::custom("nonfinite JSON number"))
            }
            fn visit_str<E: de::Error>(self, v: &str) -> std::result::Result<Strict, E> {
                Ok(Strict(v.into()))
            }
            fn visit_none<E: de::Error>(self) -> std::result::Result<Strict, E> {
                Ok(Strict(Value::Null))
            }
            fn visit_unit<E: de::Error>(self) -> std::result::Result<Strict, E> {
                Ok(Strict(Value::Null))
            }
            fn visit_seq<A: SeqAccess<'de>>(
                self,
                mut a: A,
            ) -> std::result::Result<Strict, A::Error> {
                let mut values = Vec::new();
                while let Some(Strict(v)) = a.next_element()? {
                    values.push(v);
                }
                Ok(Strict(Value::Array(values)))
            }
            fn visit_map<A: MapAccess<'de>>(
                self,
                mut a: A,
            ) -> std::result::Result<Strict, A::Error> {
                let mut values = serde_json::Map::new();
                while let Some((k, Strict(v))) = a.next_entry::<String, Strict>()? {
                    if values.insert(k.clone(), v).is_some() {
                        return Err(de::Error::custom(format!("duplicate JSON key: {k}")));
                    }
                }
                Ok(Strict(Value::Object(values)))
            }
        }
        d.deserialize_any(StrictVisitor)
    }
}
pub fn strict_json(raw: &[u8]) -> Result<Value> {
    Ok(serde_json::from_slice::<Strict>(raw)?.0)
}
pub fn digest(raw: &[u8]) -> String {
    hex(&Sha256::digest(raw))
}
pub fn hex(raw: &[u8]) -> String {
    raw.iter().map(|b| format!("{b:02x}")).collect()
}
pub fn text(v: &Value) -> bool {
    v.as_str().is_some_and(|s| !s.trim().is_empty())
}
pub fn argument(v: &Value) -> bool {
    text(v) && !v.as_str().unwrap().chars().any(|c| (c as u32) < 32)
}
pub fn integer(v: &Value, min: u64, max: u64) -> bool {
    v.as_u64().is_some_and(|n| min <= n && n <= max)
}
pub fn strings(v: &Value, required: bool) -> bool {
    v.as_array()
        .is_some_and(|a| (!required || !a.is_empty()) && a.iter().all(argument) && unique(a))
}
pub fn unique(v: &[Value]) -> bool {
    v.iter()
        .map(Value::to_string)
        .collect::<BTreeSet<_>>()
        .len()
        == v.len()
}
pub fn keys(v: &Value, required: &[&str], optional: &[&str]) -> bool {
    v.as_object().is_some_and(|o| {
        required.iter().all(|k| o.contains_key(*k))
            && o.keys()
                .all(|k| required.contains(&k.as_str()) || optional.contains(&k.as_str()))
    })
}
pub fn member(v: &Value, choices: &[&str]) -> bool {
    v.as_str().is_some_and(|s| choices.contains(&s))
}
pub fn relative_path(v: &Value) -> bool {
    argument(v)
        && v.as_str().is_some_and(|s| {
            !s.contains('\\') && s.split('/').all(|p| !["", ".", ".."].contains(&p))
        })
}
pub fn array(v: &Value) -> Result<&Vec<Value>> {
    v.as_array().ok_or_else(|| "expected JSON array".into())
}
pub fn string(v: &Value) -> Result<&str> {
    v.as_str().ok_or_else(|| "expected JSON string".into())
}
pub fn argv(v: &Value) -> Result<Vec<String>> {
    array(v)?
        .iter()
        .map(|s| Ok(string(s)?.to_owned()))
        .collect()
}
pub fn id(v: &str, length: usize) -> bool {
    v.len() == length
        && v.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn block(lines: &[&str], name: &str) -> Result<Value> {
    let marker = format!("```json codex-improve-{name}");
    let starts: Vec<_> = lines
        .iter()
        .enumerate()
        .filter(|(_, l)| **l == marker)
        .map(|(i, _)| i)
        .collect();
    ensure(
        starts.len() == 1,
        format!("plan must contain exactly one {name} block"),
    )?;
    let start = starts[0] + 1;
    let end = lines[start..]
        .iter()
        .position(|l| *l == "```")
        .ok_or_else(|| format!("{name} block is unterminated"))?
        + start;
    let raw = lines[start..end].join("\n");
    ensure(
        raw.len() <= 16 * 1024,
        format!("{name} block exceeds 16 KiB"),
    )?;
    let value = strict_json(raw.as_bytes())?;
    ensure(
        value.is_object() && value["version"].as_u64() == Some(1),
        format!("{name} version must be 1"),
    )?;
    Ok(value)
}
pub fn parse_plan(raw: &[u8]) -> Result<Value> {
    ensure(
        !raw.is_empty() && raw.len() <= 1024 * 1024,
        "plan size is invalid",
    )?;
    let lines: Vec<_> = std::str::from_utf8(raw)?.lines().collect();
    let declared: Vec<_> = lines
        .iter()
        .filter(|l| l.starts_with("- **Improve contract**:"))
        .copied()
        .collect();
    ensure(
        declared == [format!("- **Improve contract**: `{CONTRACT}`")],
        format!(
            "plan must declare exactly one {CONTRACT} contract; finish older plans with their original runtime"
        ),
    )?;
    let mut env = block(&lines, "environment")?;
    ensure(
        keys(&env, &["version", "launcher", "probes"], &["cache"]),
        "invalid environment fields",
    )?;
    let valid_argv = |v: &Value| {
        v.as_array()
            .is_some_and(|a| (1..=32).contains(&a.len()) && a.iter().all(argument))
    };
    ensure(valid_argv(&env["launcher"]), "invalid environment launcher")?;
    ensure(
        env["probes"].as_array().is_some_and(|a| a.len() <= 32),
        "invalid environment probes",
    )?;
    for probe in array(&env["probes"])? {
        ensure(
            keys(probe, &["argv", "timeoutSeconds"], &[])
                && valid_argv(&probe["argv"])
                && integer(&probe["timeoutSeconds"], 1, 3600),
            "invalid environment probe",
        )?;
    }
    if env.get("cache").is_none() {
        env["cache"] = json!({"xdgScope":"execution"});
    }
    ensure(
        keys(&env["cache"], &["xdgScope"], &[])
            && member(&env["cache"]["xdgScope"], &["execution", "worktree"]),
        "invalid environment cache scope",
    )?;
    let mut routing = block(&lines, "routing")?;
    ensure(
        keys(
            &routing,
            &["version", "lane", "writePaths", "requiredEvidence"],
            &["inputs"],
        ) && member(
            &routing["lane"],
            &[
                "economy", "standard", "deep", "writer", "scout", "visual", "reviewer",
            ],
        ),
        "invalid plan routing",
    )?;
    let writable = member(&routing["lane"], &WRITE_LANES);
    ensure(
        strings(&routing["writePaths"], writable)
            && array(&routing["writePaths"])?
                .iter()
                .all(|p| relative_path(p) && p.as_str().unwrap().split('/').next() != Some(".git"))
            && (writable || array(&routing["writePaths"])?.is_empty()),
        "invalid routing writePaths",
    )?;
    ensure(
        strings(&routing["requiredEvidence"], false),
        "invalid requiredEvidence",
    )?;
    if routing.get("inputs").is_none() {
        routing["inputs"] = json!({});
    }
    let inputs = &routing["inputs"];
    ensure(
        keys(inputs, &[], &["writer", "visual", "imageLimits"]),
        "invalid routing inputs",
    )?;
    if routing["lane"] == "writer" {
        let w = &inputs["writer"];
        ensure(
            keys(
                w,
                &[
                    "facts",
                    "conclusions",
                    "audience",
                    "language",
                    "terminology",
                    "preserve",
                    "scope",
                    "acceptance",
                ],
                &[],
            ) && text(&w["audience"])
                && text(&w["language"])
                && ["conclusions", "preserve", "scope", "acceptance"]
                    .iter()
                    .all(|k| strings(&w[k], true))
                && strings(&w["terminology"], false)
                && w["facts"].as_array().is_some_and(|a| {
                    !a.is_empty()
                        && a.iter().all(|f| {
                            keys(f, &["fact", "source"], &[])
                                && text(&f["fact"])
                                && text(&f["source"])
                        })
                }),
            "writer requires complete settled materials",
        )?;
    }
    if let Some(v) = inputs.get("visual") {
        ensure(
            keys(v, &["executionId", "inputIds", "report"], &[])
                && text(&v["executionId"])
                && strings(&v["inputIds"], true)
                && v["report"].is_boolean(),
            "invalid required visual inputs",
        )?;
    }
    if let Some(v) = inputs.get("imageLimits") {
        ensure(
            keys(v, &["count", "perImageBytes", "totalBytes"], &[])
                && v.as_object()
                    .unwrap()
                    .values()
                    .all(|n| integer(n, 1, u64::MAX)),
            "invalid reviewed image limits",
        )?;
    }
    let gates = block(&lines, "gates")?;
    ensure(
        keys(&gates, &["version", "gates"], &[]) && gates["gates"].is_array(),
        "invalid plan gates",
    )?;
    let mut ids = BTreeSet::new();
    for gate in array(&gates["gates"])? {
        ensure(
            keys(
                gate,
                &[
                    "id",
                    "class",
                    "kind",
                    "check",
                    "invalidatedBy",
                    "environment",
                    "conditions",
                ],
                &[],
            ) && ["id", "check", "environment", "conditions"]
                .iter()
                .all(|k| text(&gate[k]))
                && member(
                    &gate["class"],
                    &["implementation gate", "deferred acceptance", "observation"],
                )
                && member(&gate["kind"], &["check", "review"])
                && strings(&gate["invalidatedBy"], true),
            "invalid gate entry",
        )?;
        let name = string(&gate["id"])?;
        ensure(
            name.as_bytes()[0].is_ascii_alphabetic()
                && name
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-'),
            "invalid gate ID",
        )?;
        ensure(ids.insert(name), "duplicate gate ID")?;
        ensure(
            gate["class"] != "implementation gate"
                || array(&routing["requiredEvidence"])?.contains(&gate["id"]),
            "implementation gates must be requiredEvidence",
        )?;
    }
    ensure(
        array(&routing["requiredEvidence"])?
            .iter()
            .all(|v| ids.contains(v.as_str().unwrap())),
        "unknown required gate ID",
    )?;
    Ok(json!({"environment":env,"routing":routing,"gates":gates["gates"]}))
}

pub fn read_roles(path: &Path) -> Result<Value> {
    let roles = strict_json(&fs::read(path)?)?;
    ensure(
        keys(
            &roles,
            &[
                "economy", "standard", "deep", "writer", "reviewer", "scout", "visual",
            ],
            &[],
        ),
        "invalid Improve roles",
    )?;
    for (name, role) in roles.as_object().unwrap() {
        ensure(
            keys(
                role,
                &[
                    "model",
                    "reasoningEffort",
                    "verbosity",
                    "sandbox",
                    "approval",
                    "networkAccess",
                    "tokenLimit",
                    "reminders",
                    "initialTimeout",
                    "followupTimeout",
                ],
                &[],
            ),
            format!("invalid role: {name}"),
        )?;
        ensure(
            member(
                &role["model"],
                &["gpt-6.1-sol", "gpt-6-luna", "gpt-6.1-terra"],
            ) && member(
                &role["reasoningEffort"],
                &["low", "medium", "high", "xhigh"],
            ) && member(&role["verbosity"], &["low", "medium"])
                && role["approval"] == "never",
            format!("invalid model settings: {name}"),
        )?;
        let writable = WRITE_LANES.contains(&name.as_str());
        ensure(
            role["sandbox"]
                == if writable {
                    "workspace-write"
                } else {
                    "read-only"
                }
                && role["networkAccess"].as_bool() == Some(writable && name != "writer"),
            format!("invalid role permissions: {name}"),
        )?;
        ensure(
            (role["tokenLimit"].is_null() || integer(&role["tokenLimit"], 1, 1000000))
                && role["reminders"]
                    .as_array()
                    .is_some_and(|a| a.iter().all(|r| integer(r, 1, 1000000)))
                && integer(&role["initialTimeout"], 1, 7200)
                && (role["followupTimeout"].is_null()
                    || integer(&role["followupTimeout"], 1, 7200)),
            format!("invalid role limits: {name}"),
        )?;
    }
    Ok(roles)
}
pub fn validate_executor(v: &Value) -> Result<()> {
    ensure(
        keys(
            v,
            &["status", "steps", "stoppedBecause", "filesChanged", "notes"],
            &[],
        ) && member(&v["status"], &["COMPLETE", "STOPPED"]),
        "invalid executor report shape",
    )?;
    for k in ["steps", "filesChanged", "notes"] {
        ensure(
            v[k].as_array()
                .is_some_and(|a| (k != "steps" || !a.is_empty()) && a.iter().all(text)),
            format!("invalid executor report {k}"),
        )?;
    }
    ensure(
        if v["status"] == "COMPLETE" {
            v["stoppedBecause"].is_null()
        } else {
            text(&v["stoppedBecause"])
                && string(&v["stoppedBecause"])?.trim().to_lowercase() != "none"
        },
        "invalid executor stop reason",
    )
}
pub fn validate_review(v: &Value) -> Result<()> {
    ensure(
        keys(
            v,
            &[
                "verdict",
                "summary",
                "findings",
                "coverage",
                "review_blockers",
                "deferred_acceptance",
            ],
            &[],
        ) && member(&v["verdict"], &["APPROVE", "REVISE", "BLOCK"])
            && text(&v["summary"]),
        "invalid review verdict shape",
    )?;
    for (k, fields) in [
        (
            "findings",
            vec![
                "check", "severity", "location", "claim", "evidence", "action",
            ],
        ),
        ("coverage", vec!["check", "status", "evidence"]),
        ("review_blockers", vec!["item", "impact"]),
        (
            "deferred_acceptance",
            vec!["check", "owner", "reason", "evidence_required"],
        ),
    ] {
        ensure(
            v[k].as_array().is_some_and(|a| {
                (k != "coverage" || !a.is_empty())
                    && a.iter().all(|item| {
                        keys(item, &fields, &[]) && item.as_object().unwrap().values().all(text)
                    })
            }),
            format!("invalid review {k}"),
        )?;
    }
    let findings = array(&v["findings"])?;
    let coverage = array(&v["coverage"])?;
    let blockers = array(&v["review_blockers"])?;
    ensure(
        findings
            .iter()
            .all(|f| member(&f["severity"], &["critical", "high", "medium", "low"]))
            && coverage
                .iter()
                .all(|c| member(&c["status"], &["PASS", "FAIL", "BLOCKED"])),
        "invalid review severity or coverage status",
    )?;
    let good = match string(&v["verdict"])? {
        "APPROVE" => {
            findings.is_empty()
                && blockers.is_empty()
                && coverage.iter().all(|c| c["status"] == "PASS")
        }
        "REVISE" => {
            !findings.is_empty()
                && blockers.is_empty()
                && coverage.iter().any(|c| c["status"] == "FAIL")
                && coverage.iter().all(|c| c["status"] != "BLOCKED")
        }
        _ => !blockers.is_empty() || coverage.iter().any(|c| c["status"] == "BLOCKED"),
    };
    ensure(good, "review verdict contradicts findings or coverage")
}

#[cfg(test)]
mod tests {
    use super::*;
    pub fn plan() -> Vec<u8> {
        format!("- **Improve contract**: `{CONTRACT}`\n```json codex-improve-environment\n{{\"version\":1,\"launcher\":[\"env\"],\"probes\":[]}}\n```\n```json codex-improve-routing\n{{\"version\":1,\"lane\":\"standard\",\"writePaths\":[\"*\"],\"requiredEvidence\":[]}}\n```\n```json codex-improve-gates\n{{\"version\":1,\"gates\":[]}}\n```\n").into_bytes()
    }
    #[test]
    fn strict_json_and_contract_boundary() {
        for raw in [
            r#"{"nested":{"x":1,"x":2}}"#,
            "NaN",
            "1e999",
            "{\"x\":Infinity}",
        ] {
            assert!(strict_json(raw.as_bytes()).is_err(), "{raw}");
        }
        for v in [json!(true), json!(1.0), json!(-1)] {
            assert!(!integer(&v, 1, 3600));
        }
        let raw = plan();
        let parsed = parse_plan(&raw).unwrap();
        assert_eq!(parsed["environment"]["cache"]["xdgScope"], "execution");
        assert!(
            parse_plan(
                String::from_utf8(raw.clone())
                    .unwrap()
                    .replace(CONTRACT, "1.0.0-codex.18")
                    .as_bytes()
            )
            .is_err()
        );
        assert!(
            parse_plan(
                String::from_utf8(raw)
                    .unwrap()
                    .replace("\"version\":1", "\"version\":true")
                    .as_bytes()
            )
            .is_err()
        );
        assert!(relative_path(&json!("src/**")));
        for path in ["/tmp", "a/../b", "a//b", "a\\b", "./a"] {
            assert!(!relative_path(&json!(path)));
        }
    }
}
