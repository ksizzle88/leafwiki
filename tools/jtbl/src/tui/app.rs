use crate::engine::columns::{extract_cell, Column};
use serde_json::Value;
use std::collections::HashSet;

#[derive(Debug, Clone, PartialEq)]
pub enum AppMode {
    Normal,
    Search,
    Inspector,
    Tree,
}

pub struct App {
    pub rows: Vec<Value>,
    pub filtered_rows: Vec<usize>,
    pub columns: Vec<Column>,
    pub title: String,
    pub selected_row: usize,
    pub scroll_offset: usize,
    pub mode: AppMode,
    pub search_query: String,
    pub sort_column: Option<usize>,
    pub sort_ascending: bool,
    pub show_help: bool,
    pub show_help_overlay: bool,
    pub inspector_scroll: usize,
    pub page_size: usize,
    // Tree state
    pub tree_selected: usize,
    pub tree_expanded: HashSet<String>,
    pub tree_scroll: usize,
}

impl App {
    pub fn new(rows: Vec<Value>, columns: Vec<Column>, title: String) -> Self {
        let filtered_rows: Vec<usize> = (0..rows.len()).collect();
        Self {
            rows,
            filtered_rows,
            columns,
            title,
            selected_row: 0,
            scroll_offset: 0,
            mode: AppMode::Normal,
            search_query: String::new(),
            sort_column: None,
            sort_ascending: true,
            show_help: true,
            show_help_overlay: false,
            inspector_scroll: 0,
            page_size: 20,
            tree_selected: 0,
            tree_expanded: HashSet::new(),
            tree_scroll: 0,
        }
    }

    pub fn visible_row_count(&self) -> usize {
        self.filtered_rows.len()
    }

    pub fn selected_original_index(&self) -> Option<usize> {
        self.filtered_rows.get(self.selected_row).copied()
    }

    pub fn selected_row_value(&self) -> Option<&Value> {
        self.selected_original_index()
            .and_then(|i| self.rows.get(i))
    }

    pub fn next_row(&mut self) {
        if self.selected_row + 1 < self.visible_row_count() {
            self.selected_row += 1;
            self.adjust_scroll();
        }
    }

    pub fn prev_row(&mut self) {
        if self.selected_row > 0 {
            self.selected_row -= 1;
            self.adjust_scroll();
        }
    }

    pub fn first_row(&mut self) {
        self.selected_row = 0;
        self.scroll_offset = 0;
    }

    pub fn last_row(&mut self) {
        let count = self.visible_row_count();
        if count > 0 {
            self.selected_row = count - 1;
            self.adjust_scroll();
        }
    }

    pub fn page_down(&mut self) {
        let count = self.visible_row_count();
        if count == 0 {
            return;
        }
        self.selected_row = (self.selected_row + self.page_size).min(count - 1);
        self.adjust_scroll();
    }

    pub fn page_up(&mut self) {
        self.selected_row = self.selected_row.saturating_sub(self.page_size);
        self.adjust_scroll();
    }

    fn adjust_scroll(&mut self) {
        if self.selected_row < self.scroll_offset {
            self.scroll_offset = self.selected_row;
        }
        if self.selected_row >= self.scroll_offset + self.page_size {
            self.scroll_offset = self.selected_row - self.page_size + 1;
        }
    }

    pub fn enter_search(&mut self) {
        self.mode = AppMode::Search;
        self.search_query.clear();
    }

    pub fn search_type(&mut self, c: char) {
        self.search_query.push(c);
        self.apply_search_filter();
    }

    pub fn search_backspace(&mut self) {
        self.search_query.pop();
        self.apply_search_filter();
    }

    pub fn confirm_search(&mut self) {
        self.mode = AppMode::Normal;
    }

    pub fn cancel_search(&mut self) {
        self.search_query.clear();
        self.filtered_rows = (0..self.rows.len()).collect();
        self.selected_row = 0;
        self.scroll_offset = 0;
        self.mode = AppMode::Normal;
    }

