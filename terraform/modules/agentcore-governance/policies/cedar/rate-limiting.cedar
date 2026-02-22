// Cedar policy for rate limiting and resource protection
// Controls resource usage and prevents abuse

permit (
  principal,
  action in [Action::"invoke", Action::"query"],
  resource
)
when {
  // Rate limit checks
  context.request_count_per_minute < 100 &&
  context.request_count_per_hour < 10000 &&

  // User quota checks
  principal.has_quota == true &&
  principal.remaining_quota > 0 &&

  // Time-based restrictions
  context.current_time >= principal.access_start_time &&
  context.current_time <= principal.access_end_time &&

  // Resource availability
  resource.availability_status == AvailabilityStatus::"available"
};

// Deny if rate limits exceeded
deny (
  principal,
  action in [Action::"invoke", Action::"query"],
  resource
)
when {
  context.request_count_per_minute >= 100 ||
  context.request_count_per_hour >= 10000
};

// Deny access outside allowed hours
deny (
  principal,
  action in [Action::"invoke"],
  resource
)
when {
  context.current_time < principal.access_start_time ||
  context.current_time > principal.access_end_time
};

// Special handling for premium users (increased limits)
permit (
  principal,
  action in [Action::"invoke", Action::"query"],
  resource
)
when {
  principal.subscription_tier == SubscriptionTier::"premium" &&
  context.request_count_per_minute < 500 &&
  context.request_count_per_hour < 50000
};
