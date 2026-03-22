use crate::engine::columns::extract_cell;
use crate::tui::app::App;
use ratatui::{
    prelude::*,
    widgets::{Block, Borders, Cell, Row, Table},
};

pub fn render_table(f: &mut Frame, app: &mut App, area: Rect) {
    // Update page_size based on actual area height (minus borders and header)
    let available_rows = area.height.saturating_sub(3) as usize;
    if available_rows > 0 {
        app.page_size = available_rows;
    }

    // Build header
    let header_cells: Vec<Cell> = app
        .columns
        .iter()
        .enumerate()
        .map(|(i, col)| {
            let mut name = col.name.clone();
            if let Some(sort_col) = app.sort_column {
                if sort_col == i {
                    if app.sort_ascending {
                        name.push_str(" ▲");
                    } else {
                        name.push_str(" ▼");
                    }
                }
            }
            Cell::from(name).style(Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD))
        })
        .collect();

    let header = Row::new(header_cells).height(1).bottom_margin(0);

    // Build visible rows
    let end = (app.scroll_offset + app.page_size).min(app.visible_row_count());
    let visible_range = app.scroll_offset..end;

    let rows: Vec<Row> = visible_range
        .map(|idx| {
            let orig_idx = app.filtered_rows[idx];
            let row_val = &app.rows[orig_idx];
            let cells: Vec<Cell> = app
                .columns
                .iter()
                .map(|col| Cell::from(extract_cell(row_val, col)))
                .collect();

            let style = if idx == app.selected_row {
                Style::default().bg(Color::DarkGray).fg(Color::White)
            } else {
                Style::default()
            };

            Row::new(cells).style(style)
        })
        .collect();

    // Calculate column widths
    let widths: Vec<Constraint> = app
        .columns
        .iter()
        .map(|col| {
            let header_width = col.name.len() as u16 + 3; // extra for sort indicator
            Constraint::Min(header_width.max(8))
        })
        .collect();

    let title = format!(
        " {} ({} rows) ",
        app.title,
        app.visible_row_count()
    );

    let table = Table::new(rows, &widths)
        .header(header)
        .block(Block::default().borders(Borders::ALL).title(title))
        .row_highlight_style(Style::default().bg(Color::DarkGray));

    f.render_widget(table, area);
}
