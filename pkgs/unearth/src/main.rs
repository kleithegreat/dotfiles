use std::collections::{HashMap, HashSet};
use std::env;
use std::error::Error;
use std::ffi::{c_char, c_int};
use std::fmt;
use std::fs::{self, OpenOptions};
use std::io::ErrorKind;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant, UNIX_EPOCH};

use clap::{Parser, Subcommand};
use rusqlite::{Connection, ffi, params};
use serde::{Deserialize, Serialize};
use serde_json::json;

type Result<T> = std::result::Result<T, Box<dyn Error>>;

const PORT: &str = "8737";
const PROMPT_VERSION: &str = "embeddinggemma-2-v1";
const EMBED_READY_DEADLINE: Duration = Duration::from_secs(30);
const CHUNK_BYTES: usize = 1500;
// Longer "words" are base64, hashes and the like; they also risk overflowing a batch.
const MAX_WORD_BYTES: usize = 200;
const MAX_TEXT_BYTES: u64 = 4 << 20;
const TEXT_EXTENSIONS: &[&str] = &["txt", "md", "markdown", "org", "rst", "tex"];
const EMBED_BATCH: usize = 32;
const CANDIDATES: usize = 50;
const SNIPPET_CHARS: usize = 200;
const RRF_K: f64 = 60.0;

const SCHEMA: &str = "
    CREATE TABLE IF NOT EXISTS files (
        id INTEGER PRIMARY KEY,
        path TEXT NOT NULL UNIQUE,
        mtime INTEGER NOT NULL,
        size INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
    CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING fts5(text, file UNINDEXED, page UNINDEXED);
    CREATE VIRTUAL TABLE IF NOT EXISTS embeddings USING vec0(embedding float[768]);
";

#[derive(Debug)]
struct ServerUnavailable(String);

impl fmt::Display for ServerUnavailable {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl Error for ServerUnavailable {}

#[derive(Parser)]
#[command(about = "Local semantic search over documents")]
struct Cli {
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Run the embedding server.
    Serve,
    /// Embed new and changed documents under the roots and forget vanished ones.
    Index { roots: Vec<PathBuf> },
    /// Print the best-matching documents as JSON.
    Search {
        query: String,
        /// Match words only, without the embedding server.
        #[arg(long)]
        keyword_only: bool,
        #[arg(long, default_value_t = 20)]
        limit: usize,
    },
}

enum Kind {
    Pdf,
    Text,
}

struct Chunk {
    page: Option<i64>,
    text: String,
}

struct Candidate {
    file: i64,
    page: Option<i64>,
    snippet: String,
    score: f64,
}

#[derive(Serialize)]
struct Hit {
    path: String,
    page: Option<i64>,
    snippet: String,
}

#[derive(Deserialize)]
struct Embeddings {
    data: Vec<Embedding>,
}

#[derive(Deserialize)]
struct Embedding {
    index: usize,
    embedding: Vec<f32>,
}

fn main() -> Result<()> {
    match Cli::parse().command {
        Cmd::Serve => serve(),
        Cmd::Index { roots } => {
            let (state, db) = open()?;
            let agent = ureq::Agent::new_with_defaults();
            index(&state, &db, &roots, on_ac_power, |inputs| {
                embed(&agent, inputs)
            })
        }
        Cmd::Search {
            query,
            keyword_only,
            limit,
        } => {
            let (_, db) = open()?;
            let agent = ureq::Agent::new_with_defaults();
            let hits = search(&db, &query, keyword_only, limit, |inputs| {
                embed(&agent, inputs)
            })?;
            println!("{}", serde_json::to_string(&hits)?);
            Ok(())
        }
    }
}

fn serve() -> Result<()> {
    let model = env::var("UNEARTH_MODEL").map_err(|_| "UNEARTH_MODEL is unset")?;
    Err(Command::new("llama-server")
        .args(["--model", &model, "--embeddings", "--no-webui"])
        .args(["--host", "127.0.0.1", "--port", PORT])
        // Four 2048-token slots; a chunk plus its title stays well inside one.
        .args(["--ctx-size", "8192", "--parallel", "4"])
        .args(["--batch-size", "2048", "--ubatch-size", "2048"])
        .args(["--sleep-idle-seconds", "300"])
        .exec()
        .into())
}

fn register_vec() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        type Init = unsafe extern "C" fn(
            *mut ffi::sqlite3,
            *mut *mut c_char,
            *const ffi::sqlite3_api_routines,
        ) -> c_int;
        unsafe {
            ffi::sqlite3_auto_extension(Some(std::mem::transmute::<*const (), Init>(
                sqlite_vec::sqlite3_vec_init as *const (),
            )));
        }
    });
}

