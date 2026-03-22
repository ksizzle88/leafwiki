use clap::Parser;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "jtbl", version, about = "JSON exploration and table tool")]
pub struct Cli {
    /// jq expression for row selection (e.g., '.items')
    pub jq_expr: String,

    /// Input JSON file (reads stdin if omitted)
    pub input_file: Option<PathBuf>,

    /// Launch interactive TUI mode
    #[arg(short = 'i', long)]
    pub interactive: bool,

    /// Output format: table, markdown, csv, json
    #[arg(long, default_value = "table", value_enum)]
    pub fmt: OutputFormat,

    /// Limit number of output rows
    #[arg(long)]
    pub limit: Option<usize>,

    /// Filter rows with jq expression (e.g., '.id > 3')
    #[arg(long = "where", name = "where")]
    pub where_expr: Option<String>,

    /// Sort by column name
    #[arg(long)]
    pub sort: Option<String>,

    /// Sort in descending order (used with --sort)
    #[arg(long)]
    pub sort_desc: bool,

    /// Output file (stdout if omitted)
    #[arg(long)]
    pub out: Option<PathBuf>,
}

#[derive(clap::ValueEnum, Clone, Debug, Default)]
pub enum OutputFormat {
    #[default]
    Table,
    Markdown,
    Csv,
    Json,
}
