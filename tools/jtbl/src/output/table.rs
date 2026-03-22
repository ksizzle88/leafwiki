use crate::engine::columns::{extract_cell, Column};
use comfy_table::{ContentArrangement, Table};
use serde_json::Value;

pub fn render_table(rows: &[Value], columns: &[Column]) -> String {
    let mut table = Table::new();
    table.set_content_arrangement(ContentArrangement::Dynamic);

    let headers: Vec<&str> = columns.iter().map(|c| c.name.as_str()).collect();
    table.set_header(headers);

    for row in rows {
        let cells: Vec<String> = columns.iter().map(|col| extract_cell(row, col)).collect();
        table.add_row(cells);
    }

    format!("{}\n", table)
}