    fn apply_search_filter(&mut self) {
        if self.search_query.is_empty() {
            self.filtered_rows = (0..self.rows.len()).collect();
        } else {
            let query = self.search_query.to_lowercase();
            self.filtered_rows = (0..self.rows.len())
                .filter(|&i| {
                    self.columns.iter().any(|col| {
                        extract_cell(&self.rows[i], col)
                            .to_lowercase()
                            .contains(&query)
                    })
                })
                .collect();
        }
        self.selected_row = 0;
        self.scroll_offset = 0;
        // Re-apply sort if active
        self.apply_sort();
    }

    pub fn toggle_inspector(&mut self) {
        self.mode = if self.mode == AppMode::Inspector {
            AppMode::Normal
        } else {
            self.inspector_scroll = 0;
            AppMode::Inspector
        };
    }

    pub fn toggle_tree(&mut self) {
        self.mode = if self.mode == AppMode::Tree {
            AppMode::Normal
        } else {
            AppMode::Tree
        };
    }


    pub fn cycle_sort(&mut self) {
        match self.sort_column {
            None => {
                if !self.columns.is_empty() {
                    self.sort_column = Some(0);
                    self.sort_ascending = true;
                    self.apply_sort();
                }
            }
            Some(_) => {
                if self.sort_ascending {
                    self.sort_ascending = false;
                    self.apply_sort();
                } else {
                    self.sort_column = None;
                    self.sort_ascending = true;
                    // Restore original order, re-apply search filter
                    self.filtered_rows = (0..self.rows.len()).collect();
                    if !self.search_query.is_empty() {
                        let query = self.search_query.to_lowercase();
                        self.filtered_rows.retain(|&i| {
                            self.columns.iter().any(|col| {
                                extract_cell(&self.rows[i], col)
                                    .to_lowercase()
                                    .contains(&query)
                            })
                        });
                    }
                }
            }
        }
    }

    pub fn move_sort_left(&mut self) {
        if let Some(col) = self.sort_column {
            if col > 0 {
                self.sort_column = Some(col - 1);
                self.sort_ascending = true;
                self.apply_sort();
            }
        }
    }

    pub fn move_sort_right(&mut self) {
        if let Some(col) = self.sort_column {
            if col + 1 < self.columns.len() {
                self.sort_column = Some(col + 1);
                self.sort_ascending = true;
                self.apply_sort();
            }
        }
    }

    fn apply_sort(&mut self) {
        if let Some(col_idx) = self.sort_column {
            if let Some(col) = self.columns.get(col_idx) {
                let col = col.clone();
                let ascending = self.sort_ascending;
                let rows = &self.rows;
                self.filtered_rows.sort_by(|&a, &b| {
                    let va = extract_cell(&rows[a], &col);
                    let vb = extract_cell(&rows[b], &col);
                    let cmp = compare_cell_values(&va, &vb);
                    if ascending {
                        cmp
                    } else {
                        cmp.reverse()
                    }
                });
            }
        }
    }

    pub fn inspector_scroll_down(&mut self) {
        self.inspector_scroll += 1;
    }

    pub fn inspector_scroll_up(&mut self) {
        self.inspector_scroll = self.inspector_scroll.saturating_sub(1);
    }

    pub fn tree_next(&mut self) {
        self.tree_selected += 1;
    }

    pub fn tree_prev(&mut self) {
        self.tree_selected = self.tree_selected.saturating_sub(1);
    }

    pub fn tree_toggle_expand(&mut self) {
        let key = format!("node_{}", self.tree_selected);
        if self.tree_expanded.contains(&key) {
            self.tree_expanded.remove(&key);
        } else {
            self.tree_expanded.insert(key);
        }
    }

    pub fn tree_collapse(&mut self) {
        let key = format!("node_{}", self.tree_selected);
        self.tree_expanded.remove(&key);
    }
}

fn compare_cell_values(a: &str, b: &str) -> std::cmp::Ordering {
    if let (Ok(na), Ok(nb)) = (a.parse::<f64>(), b.parse::<f64>()) {
        return na.partial_cmp(&nb).unwrap_or(std::cmp::Ordering::Equal);
    }
    a.cmp(b)
}
