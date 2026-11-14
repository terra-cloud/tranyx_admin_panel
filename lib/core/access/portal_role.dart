/// Roles stored on the admin-portal staff directory (`tranyx-admin-portal` `users/{uid}.role`).
/// Email text is not a role and does not grant access.
bool portalRoleIsAdmin(String? role) {
  switch ((role ?? '').toLowerCase().trim()) {
    case 'admin':
    case 'superadmin':
    case 'super_admin':
      return true;
    default:
      return false;
  }
}

/// Roles that may use the portal at all. Still not inferred from the email address.
bool portalRoleMayUsePortal(String? role) {
  switch ((role ?? '').toLowerCase().trim()) {
    case 'admin':
    case 'superadmin':
    case 'super_admin':
    case 'staff':
    case 'support':
    case 'agent':
    case 'p2p_agent':
      return true;
    default:
      return false;
  }
}

/// Claim `role` sent to the workspace. Null when the portal role is not assignable.
String? workspaceClaimRole(String? portalRole) {
  switch ((portalRole ?? '').toLowerCase().trim()) {
    case 'admin':
    case 'superadmin':
    case 'super_admin':
      return 'admin';
    case 'staff':
    case 'support':
      return 'staff';
    case 'agent':
    case 'p2p_agent':
      return 'agent';
    default:
      return null;
  }
}