fn state_dir() -> Result<PathBuf> {
    let base = match env::var_os("XDG_STATE_HOME") {
        Some(dir) => PathBuf::from(dir),
        None => PathBuf::from(env::var_os("HOME").ok_or("HOME is unset")?).join(".local/state"),
    };
    Ok(base.join("unearth"))
}

fn open() -> Result<(PathBuf, Connection)> {
    register_vec();
    let state = state_dir()?;
    fs::create_dir_all(&state)?;
    let db = Connection::open(state.join("index.db"))?;
    db.pragma_update(None, "journal_mode", "WAL")?;
    db.busy_timeout(Duration::from_secs(5))?;
    db.execute_batch(SCHEMA)?;
    Ok((state, db))
}

fn check_meta(db: &Connection, current_model: Option<&str>, record: bool) -> Result<()> {
    let has_files: bool =
        db.query_row("SELECT EXISTS(SELECT 1 FROM files)", [], |row| row.get(0))?;
    let mut stored_model: Option<String> = None;
    let mut stored_prompt: Option<String> = None;
    {
        let mut stmt = db.prepare("SELECT key, value FROM meta")?;
        for row in stmt.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })? {
            let (key, value) = row?;
            match key.as_str() {
                "model" => stored_model = Some(value),
                "prompt_version" => stored_prompt = Some(value),
                _ => {}
            }
        }
    }

    if has_files {
        if stored_prompt.as_deref() != Some(PROMPT_VERSION) {
            eprintln!(
                "warning: index prompt version ({}) differs from current ({PROMPT_VERSION}); delete index.db to rebuild",
                stored_prompt.as_deref().unwrap_or("untracked"),
            );
        }
        if let Some(model) = current_model
            && stored_model.as_deref() != Some(model)
        {
            eprintln!(
                "warning: index model ({}) differs from current ({model}); delete index.db to rebuild",
                stored_model.as_deref().unwrap_or("untracked"),
            );
        }
    } else if record {
        db.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('prompt_version', ?1)",
            [PROMPT_VERSION],
        )?;
        match current_model {
            Some(model) => {
                db.execute(
                    "INSERT OR REPLACE INTO meta (key, value) VALUES ('model', ?1)",
                    [model],
                )?;
            }
            None => {
                db.execute("DELETE FROM meta WHERE key = 'model'", [])?;
            }
        }
    }
    Ok(())
}

fn index<P, F>(
    state: &Path,
    db: &Connection,
    roots: &[PathBuf],
    mut on_ac: P,
    mut embed_fn: F,
) -> Result<()>
where
    P: FnMut() -> bool,
    F: FnMut(&[String]) -> Result<Vec<Vec<f32>>>,
{
    let lock_file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(state.join("index.lock"))?;
    lock_file.lock()?;

    let current_model = env::var("UNEARTH_MODEL").ok();

    let mut documents = Vec::new();
    let mut seen = HashSet::new();
    for root in roots {
        walk(root, &mut seen, &mut documents);
    }
    documents.sort_unstable();
    let present: HashSet<&str> = documents.iter().map(String::as_str).collect();

    let known: HashMap<String, (i64, i64, i64)> = db
        .prepare("SELECT path, id, mtime, size FROM files")?
        .query_map([], |row| {
            Ok((row.get(0)?, (row.get(1)?, row.get(2)?, row.get(3)?)))
        })?
        .collect::<rusqlite::Result<_>>()?;
    let vanished: Vec<i64> = known
        .iter()
        .filter(|(path, _)| !present.contains(path.as_str()))
        .map(|(_, &(file, ..))| file)
        .collect();
    forget_files(db, &vanished)?;

    check_meta(db, current_model.as_deref(), true)?;

    for path in &documents {
        let Ok(metadata) = fs::metadata(path) else {
            continue;
        };
        let Ok(modified) = metadata.modified() else {
            continue;
        };
        let Ok(duration) = modified.duration_since(UNIX_EPOCH) else {
            eprintln!("{path}: modification time predates UNIX epoch, skipping");
            continue;
        };
        let mtime = duration.as_nanos() as i64;
        let size = metadata.len() as i64;
        let previous = known.get(path);
        if previous.is_some_and(|&(_, m, s)| (m, s) == (mtime, size)) {
            continue;
        }
        if !on_ac() {
            eprintln!("on battery, deferring the rest");
            return Ok(());
        }

        if let Err(error) = index_file(
            db,
            path,
            mtime,
            size,
            previous.map(|&(id, ..)| id),
            &mut embed_fn,
        ) {
            if error.downcast_ref::<ServerUnavailable>().is_some() {
                return Err(error);
            }
            eprintln!("{path}: {error}");
        }
    }
    Ok(())
}

