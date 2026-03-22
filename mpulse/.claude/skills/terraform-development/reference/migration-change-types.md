# Terraform Migration Change Type Reference

How to evaluate and resolve each type of plan diff encountered during a
state migration (importing existing infrastructure into new module structure).

## Guiding Principle

> **Option B -- model what exists.** Always add inputs to match existing infra
> rather than ignoring changes or accepting drift. Never change live
> infrastructure unless there is no alternative.

---

## Update Types

### 1. Metadata Convergence

**What it looks like:**
```
comment:  "" -> "DATA DEVELOPER access (ALL scope)"
tags_all: {} -> { "Env": "stage", "Owner": "Analytics", ... }
```

**Why it happens:** The new module sets metadata (comments, tags) that the
legacy config didn't manage. The resource exists but the metadata field was
empty or absent.

**Makes API call?** YES -- `ALTER ROLE SET COMMENT`, `TagResource`, etc.
**Changes behavior?** NO -- metadata only.

| Decision | When to use | How to resolve |
|----------|-------------|----------------|
| ACCEPT | Metadata matches QA and is purely descriptive | No code change. Apply as-is. |
| FIX | Environment needs different metadata than module default | Add variable to module, pass env-specific value. |

---

### 2. Privilege Materialization

**What it looks like:**
```
privileges: [] -> ["CREATE SCHEMA"]
privileges: [] -> ["USAGE"]
```

**Why it happens:** The Snowflake provider imports grants with an empty
privilege array in state. On the next plan, it reads the actual grant from
Snowflake and populates the array. This is a one-time state sync artifact.

**Makes API call?** YES -- issues a `GRANT` statement, but Snowflake `GRANT`
is idempotent. Re-granting an existing privilege is a no-op.
**Changes behavior?** NO.

| Decision | When to use | How to resolve |
|----------|-------------|----------------|
| ACCEPT | Always (this is expected post-import behavior) | No code change. Apply once, becomes no-op on next plan. |

---

### 3. Computed Attribute Refresh

**What it looks like:**
```
show_output:     (known after apply)
describe_output: (known after apply)
parameters:      (known after apply)
```

**Why it happens:** Snowflake provider resources have computed attributes
that contain the result of `SHOW` / `DESCRIBE` commands. These refresh every
plan. The diff looks like a change but no `ALTER` is issued.

**Makes API call?** NO -- state-only refresh.
**Changes behavior?** NO.

| Decision | When to use | How to resolve |
|----------|-------------|----------------|
| ACCEPT | Always | No code change. Disappears after first apply. |

---

### 4. Computed Policy / Config Recomputation

**What it looks like:**
```
policy: {"Statement":[...]} -> null
  # or
policy: {"Statement":[...]} -> (known after apply)
```

**Why it happens:** Resources with policies derived from `data` sources
(e.g., `aws_iam_policy_document`) show `(known after apply)` because
Terraform recomputes the policy at apply time. The result is identical.

**Makes API call?** YES -- e.g., `SetTopicAttributes`. Idempotent rewrite.
**Changes behavior?** NO -- same policy content.

| Decision | When to use | How to resolve |
|----------|-------------|----------------|
| ACCEPT | Policy inputs haven't changed | No code change. |
| INVESTIGATE | Policy inputs DID change (new principals, new actions) | Read the data source to confirm the policy is equivalent. |

---

### 5. New Privilege Addition

**What it looks like:**
```
privileges: ["SELECT"] -> ["REFERENCES", "SELECT"]
```

**Why it happens:** The new module grants a privilege (e.g., `REFERENCES`)
that the legacy config didn't include. This is a real additive change.

**Makes API call?** YES -- `GRANT REFERENCES`.
**Changes behavior?** Minimally -- `REFERENCES` allows foreign key constraints.

| Decision | When to use | How to resolve |
|----------|-------------|----------------|
| ACCEPT | Privilege is low-risk and matches QA | No code change. |
| FIX | Privilege shouldn't be added for this environment | Add variable to module to make the privilege set configurable. Pass legacy set from environment. |

---

### 6. Module Default vs Existing Value

**What it looks like:**
```
saml2_requested_nameid_format: "" -> "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
some_setting: "legacy_value" -> "module_default_value"
```

**Why it happens:** The module has a hardcoded or config-driven default that
differs from the value the resource was imported with.

**Makes API call?** YES -- `ALTER` statement. Real infrastructure change.
**Changes behavior?** Potentially.

| Decision | When to use | How to resolve |
|----------|-------------|----------------|
| ACCEPT | The module default is correct and the change is safe | No code change. |
| FIX (config override) | Module uses `try(local.config.key, default)` pattern | Add the key to environment's `config.yml` with the existing value. Module picks it up via `try()`. |
| FIX (new variable) | Module doesn't have a config path for this attribute | Add variable to module with `null` default. Use `var.x != null ? var.x : existing_logic` in resource. Pass existing value from environment. |
| IGNORE | Provider rejects the current value AND changing it is risky | Add attribute to `ignore_changes` in the resource lifecycle block. Document WHY with a comment and a post-migration action item. Last resort. |

**When IGNORE is the only option:** Sometimes the provider's validation is
stricter than what Snowflake stores. A value captured during import (e.g., `""`)
may be invalid according to the provider's enum. You can't write it back, but
you also don't want to change it. `ignore_changes` is the escape hatch.

---

### 7. Module Missing Configuration

