//! Ownership of the per-user command socket.
//!
//! Shutdown may delete the socket only when this process bound it.
//! A second start that finds a live listener must leave that socket alone.

use std::fs;
use std::path::Path;

const ALREADY_RUNNING: &str = "another daemon is already running";

/// A live listener already owns the socket. Do not bind, and do not treat
/// this process as the owner.
pub fn refuse_if_live(socket_exists: bool, connect_ok: bool) -> Result<(), &'static str> {
    if socket_exists && connect_ok {
        Err(ALREADY_RUNNING)
    } else {
        Ok(())
    }
}

/// Remembers whether this process successfully bound the command socket.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CommandSocketOwner {
    bound: bool,
}

impl CommandSocketOwner {
    pub const fn new() -> Self {
        Self { bound: false }
    }

    pub fn mark_bound(&mut self) {
        self.bound = true;
    }

    /// Remove `path` on shutdown only when this process bound that socket.
    pub fn unlink_on_shutdown(self, path: &Path) {
        if self.bound {
            let _ = fs::remove_file(path);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::net::{UnixListener, UnixStream};
    use std::sync::atomic::{AtomicU64, Ordering};

    struct Scratch {
        path: std::path::PathBuf,
    }

    impl Scratch {
        fn new() -> Self {
            static NEXT: AtomicU64 = AtomicU64::new(0);
            let n = NEXT.fetch_add(1, Ordering::Relaxed);
            // macOS rejects Unix socket paths at SUN_LEN (about 104 bytes).
            // `std::env::temp_dir()` is under /var/folders and is too long.
            let path = std::path::PathBuf::from(format!("/tmp/np-{}-{}", std::process::id(), n));
            fs::create_dir_all(&path).unwrap();
            Self { path }
        }
    }

    impl Drop for Scratch {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    #[test]
    fn shutdown_leaves_socket_when_this_process_did_not_bind() {
        let scratch = Scratch::new();
        let path = scratch.path.join("nameplate.sock");
        let listener = UnixListener::bind(&path).unwrap();
        let owner = CommandSocketOwner::new();
        let error = refuse_if_live(true, true).unwrap_err();
        assert_eq!(error, ALREADY_RUNNING);
        assert!(!owner.bound);
        owner.unlink_on_shutdown(&path);
        assert!(
            path.exists(),
            "shutdown unlinked nameplate.sock even though this process did not bind it"
        );
        UnixStream::connect(&path).expect("first daemon is no longer reachable at the socket path");
        drop(listener);
    }

    #[test]
    fn shutdown_unlinks_socket_this_process_bound() {
        let scratch = Scratch::new();
        let path = scratch.path.join("nameplate.sock");
        let listener = UnixListener::bind(&path).unwrap();
        drop(listener);
        let mut owner = CommandSocketOwner::new();
        assert!(refuse_if_live(false, false).is_ok());
        owner.mark_bound();
        owner.unlink_on_shutdown(&path);
        assert!(
            !path.exists(),
            "shutdown left the socket this process bound"
        );
    }

    #[test]
    fn stale_socket_file_can_be_replaced_and_is_owned() {
        let scratch = Scratch::new();
        let path = scratch.path.join("nameplate.sock");
        fs::write(&path, b"stale").unwrap();
        let mut owner = CommandSocketOwner::new();
        assert!(refuse_if_live(true, false).is_ok());
        owner.mark_bound();
        owner.unlink_on_shutdown(&path);
        assert!(!path.exists());
    }
}
