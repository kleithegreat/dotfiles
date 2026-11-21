use crate::paths;
use rusqlite::Connection;
use std::{fs, path::Path, time::Duration};

const BUSY_TIMEOUT: Duration = Duration::from_secs(5);

pub(crate) fn open_state_db() -> crate::Result<Connection> {
    open_state_db_at(&paths::db_path()?)
}

pub(crate) fn open_state_db_at(db_path: &Path) -> crate::Result<Connection> {
    if let Some(parent) = db_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let connection = Connection::open(db_path)?;
    // Several writers share this SQLite file across daemon tasks and CLI calls.
    connection.busy_timeout(BUSY_TIMEOUT)?;
    connection.execute_batch(
        "
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;
        ",
    )?;
    Ok(connection)
}
