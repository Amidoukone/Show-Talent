import 'package:cloud_firestore/cloud_firestore.dart';

/// Which of the two player populations an account belongs to.
///
/// Adfoot has two kinds of player, and they are commercially opposite:
///
/// - [adfoot] — under contract with the agency. Pays nothing, ever: neither
///   registration nor accompaniment. The agency trains them and looks for
///   opportunities.
/// - [external] — free of any tie to the agency, may belong to a club or an
///   academy, and pays for the services they use.
///
/// [none] is what every account carries today and what an account carries
/// until the administration records something. It is deliberately **not** a
/// synonym for "external": an account with no recorded membership must keep
/// behaving exactly as it does now.
enum MembershipTier { none, adfoot, external }

/// What the administration has recorded about an account's entitlements.
///
/// This is a *mirror*, never a source of truth for money. Payment happens
/// outside the application — mobile money, transfer, cash at the agency — and
/// the administration records the outcome through the admin portal. The mobile
/// app never displays a price, never offers a way to pay and never links to
/// one, which is what keeps the Play Console declaration ("no in-app
/// purchases") true.
///
/// It is also unwritable by the client: `membership` is absent from the
/// `canUpdateOwnProfile` allowlist in firestore.rules, so the only writer is
/// the admin callable running under the Admin SDK. A guardrail test asserts it
/// stays that way.
class Membership {
  const Membership({
    this.tier = MembershipTier.none,
    this.startedAt,
    this.validUntil,
    this.reference,
  });

  final MembershipTier tier;
  final DateTime? startedAt;

  /// When the entitlement lapses, or null when it does not.
  ///
  /// Null is the normal case for an [MembershipTier.adfoot] player: they are
  /// tied to the agency by a contract, not by a subscription period.
  final DateTime? validUntil;

  /// The administration's own reference for the payment or the contract.
  ///
  /// Free text, recorded so a question about an account can be answered
  /// without leaving the portal. Never shown in the mobile app.
  final String? reference;

  static const Membership none = Membership();

  /// True while the entitlement is recorded and has not lapsed.
  ///
  /// An account with no recorded membership is not "expired", it is
  /// unrecorded — see [MembershipTier.none]. Callers that gate a feature must
  /// decide explicitly what to do with an unrecorded account rather than
  /// letting it fall into the same branch as a lapsed one.
  bool isActiveAt(DateTime now) {
    if (tier == MembershipTier.none) return false;
    final until = validUntil;
    return until == null || until.isAfter(now);
  }

  bool get isRecorded => tier != MembershipTier.none;

  /// True for a player the agency carries at its own cost.
  bool get isAgencyPlayer => tier == MembershipTier.adfoot;

  /// True while the agency actually carries this account.
  ///
  /// [isAgencyPlayer] says what was recorded, not whether it still holds: an
  /// `adfoot` record given a term and left to lapse would go on claiming the
  /// agency backs a player it no longer backs. Anything other people see —
  /// the profile badge — must ask this one.
  bool isAgencyPlayerAt(DateTime now) => isAgencyPlayer && isActiveAt(now);

  static MembershipTier parseTier(Object? raw) {
    switch (raw?.toString().trim().toLowerCase()) {
      case 'adfoot':
        return MembershipTier.adfoot;
      case 'external':
      case 'externe':
        return MembershipTier.external;
      default:
        return MembershipTier.none;
    }
  }

  static String tierToString(MembershipTier tier) {
    switch (tier) {
      case MembershipTier.adfoot:
        return 'adfoot';
      case MembershipTier.external:
        return 'external';
      case MembershipTier.none:
        return 'none';
    }
  }

  /// Reads the `membership` map off a user document.
  ///
  /// Anything malformed yields [none] rather than throwing: this map is
  /// written by an admin tool that will evolve, and a profile must never fail
  /// to load because an entitlement field arrived in a shape this build does
  /// not know.
  factory Membership.fromMap(Object? raw) {
    if (raw is! Map) return none;
    final map = Map<String, dynamic>.from(raw);

    DateTime? date(Object? value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String && value.trim().isNotEmpty) {
        return DateTime.tryParse(value.trim());
      }
      return null;
    }

    final reference = map['reference']?.toString().trim();

    return Membership(
      tier: parseTier(map['tier']),
      startedAt: date(map['startedAt']),
      validUntil: date(map['validUntil']),
      reference: (reference == null || reference.isEmpty) ? null : reference,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'tier': tierToString(tier),
      'startedAt': startedAt == null ? null : Timestamp.fromDate(startedAt!),
      'validUntil': validUntil == null ? null : Timestamp.fromDate(validUntil!),
      'reference': reference,
    };
  }
}
