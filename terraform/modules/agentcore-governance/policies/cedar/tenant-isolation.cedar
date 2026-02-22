// Cedar policy for tenant isolation (Rule 14.3 ABAC enforcement)
// Enforces that principals can only access resources belonging to their own tenant.
// This implements the principal.tenant_id == resource.tenant_id requirement.

// Permit: principal can access resources with matching tenant_id
permit (
  principal,
  action,
  resource
)
when {
  principal has tenant_id &&
  resource has tenant_id &&
  principal.tenant_id == resource.tenant_id
};

// Deny: explicitly block cross-tenant access
deny (
  principal,
  action,
  resource
)
when {
  principal has tenant_id &&
  resource has tenant_id &&
  principal.tenant_id != resource.tenant_id
};

// Deny: principal with tenant_id context cannot access untagged resources
deny (
  principal,
  action,
  resource
)
when {
  principal has tenant_id &&
  !(resource has tenant_id)
};