fn index_file<F>(
    db: &Connection,
    path: &str,
    mtime: i64,
    size: i64,
    previous_id: Option<i64>,
    embed_fn: &mut F,
) -> Result<()>
where
    F: FnMut(&[String]) -> Result<Vec<Vec<f32>>>,
{
    // A file that fails to extract is still recorded, so it is retried only once it changes.
    let chunks = extract(Path::new(path)).unwrap_or_else(|error| {
        eprintln!("{path}: {error}");
        Vec::new()
    });
    let title = Path::new(path)
        .file_name()
        .unwrap_or_default()
        .to_string_lossy();
    let inputs: Vec<String> = chunks
        .iter()
        .map(|chunk| format!("title: {title} | text: {}", chunk.text))
        .collect();
    let vectors = embed_fn(&inputs)?;
    if vectors.len() != chunks.len() {
        return Err(format!(
            "embedding count mismatch: got {} vectors for {} chunks",
            vectors.len(),
            chunks.len()
        )
        .into());
    }

    let tx = db.unchecked_transaction()?;
    if let Some(file) = previous_id {
        delete_file(&tx, file)?;
    }
    tx.execute(
        "INSERT INTO files (path, mtime, size) VALUES (?1, ?2, ?3)",
        params![path, mtime, size],
    )?;
    let file = tx.last_insert_rowid();
    for (chunk, vector) in chunks.iter().zip(&vectors) {
        tx.execute(
            "INSERT INTO chunks (text, file, page) VALUES (?1, ?2, ?3)",
            params![chunk.text, file, chunk.page],
        )?;
        tx.execute(
            "INSERT INTO embeddings (rowid, embedding) VALUES (?1, ?2)",
            params![tx.last_insert_rowid(), as_bytes(vector)],
        )?;
    }
    tx.commit()?;
    eprintln!("indexed {path} ({} chunks)", chunks.len());
    Ok(())
}

fn delete_file(db: &Connection, file: i64) -> Result<()> {
    let chunks: Vec<i64> = db
        .prepare("SELECT rowid FROM chunks WHERE file = ?1")?
        .query_map([file], |row| row.get(0))?
        .collect::<rusqlite::Result<_>>()?;
    for chunk in chunks {
        db.execute("DELETE FROM embeddings WHERE rowid = ?1", [chunk])?;
    }
    db.execute("DELETE FROM chunks WHERE file = ?1", [file])?;
    db.execute("DELETE FROM files WHERE id = ?1", [file])?;
    Ok(())
}

fn forget_files(db: &Connection, files: &[i64]) -> Result<()> {
    if files.is_empty() {
        return Ok(());
    }
    let tx = db.unchecked_transaction()?;
    for &file in files {
        delete_file(&tx, file)?;
    }
    tx.commit()?;
    Ok(())
}

fn walk(dir: &Path, seen: &mut HashSet<PathBuf>, documents: &mut Vec<String>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        if entry.file_name().to_string_lossy().starts_with('.') {
            continue;
        }
        let path = entry.path();
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_dir() {
            walk(&path, seen, documents);
        } else if file_type.is_file()
            && kind(&path).is_some()
            && let Some(text) = path.to_str().map(str::to_owned)
        {
            let key = fs::canonicalize(&path).unwrap_or(path);
            if seen.insert(key) {
                documents.push(text);
            }
        }
    }
}

fn kind(path: &Path) -> Option<Kind> {
    let extension = path.extension()?.to_str()?.to_ascii_lowercase();
    if extension == "pdf" {
        Some(Kind::Pdf)
    } else if TEXT_EXTENSIONS.contains(&extension.as_str()) {
        Some(Kind::Text)
    } else {
        None
    }
}