**What it looks like:**
```
homepage_url:   "https://..." -> null
implicit_grant: [{...}]       -> []
```

**Why it happens:** The imported resource has attributes the module doesn't
expose as inputs. Terraform wants to null/empty them to match the module's
resource definition.

**Makes API call?** YES -- would remove the attribute from the live resource.
**Changes behavior?** YES -- destructive (removes existing configuration).

| Decision | When to use | How to resolve |
|----------|-------------|----------------|
| FIX (add variable) | The attribute matters and should be preserved | 1. Add variable to module (default `null`). 2. Use `dynamic` block or conditional in resource. 3. Pass existing value from environment. QA gets `null` default = no change. |
| ACCEPT | The attribute is genuinely unused and safe to remove | No code change. Confirm with `DESCRIBE` / portal that removing it has no effect. |

**Pattern for optional nested blocks:**
```hcl
dynamic "block_name" {
  for_each = var.block_config != null ? [var.block_config] : []
  content {
    attr = block_name.value.attr
  }
}
```
When variable is `null` (default), the block is absent. When set, it renders.

---

### 8. Certificate / Whitespace Normalization

**What it looks like:**
```
saml2_x509_cert: "MIIC8D...L4M\r\n" -> "MIIC8D...L4M\n"
```

**Why it happens:** Provider normalizes line endings or whitespace in
certificates, keys, or other multi-line strings.

**Makes API call?** YES -- `ALTER SECURITY INTEGRATION SET ...`
**Changes behavior?** NO -- same cert content.

| Decision | When to use | How to resolve |
|----------|-------------|----------------|
| ACCEPT | Content is identical, only formatting differs | No code change. One-time normalization. |
| IGNORE | Can't confirm content is identical, or cert is externally managed | Add to `ignore_changes`. |

---

## Create Types

### 9. Genuinely New Infrastructure

**What it looks like:**
```
# module.dms...replication_tasks["web-experience-default-export"] will be created
# module.raw_layer...schemas["MPONE_DB|WEB_EXPERIENCE_STREAMING"] will be created
```

**Why it happens:** The environment config defines resources that don't exist
yet in the target account (new DMS tasks, new schemas, new roles).

**Creates real infra?** YES.

| Decision | When to use | How to resolve |
|----------|-------------|----------------|
| ACCEPT | Resource exists in QA and is intentional | No code change. Let Terraform create it. |
| DEFER | Resource isn't needed yet or needs separate rollout | Remove from config or gate behind a variable/count. |

---

### 10. Module-Generated Grants

**What it looks like:**
```
# module.dpi_db...ddl_schemas[0] will be created
# module.standard_roles...hierarchy["SUPERUSER__ALL--ACCOUNTADMIN"] will be created
```

**Why it happens:** The module creates grants as part of its role hierarchy
or database profile. These grants weren't in the legacy config but are part
of the module's standard output. Some may already exist in Snowflake
(created manually or by other automation).

**Creates real infra?** YES -- but Snowflake `GRANT` is idempotent. If the
grant already exists, it's a no-op.

| Decision | When to use | How to resolve |
|----------|-------------|----------------|
| ACCEPT | Same grants exist in QA's module output | No code change. Idempotent if already present. |
| DEFER | Grant would change role hierarchy in a way that needs review | Disable via module variable (e.g., `enable_X = false`). |

---

### 11. State-Only Resources

**What it looks like:**
```
# module.snowdrift...tls_private_key.this[0] will be created
```

**Why it happens:** Some Terraform resources are local/computed -- they
generate values (keys, random IDs) stored in state but make no external
API calls.

**Creates real infra?** NO -- state only.

| Decision | When to use | How to resolve |
|----------|-------------|----------------|
| ACCEPT | Always (no external impact) | No code change. |

**Watch for downstream effects:** A `tls_private_key` may feed into a
`snowflake_service_user.rsa_public_key`. If the user is imported, check
that `rsa_public_key` is in `ignore_changes` to prevent overwriting the
existing key.

---

## Decision Framework

```
Is this a real infrastructure change?
+-- NO (state-only, computed refresh, idempotent rewrite)
|   +-- ACCEPT
+-- YES
    +-- Does it match QA?
    |   +-- YES and it's additive/safe -> ACCEPT
    |   +-- YES but risky (SSO, auth, networking) -> INVESTIGATE further
    +-- Does it NOT match QA?
        +-- Module default differs from existing value
        |   +-- Can we pass existing value? -> FIX (config or variable)
        |   +-- Provider rejects existing value? -> IGNORE (last resort)
        |   +-- Change is actually correct? -> ACCEPT
        +-- Module is missing configuration
            +-- FIX (add variable + dynamic block)
```

---

## Resolution Methods Summary

| Method | What it means | When to use | QA impact |
|--------|--------------|-------------|-----------|
| **ACCEPT** | Let Terraform apply the change | Safe, idempotent, or matches QA | None |
| **FIX (config override)** | Add key to `config.yml` | Module already has `try()` path for this setting | None -- QA has no key, falls through to default |
| **FIX (new variable)** | Add variable to module + pass from env | Module doesn't expose the setting | None -- variable defaults to `null` |
| **FIX (dynamic block)** | Conditional nested block in resource | Module missing an entire config block | None -- block absent when variable is `null` |
| **IGNORE** | Add to `ignore_changes` lifecycle | Provider rejects current value AND change is risky | None if QA's value is already correct in state |
| **DEFER** | Remove from config or disable via variable | Resource isn't ready for this environment | None |
