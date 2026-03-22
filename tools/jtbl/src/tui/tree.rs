use crate::tui::app::App;
use ratatui::{
    prelude::*,
    widgets::{Block, Borders, Paragraph},
};
use serde_json::Value;

struct TreeNode {
    indent: usize,
    key: String,
    value_str: String,
    is_expandable: bool,
    is_expanded: bool,
}

pub fn render_tree(f: &mut Frame, app: &App, area: Rect) {
    let input = if !app.rows.is_empty() {
        Value::Array(app.rows.clone())
    } else {
        Value::Null
    };

    let nodes = flatten_tree(&input, "", 0, &app.tree_expanded);

    // Clamp tree_selected
    let max_idx = if nodes.is_empty() { 0 } else { nodes.len() - 1 };
    let selected = app.tree_selected.min(max_idx);

    let visible_height = area.height.saturating_sub(2) as usize;

    // Adjust scroll
    let scroll = if selected < app.tree_scroll {
        selected
    } else if selected >= app.tree_scroll + visible_height {
        selected - visible_height + 1
    } else {
        app.tree_scroll
    };

    let lines: Vec<Line> = nodes
        .iter()
        .enumerate()
        .skip(scroll)
        .take(visible_height)
        .map(|(idx, node)| {
            let indent = "  ".repeat(node.indent);
            let prefix = if node.is_expandable {
                if node.is_expanded {
                    "▼ "
                } else {
                    "▶ "
                }
            } else {
                "  "
            };

            let text = if node.value_str.is_empty() {
                format!("{}{}{}", indent, prefix, node.key)
            } else {
                format!("{}{}{}: {}", indent, prefix, node.key, node.value_str)
            };

            let style = if idx == selected {
                Style::default().bg(Color::DarkGray).fg(Color::White)
            } else if node.is_expandable {
                Style::default().fg(Color::Cyan)
            } else {
                Style::default()
            };

            Line::from(Span::styled(text, style))
        })
        .collect();

    let title = format!(" Tree Explorer ({} nodes) ", nodes.len());
    let paragraph = Paragraph::new(lines)
        .block(Block::default().borders(Borders::ALL).title(title));
    f.render_widget(paragraph, area);
}

fn flatten_tree(
    value: &Value,
    key: &str,
    indent: usize,
    expanded: &std::collections::HashSet<String>,
) -> Vec<TreeNode> {
    let mut nodes = Vec::new();

    match value {
        Value::Object(map) => {
            let node_path = format!("node_{}", nodes.len());
            let is_expanded = expanded.contains(&node_path);
            nodes.push(TreeNode {
                indent,
                key: if key.is_empty() {
                    "{...}".to_string()
                } else {
                    format!("{} {{{}}}", key, map.len())
                },
                value_str: String::new(),
                is_expandable: true,
                is_expanded,
            });

            if is_expanded {
                for (k, v) in map {
                    let child_nodes = flatten_tree(v, k, indent + 1, expanded);
                    nodes.extend(child_nodes);
                }
            }
        }
        Value::Array(arr) => {
            let node_path = format!("node_{}", nodes.len());
            let is_expanded = expanded.contains(&node_path);
            nodes.push(TreeNode {
                indent,
                key: if key.is_empty() {
                    format!("[{}]", arr.len())
                } else {
                    format!("{} [{}]", key, arr.len())
                },
                value_str: String::new(),
                is_expandable: true,
                is_expanded,
            });

            if is_expanded {
                for (i, v) in arr.iter().enumerate() {
                    let child_key = format!("[{}]", i);
                    let child_nodes = flatten_tree(v, &child_key, indent + 1, expanded);
                    nodes.extend(child_nodes);
                }
            }
        }
        Value::String(s) => {
            nodes.push(TreeNode {
                indent,
                key: key.to_string(),
                value_str: format!("\"{}\"", s),
                is_expandable: false,
                is_expanded: false,
            });
        }
        Value::Number(n) => {
            nodes.push(TreeNode {
                indent,
                key: key.to_string(),
                value_str: n.to_string(),
                is_expandable: false,
                is_expanded: false,
            });
        }
        Value::Bool(b) => {
            nodes.push(TreeNode {
                indent,
                key: key.to_string(),
                value_str: b.to_string(),
                is_expandable: false,
                is_expanded: false,
            });
        }
        Value::Null => {
            nodes.push(TreeNode {
                indent,
                key: key.to_string(),
                value_str: "null".to_string(),
                is_expandable: false,
                is_expanded: false,
            });
        }
    }

    nodes
}
