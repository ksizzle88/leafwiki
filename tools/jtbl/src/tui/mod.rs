mod app;
mod inspector;
mod keymap;
mod search;
mod statusbar;
mod table_view;
mod tree;

use crate::engine::columns::Column;
use anyhow::Result;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::prelude::*;
use ratatui::widgets::{Block, Borders, Clear, Paragraph, Wrap};
use serde_json::Value;
use std::io;

use app::{App, AppMode};

/// Run the interactive TUI.
pub fn run(rows: Vec<Value>, columns: Vec<Column>, title: &str) -> Result<()> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let original_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |panic_info| {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture);
        original_hook(panic_info);
    }));

    let mut app = App::new(rows, columns, title.to_string());

    loop {
        terminal.draw(|f| render_ui(f, &mut app))?;

        if event::poll(std::time::Duration::from_millis(250))? {
            if let Event::Key(key) = event::read()? {
                if handle_key(&mut app, key) {
                    break;
                }
            }
        }
    }

    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    Ok(())
}

/// Returns true if the app should quit.
fn handle_key(app: &mut App, key: event::KeyEvent) -> bool {
    // Ctrl+C always quits
    if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
        return true;
    }

    // Help overlay captures all keys
    if app.show_help_overlay {
        match key.code {
            KeyCode::Esc | KeyCode::Char('?') | KeyCode::Char('q') => {
                app.show_help_overlay = false;
            }
            _ => {}
        }
        return false;
    }

    match app.mode {
        AppMode::Search => {
            match key.code {
                KeyCode::Esc => app.cancel_search(),
                KeyCode::Enter => app.confirm_search(),
                KeyCode::Backspace => app.search_backspace(),
                KeyCode::Char(c) => app.search_type(c),
                _ => {}
            }
            false
        }
        AppMode::Tree => match key.code {
            KeyCode::Char('q') => true,
            KeyCode::Esc | KeyCode::Tab | KeyCode::Char('t') => {
                app.toggle_tree();
                false
            }
            KeyCode::Char('j') | KeyCode::Down => {
                app.tree_next();
                false
            }
            KeyCode::Char('k') | KeyCode::Up => {
                app.tree_prev();
                false
            }
            KeyCode::Enter | KeyCode::Right | KeyCode::Char('l') => {
                app.tree_toggle_expand();
                false
            }
            KeyCode::Left | KeyCode::Char('h') => {
                app.tree_collapse();
                false
            }
            KeyCode::Char('?') => {
                app.show_help_overlay = true;
                false
            }
            _ => false,
        },
        AppMode::Inspector => match key.code {
            KeyCode::Char('q') => true,
            KeyCode::Esc | KeyCode::Char('i') | KeyCode::Enter => {
                app.toggle_inspector();
                false
            }
            KeyCode::Char('j') | KeyCode::Down => {
                app.next_row();
                app.inspector_scroll = 0;
                false
            }
            KeyCode::Char('k') | KeyCode::Up => {
                app.prev_row();
                app.inspector_scroll = 0;
                false
            }
            KeyCode::Char('g') | KeyCode::Home => {
                app.first_row();
                app.inspector_scroll = 0;
                false
            }
            KeyCode::Char('G') | KeyCode::End => {
                app.last_row();
                app.inspector_scroll = 0;
                false
            }
            KeyCode::PageDown => {
                app.inspector_scroll_down();
                false
            }
            KeyCode::PageUp => {
                app.inspector_scroll_up();
                false
            }
            KeyCode::Char('/') => {
                app.enter_search();
                false
            }
            KeyCode::Char('s') => {
                app.cycle_sort();
                false
            }
            KeyCode::Tab | KeyCode::Char('t') => {
                app.toggle_tree();
                false
            }
            KeyCode::Char('?') => {
                app.show_help_overlay = true;
                false
            }
            _ => false,
        },
        AppMode::Normal => match key.code {
            KeyCode::Char('q') => true,
            KeyCode::Char('j') | KeyCode::Down => {
                app.next_row();
                false
            }
            KeyCode::Char('k') | KeyCode::Up => {
                app.prev_row();
                false
            }
            KeyCode::Char('g') | KeyCode::Home => {
                app.first_row();
                false
            }
            KeyCode::Char('G') | KeyCode::End => {
                app.last_row();
                false
            }
            KeyCode::PageDown => {
                app.page_down();
                false
            }
            KeyCode::PageUp => {
                app.page_up();
                false
            }
            KeyCode::Char('/') => {
                app.enter_search();
                false
            }
            KeyCode::Char('i') | KeyCode::Enter => {
                app.toggle_inspector();
                false
            }
            KeyCode::Char('s') => {
                app.cycle_sort();
                false
            }
            KeyCode::Char('h') | KeyCode::Left => {
                app.move_sort_left();
                false
            }
            KeyCode::Char('l') | KeyCode::Right => {
                app.move_sort_right();
                false
            }
            KeyCode::Tab | KeyCode::Char('t') => {
                app.toggle_tree();
                false
            }
            KeyCode::Char('?') => {
                app.show_help_overlay = true;
                false
            }
            KeyCode::Esc => false,
            _ => false,
        },
    }
}

