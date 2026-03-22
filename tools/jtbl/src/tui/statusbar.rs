use crate::tui::app::{App, AppMode};
use ratatui::{
    prelude::*,
    widgets::Paragraph,
};

pub fn render_statusbar(f: &mut Frame, app: &App, area: Rect) {
    let mode_str = match app.mode {
        AppMode::Normal => "NORMAL",
        AppMode::Search => "SEARCH",
        AppMode::Inspector => "INSPECT",
        AppMode::Tree => "TREE",
    };

    let sort_info = match app.sort_column {
        Some(idx) => {
            let dir = if app.sort_ascending { "asc" } else { "desc" };
            let name = app.columns.get(idx).map(|c| c.name.as_str()).unwrap_or("?");
            format!(" | sort: {} ({})", name, dir)
        }
        None => String::new(),
    };

    let row_info = if app.visible_row_count() > 0 {
        format!(
            "row {}/{}",
            app.selected_row + 1,
            app.visible_row_count()
        )
    } else {
        "no rows".to_string()
    };

    let status = format!(
        " [{}] {} | {}{}",
        mode_str, app.title, row_info, sort_info
    );

    let bar = Paragraph::new(status)
        .style(Style::default().fg(Color::White).bg(Color::Blue));
    f.render_widget(bar, area);
}
