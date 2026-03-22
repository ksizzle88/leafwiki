use anyhow::{Context, Result};
use serde_json::Value;
use std::io::Read;
use std::path::Path;

/// Load JSON from a file path or stdin.
pub fn load_json(path: Option<&Path>) -> Result<Value> {
    let json_str = match path {
        Some(p) => {
            std::fs::read_to_string(p).with_context(|| format!("Failed to read file: {}", p.display()))?
        }
        None => {
            let mut buf = String::new();
            std::io::stdin()
                .read_to_string(&mut buf)
                .context("Failed to read from stdin")?;
            buf
        }
    };

    let trimmed = json_str.trim();

    // Try parsing as a single JSON value first
    if let Ok(value) = serde_json::from_str(trimmed) {
        return Ok(value);
    }

    // Try JSONL (line-delimited JSON)
    let mut items = Vec::new();
    for line in trimmed.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let val: Value =
            serde_json::from_str(line).with_context(|| format!("Failed to parse JSON line: {}", line))?;
        items.push(val);
    }

    if items.is_empty() {
        anyhow::bail!("No valid JSON found in input");
    }

    Ok(Value::Array(items))
}

/// Normalize jq output to a Vec of row Values.
/// If the result is a single array, unwrap it.
/// If it's a single object, wrap it in a vec.
/// If it's multiple values, collect them.
pub fn normalize_to_rows(results: Vec<Value>) -> Vec<Value> {
    if results.len() == 1 {
        match results.into_iter().next().unwrap() {
            Value::Array(arr) => arr,
            other => vec![other],
        }
    } else {
        results
    }
}
