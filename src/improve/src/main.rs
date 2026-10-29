use clap::{Parser, Subcommand};
use codex_improve::{Result, state::StateStore};
use std::path::PathBuf;

mod lifecycle;

#[derive(Parser)]
#[command(
    name = "codex-improve",
    about = "Improve 1.0.0-codex.19 native runtime"
)]
struct Cli {
    #[arg(long, global = true, hide = true)]
    state_home: Option<PathBuf>,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Create a clean Worktrunk worktree and run an approved plan.
    Execute {
        plan: PathBuf,
        repository: PathBuf,
        #[arg(long, value_parser = ["economy", "standard", "deep", "writer"])]
        lane: Option<String>,
        #[arg(long)]
        base: Option<String>,
        #[arg(long, value_parser = [".agents", ".codex"])]
        grant: Vec<String>,
        #[arg(long)]
        copy_from: Option<PathBuf>,
        #[arg(long)]
        include: Vec<String>,
    },
    /// Run an independent read-only scout.
    Scout {
        worktree: PathBuf,
        tree: String,
        dossier: PathBuf,
    },
    /// Inspect private PNG/JPEG snapshots read-only.
    Visual {
        worktree: PathBuf,
        tree: String,
        dossier: PathBuf,
        #[arg(long)]
        inputs: PathBuf,
    },
    /// Run an independent read-only review.
    Review {
        execution_id: String,
        tree: String,
        dossier: PathBuf,
        #[arg(long)]
        retry_of: Option<String>,
        #[arg(long)]
        retry_authorized: bool,
    },
    /// Record evidence-backed main-agent review dispositions.
    Reconcile { review_id: String, dossier: PathBuf },
    /// Inspect authenticated private state without a model call.
    Status { execution_id: Option<String> },
    /// Print full HEAD and candidate tree.
    Candidate { worktree: PathBuf },
    /// Commit an exact candidate or integrate a reviewed OID.
    Checkpoint {
        execution_id: String,
        tree: Option<String>,
        #[arg(long)]
        message: Option<String>,
        #[arg(long)]
        integrate_oid: Option<String>,
        #[arg(long)]
        target: Option<PathBuf>,
        #[arg(long)]
        expected_target: Option<String>,
    },
    /// Retry a failed preflight once.
    Resume { execution_id: String },
    /// Run one bounded serial recovery.
    Recover {
        execution_id: String,
        #[arg(required = true, num_args = 1..)]
        slices: Vec<PathBuf>,
        #[arg(long)]
        expected_tree: String,
        #[arg(long, value_parser = [".agents", ".codex"])]
        grant: Vec<String>,
    },
    /// Run a bounded review revision.
    Revise {
        execution_id: String,
        findings: PathBuf,
        #[arg(long)]
        expected_tree: String,
        #[arg(long, value_parser = [".agents", ".codex"])]
        grant: Vec<String>,
    },
    /// Start at a protected exact checkpoint.
    Next {
        execution_id: String,
        checkpoint_oid: String,
        plan: PathBuf,
        #[arg(long, value_parser = ["economy", "standard", "deep", "writer"])]
        lane: Option<String>,
        #[arg(long, value_parser = [".agents", ".codex"])]
        grant: Vec<String>,
    },
    #[command(name = "_worker", hide = true)]
    Worker { execution_id: String },
}

fn run(cli: Cli) -> Result<i32> {
    let store = StateStore::new(cli.state_home.as_deref())?;
    let runtime = lifecycle::Runtime::new(store)?;
    let result = runtime.dispatch(cli.command)?;
    println!("{}", serde_json::to_string(&result)?);
    Ok(if result["outcome"] == "INCONCLUSIVE" {
        1
    } else {
        0
    })
}
fn main() {
    // All state and process artifacts stay private, including children-created output.
    unsafe {
        nix::libc::umask(0o077);
    }
    let code = run(Cli::parse()).unwrap_or_else(|e| {
        eprintln!("codex-improve: {e}");
        2
    });
    std::process::exit(code);
}
