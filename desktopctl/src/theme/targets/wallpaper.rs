use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    expand_user_path, find_command,
    schema::{ColorScheme, ThemeState},
};
use std::{
    fs, io,
    path::{Path, PathBuf},
    process::Command,
    time::UNIX_EPOCH,
};

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "wallpaper",
    Assembly::Command,
    &["color_scheme", "wallpaper", "filter_wallpaper"],
)
.sync_safe(false);

const CACHE_VERSION: &str = "lutgen-apply-v1";

fn awww_command(path: &str) -> Vec<String> {
    vec![
        "awww".to_owned(),
        "img".to_owned(),
        path.to_owned(),
        "--transition-type".to_owned(),
        "fade".to_owned(),
        "--transition-duration".to_owned(),
        "1".to_owned(),
    ]
}

fn cache_root() -> crate::Result<PathBuf> {
    match std::env::var("XDG_CACHE_HOME") {
        Ok(base) => Ok(PathBuf::from(base).join("apply-theme").join("wallpaper")),
        Err(std::env::VarError::NotPresent) => expand_user_path("~/.cache/apply-theme/wallpaper"),
        Err(error) => Err(io::Error::new(io::ErrorKind::InvalidInput, error).into()),
    }
}

fn cache_key(colors: &ColorScheme, wallpaper: &Path) -> crate::Result<String> {
    let stat = wallpaper.metadata()?;
    let resolved = wallpaper.canonicalize()?;
    let modified_ns = stat
        .modified()?
        .duration_since(UNIX_EPOCH)
        .map_err(io::Error::other)?
        .as_nanos()
        .to_string();

    let mut hasher = Sha256::new();
    hasher.update(CACHE_VERSION.as_bytes());
    hasher.update(resolved.to_string_lossy().as_bytes());
    hasher.update(stat.len().to_string().as_bytes());
    hasher.update(modified_ns.as_bytes());
    for color in &colors.palette {
        hasher.update(color.to_ascii_lowercase().as_bytes());
    }
    Ok(hasher.finish_hex()[..16].to_owned())
}

fn filtered_wallpaper_path(colors: &ColorScheme, state: &ThemeState) -> crate::Result<PathBuf> {
    let wallpaper = PathBuf::from(&state.wallpaper).expanduser()?;
    let stem = sanitize_stem(
        wallpaper
            .file_stem()
            .and_then(|stem| stem.to_str())
            .unwrap_or_default(),
    );
    let scheme = sanitize_component(&state.color_scheme);
    Ok(cache_root()?.join(format!(
        "{stem}-{scheme}-{}.png",
        cache_key(colors, &wallpaper)?
    )))
}

fn sanitize_component(value: &str) -> String {
    value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '-' | '_') {
                character
            } else {
                '-'
            }
        })
        .collect()
}

fn sanitize_stem(value: &str) -> String {
    let sanitized = sanitize_component(value);
    let trimmed = sanitized.trim_matches(['-', '_']);
    if trimmed.is_empty() {
        "wallpaper".to_owned()
    } else {
        trimmed.to_owned()
    }
}

fn run_command(command: &[String]) -> (bool, String) {
    let output = Command::new(&command[0]).args(&command[1..]).output();
    match output {
        Ok(output) if output.status.success() => (true, String::new()),
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
            let message = if !stderr.is_empty() {
                stderr
            } else if !stdout.is_empty() {
                stdout
            } else {
                output.status.to_string()
            };
            (false, message)
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            (false, format!("{:?} not found", command[0]))
        }
        Err(error) => (false, error.to_string()),
    }
}

fn warn(message: &str) {
    eprintln!("  wallpaper warning: {message}");
}

fn apply_wallpaper(path: &Path) {
    let (ok, message) = run_command(&awww_command(&path.display().to_string()));
    if !ok {
        warn(&format!(
            "failed to apply wallpaper {}: {message}",
            path.display()
        ));
    }
}

fn fallback_to_source(source: &Path, reason: &str) {
    warn(&format!("{reason}; using original wallpaper"));
    apply_wallpaper(source);
}

pub fn generate(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    let commands = if state.filter_wallpaper {
        Vec::new()
    } else {
        vec![awww_command(&state.wallpaper)]
    };
    Ok(GeneratedContent::commands(commands))
}