fn extract(path: &Path) -> Result<Vec<Chunk>> {
    Ok(match kind(path) {
        Some(Kind::Pdf) => {
            let output = Command::new("pdftotext").arg(path).arg("-").output()?;
            if !output.status.success() {
                return Err(String::from_utf8_lossy(&output.stderr).trim().into());
            }
            String::from_utf8_lossy(&output.stdout)
                .split('\x0c')
                .zip(1..)
                .flat_map(|(page, number)| {
                    split(page).into_iter().map(move |text| Chunk {
                        page: Some(number),
                        text,
                    })
                })
                .collect()
        }
        Some(Kind::Text) if fs::metadata(path)?.len() <= MAX_TEXT_BYTES => {
            split(&String::from_utf8_lossy(&fs::read(path)?))
                .into_iter()
                .map(|text| Chunk { page: None, text })
                .collect()
        }
        _ => Vec::new(),
    })
}

fn split(text: &str) -> Vec<String> {
    let mut chunks = vec![String::new()];
    for word in text
        .split_whitespace()
        .filter(|word| word.len() <= MAX_WORD_BYTES)
    {
        if chunks
            .last()
            .is_some_and(|chunk| chunk.len() + word.len() >= CHUNK_BYTES)
        {
            chunks.push(String::new());
        }
        let chunk = chunks.last_mut().expect("chunks starts non-empty");
        if !chunk.is_empty() {
            chunk.push(' ');
        }
        chunk.push_str(word);
    }
    chunks.retain(|chunk| !chunk.is_empty());
    chunks
}

fn embed(agent: &ureq::Agent, inputs: &[String]) -> Result<Vec<Vec<f32>>> {
    let url = format!("http://127.0.0.1:{PORT}/v1/embeddings");
    let mut vectors = Vec::with_capacity(inputs.len());
    for batch in inputs.chunks(EMBED_BATCH) {
        let body = json!({ "input": batch });
        let deadline = Instant::now() + EMBED_READY_DEADLINE;
        let mut response = loop {
            match agent.post(&url).send_json(&body) {
                Ok(response) => break response,
                // The server refuses connections briefly at startup and returns 503 while loading the model.
                Err(ureq::Error::StatusCode(503)) => {}
                Err(ureq::Error::Io(ref err)) if err.kind() == ErrorKind::ConnectionRefused => {}
                Err(error) => return Err(error.into()),
            }
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(Box::new(ServerUnavailable(format!(
                    "embedding server at {url} did not become ready within {}s",
                    EMBED_READY_DEADLINE.as_secs()
                ))));
            }
            thread::sleep(Duration::from_millis(250).min(remaining));
        };
        let mut embeddings: Embeddings = response.body_mut().read_json()?;
        if embeddings.data.len() != batch.len() {
            return Err(format!(
                "embedding server returned {} vectors for batch of {}",
                embeddings.data.len(),
                batch.len()
            )
            .into());
        }
        embeddings.data.sort_by_key(|embedding| embedding.index);
        vectors.extend(
            embeddings
                .data
                .into_iter()
                .map(|embedding| embedding.embedding),
        );
    }
    Ok(vectors)
}

fn as_bytes(vector: &[f32]) -> Vec<u8> {
    vector
        .iter()
        .flat_map(|value| value.to_le_bytes())
        .collect()
}

fn on_ac_power() -> bool {
    let Ok(supplies) = fs::read_dir("/sys/class/power_supply") else {
        return true;
    };
    let read =
        |supply: &Path, attribute| fs::read_to_string(supply.join(attribute)).unwrap_or_default();
    let mains: Vec<PathBuf> = supplies
        .flatten()
        .map(|supply| supply.path())
        .filter(|supply| read(supply, "type").trim() == "Mains")
        .collect();
    mains.is_empty()
        || mains
            .iter()
            .any(|supply| read(supply, "online").trim() == "1")
}

fn fts5_pattern(query: &str) -> Option<String> {
    let terms: Vec<String> = query
        .split(|c: char| !c.is_alphanumeric())
        .filter(|word| !word.is_empty())
        .map(|word| format!("\"{word}\""))
        .collect();
    if terms.is_empty() {
        None
    } else {
        // The trailing `*` lets the word still being typed match as a prefix.
        Some(terms.join(" ") + "*")
    }
}

fn add_rrf_rank(
    candidates: &mut HashMap<i64, Candidate>,
    chunk: i64,
    position: usize,
    file: i64,
    page: Option<i64>,
    snippet: String,
) {
    candidates
        .entry(chunk)
        .or_insert(Candidate {
            file,
            page,
            snippet,
            score: 0.0,
        })
        .score += 1.0 / (RRF_K + position as f64);
}

