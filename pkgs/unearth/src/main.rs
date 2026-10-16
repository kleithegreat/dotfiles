use std::collections::{HashMap, HashSet};
use std::env;
use std::error::Error;
use std::ffi::{c_char, c_int};
use std::fs;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::{Duration, UNIX_EPOCH};

use clap::{Parser, Subcommand};
use rusqlite::{Connection, ffi, params};
use serde::{Deserialize, Serialize};
use serde_json::json;

type Result<T> = std::result::Result<T, Box<dyn Error>>;

const PORT: &str = "8737";
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
    CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING fts5(text, file UNINDEXED, page UNINDEXED);
    CREATE VIRTUAL TABLE IF NOT EXISTS embeddings USING vec0(embedding float[768]);
";

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
        Cmd::Index { roots } => index(&open()?, &roots),
        Cmd::Search {
            query,
            keyword_only,
            limit,
        } => {
            let hits = search(&open()?, &query, keyword_only, limit)?;
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

fn open() -> Result<Connection> {
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
    let state = match env::var_os("XDG_STATE_HOME") {
        Some(dir) => PathBuf::from(dir),
        None => PathBuf::from(env::var_os("HOME").ok_or("HOME is unset")?).join(".local/state"),
    }
    .join("unearth");
    fs::create_dir_all(&state)?;
    let db = Connection::open(state.join("index.db"))?;
    db.pragma_update(None, "journal_mode", "WAL")?;
    db.busy_timeout(Duration::from_secs(5))?;
    db.execute_batch(SCHEMA)?;
    Ok(db)
}

fn index(db: &Connection, roots: &[PathBuf]) -> Result<()> {
    let mut documents = Vec::new();
    for root in roots {
        walk(root, &mut documents);
    }
    let present: HashSet<&str> = documents.iter().map(String::as_str).collect();

    let known: HashMap<String, (i64, i64, i64)> = db
        .prepare("SELECT path, id, mtime, size FROM files")?
        .query_map([], |row| {
            Ok((row.get(0)?, (row.get(1)?, row.get(2)?, row.get(3)?)))
        })?
        .collect::<rusqlite::Result<_>>()?;
    for (path, &(file, ..)) in &known {
        if !present.contains(path.as_str()) {
            forget(db, file)?;
        }
    }

    for path in &documents {
        let Ok(metadata) = fs::metadata(path) else {
            continue;
        };
        let mtime = metadata.modified()?.duration_since(UNIX_EPOCH)?.as_nanos() as i64;
        let size = metadata.len() as i64;
        let previous = known.get(path);
        if previous.is_some_and(|&(_, m, s)| (m, s) == (mtime, size)) {
            continue;
        }
        if !on_ac_power() {
            eprintln!("on battery, deferring the rest");
            return Ok(());
        }

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
        let vectors = embed(&inputs)?;

        let tx = db.unchecked_transaction()?;
        if let Some(&(file, ..)) = previous {
            forget(&tx, file)?;
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
    }
    Ok(())
}

fn forget(db: &Connection, file: i64) -> Result<()> {
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

fn walk(dir: &Path, documents: &mut Vec<String>) {
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
            walk(&path, documents);
        } else if file_type.is_file()
            && kind(&path).is_some()
            && let Some(path) = path.to_str()
        {
            documents.push(path.to_owned());
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

fn embed(inputs: &[String]) -> Result<Vec<Vec<f32>>> {
    let url = format!("http://127.0.0.1:{PORT}/v1/embeddings");
    let mut vectors = Vec::with_capacity(inputs.len());
    for batch in inputs.chunks(EMBED_BATCH) {
        let body = json!({ "input": batch });
        let mut response = loop {
            match ureq::post(&url).send_json(&body) {
                // The server answers 503 while it loads the model after starting.
                Err(ureq::Error::StatusCode(503)) => thread::sleep(Duration::from_millis(250)),
                response => break response?,
            }
        };
        let mut embeddings: Embeddings = response.body_mut().read_json()?;
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

fn search(db: &Connection, query: &str, keyword_only: bool, limit: usize) -> Result<Vec<Hit>> {
    let mut candidates: HashMap<i64, Candidate> = HashMap::new();
    let mut rank = |chunk: i64, position: usize, file: i64, page: Option<i64>, snippet: String| {
        candidates
            .entry(chunk)
            .or_insert(Candidate {
                file,
                page,
                snippet,
                score: 0.0,
            })
            .score += 1.0 / (RRF_K + position as f64);
    };

    let terms: Vec<String> = query
        .split_whitespace()
        .map(|word| format!("\"{}\"", word.replace('"', "\"\"")))
        .collect();
    if terms.is_empty() {
        return Ok(Vec::new());
    }
    // The trailing `*` lets the word still being typed match as a prefix.
    let pattern = terms.join(" ") + "*";
    let mut keyword = db.prepare(
        "SELECT rowid, file, page, snippet(chunks, 0, '', '', '…', 24)
         FROM chunks WHERE chunks MATCH ?1 ORDER BY rank LIMIT ?2",
    )?;
    let rows = keyword.query_map(params![pattern, CANDIDATES], |row| {
        Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
    })?;
    for (position, row) in rows.enumerate() {
        let (chunk, file, page, snippet) = row?;
        rank(chunk, position, file, page, snippet);
    }

    if !keyword_only {
        let vector = embed(&[format!("task: search result | query: {query}")])?;
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
            rank(chunk, position, file, page, snippet);
        }
    }

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
