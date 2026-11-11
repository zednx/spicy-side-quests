// Spicy Side Quests desktop app: a small window around the shared TypeScript sync engine.
// The Rust side only offers plain file access (read, write, stat, list) and the platform's
// folders; all sync logic runs in the web view, the same code the scripts and plugin use.
// No network access: the app makes no connections at all.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::Serialize;
use std::collections::hash_map::RandomState;
use std::fs;
use std::hash::{BuildHasher, Hasher};
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FileInfo {
    mtime_ms: f64,
    size: u64,
    is_dir: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct EnvInfo {
    /// "windows", "linux" or "macos"
    platform: String,
    home: String,
    /// Where settings live: %APPDATA% on Windows, $XDG_CONFIG_HOME or ~/.config elsewhere
    /// (the same place the companion scripts use, so they share settings).
    config_root: String,
}

/// File contents, or None if the file doesn't exist.
#[tauri::command]
fn read_text(path: String) -> Result<Option<String>, String> {
    match fs::read(&path) {
        Ok(bytes) => Ok(Some(String::from_utf8_lossy(&bytes).into_owned())),
        Err(e) if e.kind() == ErrorKind::NotFound => Ok(None),
        Err(e) => Err(format!("{path}: {e}")),
    }
}

/// Writes through a temp file with a random, exclusive name, then swaps it in.
#[tauri::command]
fn write_text(path: String, text: String) -> Result<(), String> {
    let target = PathBuf::from(&path);
    if let Some(dir) = target.parent() {
        if !dir.as_os_str().is_empty() {
            fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        }
    }
    let mut h = RandomState::new().build_hasher();
    h.write_u64(std::process::id() as u64);
    let tmp = PathBuf::from(format!("{path}.{:012x}.tmp", h.finish() & 0xffff_ffff_ffff));
    let written = fs::OpenOptions::new()
        .write(true)
        .create_new(true) // never follows an existing file or link
        .open(&tmp)
        .and_then(|mut f| f.write_all(text.as_bytes()).and_then(|_| f.sync_all()));
    if let Err(e) = written {
        let _ = fs::remove_file(&tmp);
        return Err(format!("{path}: {e}"));
    }
    if fs::rename(&tmp, &target).is_err() {
        // e.g. the file is open in another program on Windows: write in place instead
        let _ = fs::remove_file(&tmp);
        fs::write(&target, text.as_bytes()).map_err(|e| format!("{path}: {e}"))?;
    }
    Ok(())
}

#[tauri::command]
fn file_info(path: String) -> Option<FileInfo> {
    let meta = fs::metadata(Path::new(&path)).ok()?;
    let mtime_ms = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as f64)
        .unwrap_or(0.0);
    Some(FileInfo { mtime_ms, size: meta.len(), is_dir: meta.is_dir() })
}

/// Entry names in a folder; empty if it doesn't exist.
#[tauri::command]
fn list_dir(path: String) -> Vec<String> {
    fs::read_dir(&path)
        .map(|rd| rd.filter_map(|e| e.ok()).map(|e| e.file_name().to_string_lossy().into_owned()).collect())
        .unwrap_or_default()
}

#[tauri::command]
fn env_info() -> EnvInfo {
    let home = dirs::home_dir().unwrap_or_default();
    let config_root = if cfg!(windows) {
        std::env::var_os("APPDATA").map(PathBuf::from).or_else(dirs::config_dir).unwrap_or_else(|| home.clone())
    } else {
        std::env::var_os("XDG_CONFIG_HOME")
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".config"))
    };
    EnvInfo {
        platform: std::env::consts::OS.to_string(),
        home: home.to_string_lossy().into_owned(),
        config_root: config_root.to_string_lossy().into_owned(),
    }
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![read_text, write_text, file_info, list_dir, env_info])
        .run(tauri::generate_context!())
        .expect("error while running Spicy Side Quests");
}
