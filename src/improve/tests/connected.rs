#[test]
fn connected_native_contract() {
    let source = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let result = std::process::Command::new("python3")
        .arg(source.join("tests/connected.py"))
        .arg(env!("CARGO_BIN_EXE_codex-improve"))
        .arg(source.join("../../plugins/codex-base/skills/improve"))
        .status()
        .unwrap();
    assert!(result.success());
}
