use serde_json::Value;
use std::collections::BTreeSet;

/// A column definition for table output.
#[derive(Clone, Debug)]
pub struct Column {
    /// Display name of the column
    pub name: String,
    /// JSON key path
    pub path: String,
}

/// Infer columns from the first N rows by collecting all unique top-level keys.
pub fn infer_columns(rows: &[Value]) -> Vec<Column> {
    let sample_size = rows.len().min(50);
    let mut keys = BTreeSet::new();

    for row in rows.iter().take(sample_size) {
        if let Value::Object(map) = row {
            for key in map.keys() {
                keys.insert(key.clone());
            }
        }
    }

    // Sort alphabetically but put "id" and "name" first
    let mut columns: Vec<Column> = keys
        .into_iter()
        .map(|key| Column {
            name: key.clone(),
            path: key,
        })
        .collect();

    columns.sort_by(|a, b| {
        let priority_a = key_priority(&a.name);
        let priority_b = key_priority(&b.name);
        priority_a.cmp(&priority_b).then(a.name.cmp(&b.name))
    });

    columns
}

fn key_priority(name: &str) -> u8 {
    match name {
        "id" => 0,
        "name" => 1,
        _ => 2,
    }
}

/// Extract a cell value from a row using a dot-separated path.
pub fn extract_cell(row: &Value, column: &Column) -> String {
    let value = navigate_path(row, &column.path);
    format_value(value)
}

fn navigate_path<'a>(value: &'a Value, path: &str) -> &'a Value {
    let mut current = value;
    for segment in path.split('.') {
        match current {
            Value::Object(map) => {
                current = map.get(segment).unwrap_or(&Value::Null);
            }
            _ => return &Value::Null,
        }
    }
    current
}

fn format_value(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => n.to_string(),
        Value::String(s) => s.clone(),
        Value::Array(_) | Value::Object(_) => {
            serde_json::to_string(value).unwrap_or_default()
        }
    }
}