fn render_ui(f: &mut Frame, app: &mut App) {
    let area = f.area();

    match app.mode {
        AppMode::Tree => {
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Min(1),
                    Constraint::Length(1),
                    Constraint::Length(if app.show_help { 1 } else { 0 }),
                ])
                .split(area);

            tree::render_tree(f, app, chunks[0]);
            statusbar::render_statusbar(f, app, chunks[1]);
            if app.show_help {
                keymap::render_help_bar(f, chunks[2]);
            }
        }
        AppMode::Inspector => {
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Min(1),
                    Constraint::Length(1),
                    Constraint::Length(if app.show_help { 1 } else { 0 }),
                ])
                .split(area);

            let hsplit = Layout::default()
                .direction(Direction::Horizontal)
                .constraints([Constraint::Percentage(60), Constraint::Percentage(40)])
                .split(chunks[0]);

            table_view::render_table(f, app, hsplit[0]);
            inspector::render_inspector(f, app, hsplit[1]);
            statusbar::render_statusbar(f, app, chunks[1]);
            if app.show_help {
                keymap::render_help_bar(f, chunks[2]);
            }
        }
        AppMode::Search => {
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Min(1),
                    Constraint::Length(1),
                    Constraint::Length(1),
                ])
                .split(area);

            table_view::render_table(f, app, chunks[0]);
            search::render_search_bar(f, app, chunks[1]);
            statusbar::render_statusbar(f, app, chunks[2]);
        }
        AppMode::Normal => {
            let help_height = if app.show_help { 1 } else { 0 };
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Min(1),
                    Constraint::Length(1),
                    Constraint::Length(help_height),
                ])
                .split(area);

            table_view::render_table(f, app, chunks[0]);
            statusbar::render_statusbar(f, app, chunks[1]);
            if app.show_help {
                keymap::render_help_bar(f, chunks[2]);
            }
        }
    }

    // Help overlay on top of everything
    if app.show_help_overlay {
        render_help_overlay(f, area);
    }
}

fn render_help_overlay(f: &mut Frame, area: Rect) {
    let entries = keymap::full_help();
    let text: String = entries
        .iter()
        .map(|(k, desc)| format!("  {:<16} {}", k, desc))
        .collect::<Vec<_>>()
        .join("\n");

    let width = 44.min(area.width.saturating_sub(4));
    let height = (entries.len() as u16 + 3).min(area.height.saturating_sub(2));
    let x = area.x + (area.width.saturating_sub(width)) / 2;
    let y = area.y + (area.height.saturating_sub(height)) / 2;
    let popup_area = Rect::new(x, y, width, height);

    f.render_widget(Clear, popup_area);
    let paragraph = Paragraph::new(text)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(" Key Bindings ")
                .style(Style::default().bg(Color::Black)),
        )
        .wrap(Wrap { trim: false })
        .style(Style::default().fg(Color::White).bg(Color::Black));
    f.render_widget(paragraph, popup_area);
}
