use crate::tui::app::App;
use ratatui::{
    prelude::*,
    widgets::Paragraph,
};

pub fn render_search_bar(f: &mut Frame, app: &App, area: Rect) {
    let search_text = format!(
        "/{}_  ({}/{} matches)",
        app.search_query,
        app.visible_row_count(),
        app.rows.len()
    );
    let search_bar = Paragraph::new(search_text)
        .style(Style::default().fg(Color::Yellow).bg(Color::DarkGray));
    f.render_widget(search_bar, area);
}
