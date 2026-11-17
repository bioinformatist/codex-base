use clap::{Parser, Subcommand};
use codex_improve::{
    Result,
    native::emit,
    session::{self, Start},
    state::StateStore,
};
use std::path::PathBuf;

#[derive(Parser)]
#[command(
    name = "codex-improve",
    about = "Improve 1.0.0-codex.20 connected native workflow"
)]
struct Cli {
    #[arg(long, global = true, hide = true)]
    state_home: Option<PathBuf>,
    #[command(subcommand)]
    command: Command,
}
#[derive(Subcommand)]
enum Command {
    /// Hold an App Server connection and one loaded implementation root. Control with JSON lines on stdin.
    Session {
        plan: PathBuf,
        repository: PathBuf,
        #[arg(long)]
        base: Option<String>,
        #[arg(long,value_parser=["economy","standard","deep","writer"])]
        lane: Option<String>,
        /// A clean host-managed worktree returned by the native worktree tool, at the exact base.
        #[arg(long)]
        worktree: Option<PathBuf>,
        #[arg(long,value_parser=[".agents",".codex"])]
        grant: Vec<String>,
        #[arg(long)]
        copy_from: Option<PathBuf>,
        #[arg(long)]
        include: Vec<String>,
    },
    /// Read the current authenticated task summary. This cannot reconnect or continue a root.
    Inspect { task_id: String },
    /// Remove a clean task-created worktree after explicit cleanup authorization and integration.
    Remove { task_id: String },
}
fn run(cli: Cli) -> Result<()> {
    let store = StateStore::new(cli.state_home.as_deref())?;
    match cli.command {
        Command::Session {
            plan,
            repository,
            base,
            lane,
            worktree,
            grant,
            copy_from,
            include,
        } => session::run(
            store,
            Start {
                plan,
                repository,
                base,
                lane,
                worktree,
                grants: grant,
                copy_from,
                includes: include,
            },
        ),
        Command::Inspect { task_id } => emit(&store.load(&task_id)?),
        Command::Remove { task_id } => {
            session::remove(&store, &task_id)?;
            emit(&serde_json::json!({"removed":task_id}))
        }
    }
}
fn main() {
    unsafe {
        nix::libc::umask(0o077);
    }
    if let Err(e) = run(Cli::parse()) {
        eprintln!("codex-improve: {e}");
        std::process::exit(2);
    }
}
