use anyhow::Result;
use serde_json::Value;

/// Filter rows by evaluating a jq expression on each row.
/// Keeps rows where the expression evaluates to a truthy value.
pub fn filter_rows(rows: Vec<Value>, where_expr: &str) -> Result<Vec<Value>> {
    let mut filtered = Vec::new();
    for row in rows {
        let results = crate::engine::jq::apply_jq(&row, where_expr)?;
        let is_truthy = results.iter().any(|v| match v {
            Value::Bool(b) => *b,
            Value::Null => false,
            Value::Number(n) => n.as_f64().is_some_and(|f| f != 0.0),
            Value::String(s) => !s.is_empty(),
            Value::Array(a) => !a.is_empty(),
            Value::Object(_) => true,
        });
        if is_truthy {
            filtered.push(row);
        }
    }
    Ok(filtered)
}

/// Sort rows by a column value. Handles numeric vs string comparison.
pub fn sort_rows(rows: &mut [Value], column: &str, ascending: bool) {
    rows.sort_by(|a, b| {
        let val_a = get_sort_value(a, column);
        let val_b = get_sort_value(b, column);
        let cmp = compare_values(&val_a, &val_b);
        if ascending {
            cmp
        } else {
            cmp.reverse()
        }
    });
}

fn get_sort_value(row: &Value, column: &str) -> Value {
    let mut current = row;
    for segment in column.split('.') {
        match current {
            Value::Object(map) => {
                current = map.get(segment).unwrap_or(&Value::Null);
            }
            _ => return Value::Null,
        }
    }
    current.clone()
}

fn compare_values(a: &Value, b: &Value) -> std::cmp::Ordering {
    // Try numeric comparison first
    if let (Some(na), Some(nb)) = (a.as_f64(), b.as_f64()) {
        return na.partial_cmp(&nb).unwrap_or(std::cmp::Ordering::Equal);
    }

    // Fall back to string comparison
    let sa = value_to_sort_string(a);
    let sb = value_to_sort_string(b);
    sa.cmp(&sb)
}

fn value_to_sort_string(v: &Value) -> String {
    match v {
        Value::Null => String::new(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => n.to_string(),
        Value::String(s) => s.clone(),
        other => serde_json::to_string(other).unwrap_or_default(),
    }
}

/// Truncate rows to a maximum count.
pub fn limit_rows(rows: Vec<Value>, limit: usize) -> Vec<Value> {
    rows.into_iter().take(limit).collect()
}
