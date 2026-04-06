import '../models/app_user.dart';
import '../models/compliance_rule_set.dart';

class ComplianceRuleSetUtils {
  ComplianceRuleSetUtils._();

  static List<ComplianceRuleSet> effectiveRuleSets({
    required List<ComplianceRuleSet> ruleSets,
    required AppUserProfile? currentUser,
  }) {
    if (ruleSets.isNotEmpty) {
      return ruleSets;
    }
    if (currentUser == null) {
      return const [];
    }
    return [
      ComplianceRuleSet.defaultRetail(
        currentUser.orgId,
        createdByUid: currentUser.uid,
      ),
    ];
  }
}