pub fn on_apply(colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    if !state.filter_wallpaper {
        return Ok(());
    }

    let source = PathBuf::from(&state.wallpaper).expanduser()?;
    if !source.is_file() {
        warn(&format!(
            "source wallpaper does not exist: {}",
            source.display()
        ));
        return Ok(());
    }

    match filtered_wallpaper_path(colors, state) {
        Ok(filtered) => {
            if !filtered.is_file() {
                if find_command("lutgen").is_none() {
                    fallback_to_source(
                        &source,
                        "filter_wallpaper is enabled but 'lutgen' is not installed",
                    );
                    return Ok(());
                }

                if let Err(error) =
                    fs::create_dir_all(filtered.parent().expect("filtered wallpaper parent"))
                {
                    fallback_to_source(
                        &source,
                        &format!(
                            "could not create wallpaper filter cache at {}: {error}",
                            filtered
                                .parent()
                                .expect("filtered wallpaper parent")
                                .display()
                        ),
                    );
                    return Ok(());
                }

                let (ok, message) = run_command(&{
                    let mut command = vec![
                        "lutgen".to_owned(),
                        "apply".to_owned(),
                        "--cache".to_owned(),
                        "-o".to_owned(),
                        filtered.display().to_string(),
                        source.display().to_string(),
                        "--".to_owned(),
                    ];
                    command.extend(colors.palette.iter().cloned());
                    command
                });
                if !ok {
                    let _ = fs::remove_file(&filtered);
                    fallback_to_source(
                        &source,
                        &format!("could not generate filtered wallpaper with lutgen: {message}"),
                    );
                    return Ok(());
                }
            }
            apply_wallpaper(&filtered);
        }
        Err(error) => fallback_to_source(
            &source,
            &format!("unexpected error while preparing filtered wallpaper: {error}"),
        ),
    }

    Ok(())
}

trait ExpandUserPath {
    fn expanduser(self) -> crate::Result<PathBuf>;
}

impl ExpandUserPath for PathBuf {
    fn expanduser(self) -> crate::Result<PathBuf> {
        let text = self.to_string_lossy().to_string();
        expand_user_path(&text)
    }
}

struct Sha256 {
    state: [u32; 8],
    length_bits: u64,
    buffer: Vec<u8>,
}

impl Sha256 {
    fn new() -> Self {
        Self {
            state: [
                0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
                0x5be0cd19,
            ],
            length_bits: 0,
            buffer: Vec::new(),
        }
    }

    fn update(&mut self, bytes: &[u8]) {
        self.length_bits = self.length_bits.wrapping_add((bytes.len() as u64) * 8);
        self.buffer.extend_from_slice(bytes);
        while self.buffer.len() >= 64 {
            let mut block = [0u8; 64];
            block.copy_from_slice(&self.buffer[..64]);
            self.process_block(&block);
            self.buffer.drain(..64);
        }
    }

    fn finish_hex(mut self) -> String {
        let bit_length = self.length_bits;
        self.buffer.push(0x80);
        while !(self.buffer.len() + 8).is_multiple_of(64) {
            self.buffer.push(0);
        }
        self.buffer.extend_from_slice(&bit_length.to_be_bytes());

        while !self.buffer.is_empty() {
            let mut block = [0u8; 64];
            block.copy_from_slice(&self.buffer[..64]);
            self.process_block(&block);
            self.buffer.drain(..64);
        }

        let mut output = String::with_capacity(64);
        for word in self.state {
            output.push_str(&format!("{word:08x}"));
        }
        output
    }

    fn process_block(&mut self, block: &[u8; 64]) {
        const K: [u32; 64] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
            0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
            0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
            0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
            0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
            0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
            0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
            0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
            0xc67178f2,
        ];

        let mut words = [0u32; 64];
        for (index, chunk) in block.chunks_exact(4).enumerate().take(16) {
            words[index] = u32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
        }
        for index in 16..64 {
            let s0 = words[index - 15].rotate_right(7)
                ^ words[index - 15].rotate_right(18)
                ^ (words[index - 15] >> 3);
            let s1 = words[index - 2].rotate_right(17)
                ^ words[index - 2].rotate_right(19)
                ^ (words[index - 2] >> 10);
            words[index] = words[index - 16]
                .wrapping_add(s0)
                .wrapping_add(words[index - 7])
                .wrapping_add(s1);
        }

        let mut a = self.state[0];
        let mut b = self.state[1];
        let mut c = self.state[2];
        let mut d = self.state[3];
        let mut e = self.state[4];
        let mut f = self.state[5];
        let mut g = self.state[6];
        let mut h = self.state[7];

        for index in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = h
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[index])
                .wrapping_add(words[index]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            h = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }

        self.state[0] = self.state[0].wrapping_add(a);
        self.state[1] = self.state[1].wrapping_add(b);
        self.state[2] = self.state[2].wrapping_add(c);
        self.state[3] = self.state[3].wrapping_add(d);
        self.state[4] = self.state[4].wrapping_add(e);
        self.state[5] = self.state[5].wrapping_add(f);
        self.state[6] = self.state[6].wrapping_add(g);
        self.state[7] = self.state[7].wrapping_add(h);
    }
}
