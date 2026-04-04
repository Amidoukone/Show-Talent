const publicSelfSignupRoles = <String>[
  'joueur',
  'fan',
];

const managedAccountRoles = <String>[
  'club',
  'recruteur',
  'agent',
];

const opportunityPublisherRoles = <String>[
  'club',
  'recruteur',
  'agent',
];

const adminPortalOnlyRoles = <String>[
  'admin',
];

String normalizeUserRole(String? role) => role?.trim().toLowerCase() ?? '';

bool isPublicSelfSignupRole(String? role) {
  return publicSelfSignupRoles.contains(normalizeUserRole(role));
}

bool isManagedAccountRole(String? role) {
  return managedAccountRoles.contains(normalizeUserRole(role));
}

bool isOpportunityPublisherRole(String? role) {
  return opportunityPublisherRoles.contains(normalizeUserRole(role));
}

bool isAdminPortalOnlyRole(String? role) {
  return adminPortalOnlyRoles.contains(normalizeUserRole(role));
}
