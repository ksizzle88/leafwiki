use crate::tui::app::App;
use ratatui::{
    prelude::*,
    widgets::{Block, Borders, Paragraph, Wrap},
};

pub fn render_inspector(f: &mut Frame, app: &App, area: Rect) {
    let json_text = match app.selected_row_value() {
        Some(val) => serde_json::to_string_pretty(val).unwrap_or_else(|_| "null".to_string()),
        None => "No row selected".to_string(),
    };

    let lines: Vec<Line> = json_text
        .lines()
        .skip(app.inspector_scroll)
        .map(|line| Line::from(line.to_string()))
        .collect();

    let title = format!(" Inspector (row {}) ", app.selected_row + 1);
    let paragraph = Paragraph::new(lines)
        .block(Block::default().borders(Borders::ALL).title(title))
        .wrap(Wrap { trim: false });

    f.render_widget(paragraph, area);
}