fn best_per_file(candidates: HashMap<i64, Candidate>, limit: usize) -> Vec<Candidate> {
    let mut best: HashMap<i64, Candidate> = HashMap::new();
    for candidate in candidates.into_values() {
        if best
            .get(&candidate.file)
            .is_none_or(|kept| kept.score < candidate.score)
        {
            best.insert(candidate.file, candidate);
        }
    }
    let mut ranked: Vec<Candidate> = best.into_values().collect();
    ranked.sort_by(|a, b| b.score.total_cmp(&a.score));
    ranked.truncate(limit);
    ranked
}

fn search<F>(
    db: &Connection,
    query: &str,
    keyword_only: bool,
    limit: usize,
    mut embed_fn: F,
) -> Result<Vec<Hit>>
where
    F: FnMut(&[String]) -> Result<Vec<Vec<f32>>>,
{
    if query.trim().is_empty() {
        return Ok(Vec::new());
    }
    if !keyword_only {
        check_meta(db, env::var("UNEARTH_MODEL").ok().as_deref(), false)?;
    }

    let mut candidates: HashMap<i64, Candidate> = HashMap::new();

    if let Some(pattern) = fts5_pattern(query) {
        let mut keyword = db.prepare(
            "SELECT rowid, file, page, snippet(chunks, 0, '', '', '…', 24)
             FROM chunks WHERE chunks MATCH ?1 ORDER BY rank LIMIT ?2",
        )?;
        match keyword.query_map(params![pattern, CANDIDATES], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        }) {
            Ok(rows) => {
                for (position, row) in rows.enumerate() {
                    let (chunk, file, page, snippet) = row?;
                    add_rrf_rank(&mut candidates, chunk, position, file, page, snippet);
                }
            }
            Err(error) if keyword_only => return Err(error.into()),
            Err(error) => {
                eprintln!("fts5 query failed, falling back to semantic search: {error}");
            }
        }
    } else if keyword_only {
        return Ok(Vec::new());
    }

    if !keyword_only {
        let vector = embed_fn(&[format!("task: search result | query: {query}")])?;
        if vector.len() != 1 {
            return Err(format!("expected 1 query embedding, got {}", vector.len()).into());
        }
        let mut semantic = db.prepare(
            "WITH knn AS (
                 SELECT rowid, distance FROM embeddings WHERE embedding MATCH ?1 AND k = ?2
             )
             SELECT knn.rowid, chunks.file, chunks.page, chunks.text
             FROM knn JOIN chunks ON chunks.rowid = knn.rowid ORDER BY knn.distance",
        )?;
        let rows = semantic.query_map(params![as_bytes(&vector[0]), CANDIDATES], |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get::<_, String>(3)?,
            ))
        })?;
        for (position, row) in rows.enumerate() {
            let (chunk, file, page, text) = row?;
            let mut snippet: String = text.chars().take(SNIPPET_CHARS).collect();
            if snippet.len() < text.len() {
                snippet.push('…');
            }
            add_rrf_rank(&mut candidates, chunk, position, file, page, snippet);
        }
    }

    let ranked = best_per_file(candidates, limit);

    let mut path = db.prepare("SELECT path FROM files WHERE id = ?1")?;
    ranked
        .into_iter()
        .map(|candidate| {
            Ok(Hit {
                path: path.query_row([candidate.file], |row| row.get(0))?,
                page: candidate.page,
                snippet: candidate.snippet,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    fn test_db() -> Connection {
        register_vec();
        let db = Connection::open_in_memory().unwrap();
        db.execute_batch(SCHEMA).unwrap();
        db
    }

    fn temp_dir() -> PathBuf {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let id = NEXT.fetch_add(1, Ordering::Relaxed);
        let dir = env::temp_dir().join(format!("unearth-test-{}-{id}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn split_respects_budget_and_drops_huge_tokens() {
        let huge = "x".repeat(MAX_WORD_BYTES + 1);
        let words: Vec<String> = (0..120).map(|i| format!("word{i:03}abcdefghij")).collect();
        let input = format!("{huge} {}", words.join(" "));
        let chunks = split(&input);
        assert!(chunks.len() > 1);
        for chunk in &chunks {
            assert!(!chunk.is_empty());
            assert!(!chunk.contains(&huge));
            assert!(chunk.len() < CHUNK_BYTES + MAX_WORD_BYTES);
        }
    }

    #[test]
    fn fts5_pattern_sanitizes_punctuation_and_operators() {
        assert_eq!(fts5_pattern("   "), None);
        assert_eq!(fts5_pattern("--- ??? ***"), None);
        assert_eq!(
            fts5_pattern("self-attention (NOT) \"quote\":*"),
            Some("\"self\" \"attention\" \"NOT\" \"quote\"*".to_owned())
        );

        let db = test_db();
        db.execute(
            "INSERT INTO chunks (text, file, page) VALUES (?1, 1, NULL)",
            ["Self-attention avoids NOT operators."],
        )
        .unwrap();
        for query in ["self-attention", "NOT", "\"quote\"", "a:b^c"] {
            let pattern = fts5_pattern(query).unwrap();
            let count: i64 = db
                .query_row(
                    "SELECT count(*) FROM chunks WHERE chunks MATCH ?1",
                    [pattern],
                    |row| row.get(0),
                )
                .unwrap();
            assert!(count <= 1);
        }
    }

    #[test]
    fn search_rrf_ranking_and_per_file_dedup() {
        let db = test_db();
        db.execute(
            "INSERT INTO files (id, path, mtime, size) VALUES (1, '/a.md', 1, 10), (2, '/b.md', 1, 10)",
            [],
        )
        .unwrap();

        let a1 = vec![1.0_f32; 768];
        let mut b1 = vec![0.0_f32; 768];
        b1[0] = 1.0;

        for (rowid, file, text, vec) in [
            (1, 1, "alpha needle match", &a1),
            (2, 1, "alpha needle second chunk", &b1),
            (3, 2, "beta topic", &b1),
        ] {
            db.execute(
                "INSERT INTO chunks (rowid, text, file, page) VALUES (?1, ?2, ?3, NULL)",
                params![rowid, text, file],
            )
            .unwrap();
            db.execute(
                "INSERT INTO embeddings (rowid, embedding) VALUES (?1, ?2)",
                params![rowid, as_bytes(vec)],
            )
            .unwrap();
        }

        let hits = search(&db, "alpha", false, 10, |_| Ok(vec![a1.clone()])).unwrap();
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].path, "/a.md");
        assert_eq!(hits[1].path, "/b.md");
    }

    #[test]
    fn forget_is_atomic_when_file_delete_fails() {
        let db = test_db();
        db.execute(
            "INSERT INTO files (id, path, mtime, size) VALUES (1, '/a.md', 1, 10)",
            [],
        )
        .unwrap();
        db.execute(
            "INSERT INTO chunks (rowid, text, file, page) VALUES (10, 'hello world', 1, NULL)",
            [],
        )
        .unwrap();
        db.execute(
            "INSERT INTO embeddings (rowid, embedding) VALUES (10, ?1)",
            [as_bytes(&vec![0.1_f32; 768])],
        )
        .unwrap();
        db.execute(
            "CREATE TRIGGER abort_file_delete BEFORE DELETE ON files
             BEGIN
                 SELECT RAISE(ABORT, 'simulated failure');
             END;",
            [],
        )
        .unwrap();

        assert!(forget_files(&db, &[1]).is_err());
        let files: i64 = db
            .query_row("SELECT count(*) FROM files", [], |r| r.get(0))
            .unwrap();
        let chunks: i64 = db
            .query_row("SELECT count(*) FROM chunks", [], |r| r.get(0))
            .unwrap();
        let embeddings: i64 = db
            .query_row("SELECT count(*) FROM embeddings", [], |r| r.get(0))
            .unwrap();
        assert_eq!((files, chunks, embeddings), (1, 1, 1));
    }

    #[test]
    fn index_deduplicates_overlapping_roots_and_tracks_meta() {
        let root = temp_dir();
        let sub = root.join("sub");
        fs::create_dir_all(&sub).unwrap();
        fs::write(sub.join("note.md"), "unique indexed note").unwrap();

        let state = root.join("state");
        fs::create_dir_all(&state).unwrap();
        let db = test_db();

        index(
            &state,
            &db,
            &[root.clone(), sub.clone()],
            || false,
            |_| panic!("should defer without embedding on battery"),
        )
        .unwrap();
        let deferred: i64 = db
            .query_row("SELECT count(*) FROM files", [], |r| r.get(0))
            .unwrap();
        assert_eq!(deferred, 0);

        index(
            &state,
            &db,
            &[root.clone(), sub],
            || true,
            |inputs| Ok(vec![vec![0.2_f32; 768]; inputs.len()]),
        )
        .unwrap();

        let count: i64 = db
            .query_row("SELECT count(*) FROM files", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1);
        let prompt: String = db
            .query_row(
                "SELECT value FROM meta WHERE key = 'prompt_version'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(prompt, PROMPT_VERSION);

        let _ = fs::remove_dir_all(&root);
    }
}
