mod csv_out;
mod json_out;
mod markdown;
mod table;

use crate::cli::OutputFormat;
use crate::engine::columns::Column;
use anyhow::Result;
use serde_json::Value;
use std::path::Path;

/// Render rows in the specified format, writing to a file or stdout.
pub fn render(
    rows: &[Value],
    columns: &[Column],
    format: &OutputFormat,
    out: Option<&Path>,
) -> Result<()> {
    let output = match format {
        OutputFormat::Table => table::render_table(rows, columns),
        OutputFormat::Markdown => markdown::render_markdown(rows, columns),
        OutputFormat::Csv => csv_out::render_csv(rows, columns),
        OutputFormat::Json => json_out::render_json(rows),
    };

    match out {
        Some(path) => std::fs::write(path, &output)?,
        None => print!("{}", output),
    }

    Ok(())
}
