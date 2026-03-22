use anyhow::{anyhow, Result};
use jaq_interpret::{Ctx, FilterT, ParseCtx, RcIter, Val};
use serde_json::Value;

/// Apply a jq expression to a JSON value using the embedded jaq engine.
/// This avoids needing jq installed as a system dependency.
pub fn apply_jq(input: &Value, expr: &str) -> Result<Vec<Value>> {
    let (main_filter, errs) = jaq_parse::parse(expr, jaq_parse::main());
    if !errs.is_empty() {
        return Err(anyhow!("Failed to parse jq expression '{}'", expr));
    }
    let main_filter =
        main_filter.ok_or_else(|| anyhow!("jq expression '{}' produced no filter", expr))?;

    let mut defs = ParseCtx::new(Vec::new());
    defs.insert_natives(jaq_core::core());
    defs.insert_defs(jaq_std::std());

    let filter = defs.compile(main_filter);
    if !defs.errs.is_empty() {
        return Err(anyhow!(
            "Failed to compile jq expression '{}' ({} errors)",
            expr,
            defs.errs.len()
        ));
    }

    let inputs = RcIter::new(core::iter::empty());
    let jaq_val = Val::from(input.clone());

    let mut results = Vec::new();
    for output in filter.run((Ctx::new([], &inputs), jaq_val)) {
        match output {
            Ok(val) => {
                let json_val: Value = serde_json::from_str(&val.to_string())
                    .unwrap_or_else(|_| Value::String(val.to_string()));
                results.push(json_val);
            }
            Err(e) => {
                return Err(anyhow!("jq evaluation error: {}", e));
            }
        }
    }

    Ok(results)
}
