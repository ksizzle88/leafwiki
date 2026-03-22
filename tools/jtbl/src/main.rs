mod cli;
mod engine;
mod output;
mod tui;

use anyhow::Result;
use clap::Parser;
use cli::Cli;

fn main() -> Result<()> {
    let cli = Cli::parse();

    // Load JSON input
    let input = engine::loader::load_json(cli.input_file.as_deref())?;

    // Apply jq expression
    let results = engine::jq::apply_jq(&input, &cli.jq_expr)?;

    // Normalize to array of objects
    let mut rows = engine::loader::normalize_to_rows(results);

    // Apply --where filter
    if let Some(ref where_expr) = cli.where_expr {
        rows = engine::filter::filter_rows(rows, where_expr)?;
    }

    // Infer columns
    let columns = engine::columns::infer_columns(&rows);

    // Apply --sort
    if let Some(ref sort_col) = cli.sort {
        engine::filter::sort_rows(&mut rows, sort_col, !cli.sort_desc);
    }

    // Apply --limit
    if let Some(limit) = cli.limit {
        rows = engine::filter::limit_rows(rows, limit);
    }

    if cli.interactive {
        tui::run(rows, columns, &cli.jq_expr)?;
    } else {
        output::render(&rows, &columns, &cli.fmt, cli.out.as_deref())?;
    }

    Ok(())
}
