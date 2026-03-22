use crate::engine::columns::{extract_cell, Column};
use serde_json::Value;

pub fn render_csv(rows: &[Value], columns: &[Column]) -> String {
    let mut out = String::new();

    // Header row
    let headers: Vec<&str> = columns.iter().map(|c| c.name.as_str()).collect();
    out.push_str(&csv_row(&headers));

    // Data rows
    for row in rows {
        let cells: Vec<String> = columns.iter().map(|col| extract_cell(row, col)).collect();
        let refs: Vec<&str> = cells.iter().map(|s| s.as_str()).collect();
        out.push_str(&csv_row(&refs));
    }

    out
}

fn csv_row(fields: &[&str]) -> String {
    let escaped: Vec<String> = fields.iter().map(|f| csv_escape(f)).collect();
    format!("{}\n", escaped.join(","))
}

fn csv_escape(field: &str) -> String {
    if field.contains(',') || field.contains('"') || field.contains('\n') {
        format!("\"{}\"", field.replace('"', "\"\""))
    } else {
        field.to_string()
    }
}
