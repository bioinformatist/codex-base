pub mod contracts;
pub mod git_worktree;
pub mod reviews;
pub mod state;
pub mod transport;
pub mod visual;

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
pub fn ensure(condition: bool, message: impl Into<String>) -> Result<()> {
    if condition {
        Ok(())
    } else {
        Err(message.into().into())
    }
}
