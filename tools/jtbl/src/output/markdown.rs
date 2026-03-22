use crate::engine::columns::{extract_cell, Column};
use serde_json::Value;

pub fn render_markdown(rows: &[Value], columns: &[Column]) -> String {
    if columns.is_empty() {
        return String::new();
    }

    let mut out = String::new();

    // Header row
    out.push('|');
    for col in columns {
        out.push_str(&format!(" {} |", col.name));
    }
    out.push('\n');

    // Separator row
    out.push('|');
    for _ in columns {
        out.push_str(" --- |");
    }
    out.push('\n');

    // Data rows
    for row in rows {
        out.push('|');
        for col in columns {
            let cell = extract_cell(row, col).replace('|', "\\|");
            out.push_str(&format!(" {} |", cell));
        }
        out.push('\n');
    }

    out
}
