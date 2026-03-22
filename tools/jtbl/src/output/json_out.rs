use serde_json::Value;

pub fn render_json(rows: &[Value]) -> String {
    let array = Value::Array(rows.to_vec());
    serde_json::to_string_pretty(&array).unwrap_or_else(|_| "[]".to_string()) + "\n"
}
