// Cedar policy for PII (Personally Identifiable Information) protection
// Restricts access to sensitive data based on user role and context

permit (
  principal,
  action in [Action::"read", Action::"process"],
  resource
)
when {
  // Allow access only to authorized roles
  principal.role in [Role::"data_analyst", Role::"admin"] &&

  // Must have explicit PII handling certification
  principal has pii_certified &&
  principal.pii_certified == true &&

  // Data classification must be appropriate
  resource.classification == Classification::"pii" &&

  // Access context must be secure
  context.encryption == true &&
  context.audit_logging == true
};

// Deny any direct access to raw PII data
deny (
  principal,
  action == Action::"export",
  resource
)
when {
  resource.contains_pii == true &&
  principal.role == Role::"user"
};

// Require approval for PII modification
permit (
  principal,
  action == Action::"update",
  resource
)
when {
  resource.contains_pii == true &&
  principal.role == Role::"admin" &&
  context.has_approval == true &&
  context.approval_level >= 2
};
