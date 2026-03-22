use ratatui::{
    prelude::*,
    widgets::Paragraph,
};

pub fn render_help_bar(f: &mut Frame, area: Rect) {
    let help_text = " q:Quit  j/k:Nav  /:Search  i:Inspect  s:Sort  h/l:Move sort  t:Tree  ?:Help";
    let help = Paragraph::new(help_text)
        .style(Style::default().fg(Color::Black).bg(Color::White));
    f.render_widget(help, area);
}

pub fn full_help() -> Vec<(&'static str, &'static str)> {
    vec![
        ("q, Ctrl+C", "Quit"),
        ("j / Down", "Next row"),
        ("k / Up", "Previous row"),
        ("g / Home", "First row"),
        ("G / End", "Last row"),
        ("PgDn / PgUp", "Page down / up"),
        ("/", "Search / filter rows"),
        ("i / Enter", "Toggle row inspector"),
        ("s", "Cycle sort (asc/desc/none)"),
        ("h/l, Left/Right", "Move sort column"),
        ("t / Tab", "Switch Table / Tree"),
        ("?", "Toggle this help"),
        ("Esc", "Close panel / cancel"),
    ]
}
