import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/goat_theme.dart';
import '../../../../providers/profile_provider.dart';
import '../goat_setup_applier.dart';
import '../goat_setup_models.dart';
import '../goat_setup_providers.dart';
import '../widgets/goat_setup_profile_fields.dart';
import '../widgets/goat_setup_section_review_cards.dart';

/// Manual form path: same review cards as chat, starting from an empty editable template.
class GoatSetupFormFallbackScreen extends ConsumerStatefulWidget {
  const GoatSetupFormFallbackScreen({super.key});

  @override
  ConsumerState<GoatSetupFormFallbackScreen> createState() => _GoatSetupFormFallbackScreenState();
}

class _GoatSetupFormFallbackScreenState extends ConsumerState<GoatSetupFormFallbackScreen> {
  late GoatSetupInterpretResult _draft;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _draft = GoatSetupInterpretResult.emptyTemplate().copyForReview();
  }

  void _patchRaw(String key, dynamic value) {
    final j = Map<String, dynamic>.from(_draft.raw);
    j[key] = value;
    setState(() => _draft = GoatSetupInterpretResult.fromJson(j));
  }

  Future<void> _apply() async {
    final currency = ref.read(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'INR';
    setState(() => _loading = true);
    try {
      await GoatSetupApplier.applyInterpretation(
        draft: _draft,
        draftId: null,
        preferredCurrencyFallback: currency,
      );
      await refreshGoatSetupAfterApply(ref);
      if (mounted) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('GOAT setup (forms)'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            Text(
              'Fill what you know. Only checked sections with valid values are saved.',
              style: TextStyle(color: GoatTokens.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            GoatSetupDraftReviewCard(
              title: 'Profile defaults',
              child: GoatSetupProfileFields(
                initial: d.profileDefaults,
                onChanged: (m) => _patchRaw('profile_defaults', m),
              ),
            ),
            _addRowBar(
              label: 'Account',
              onAdd: () {
                final list = List<Map<String, dynamic>>.from(d.accounts)..add(GoatSetupInterpretResult.templateAccountRow());
                _patchRaw('accounts', list);
              },
            ),
            GoatSetupDraftReviewCard(
              title: 'Accounts',
              child: GoatSetupAccountsReviewCard(
                rows: d.accounts,
                onChanged: (i, next) {
                  final list = List<Map<String, dynamic>>.from(d.accounts);
                  list[i] = next;
                  _patchRaw('accounts', list);
                },
              ),
            ),
            _addRowBar(
              label: 'Income stream',
              onAdd: () {
                final list = List<Map<String, dynamic>>.from(d.incomeStreams)..add(GoatSetupInterpretResult.templateIncomeRow());
                _patchRaw('income_streams', list);
              },
            ),
            GoatSetupDraftReviewCard(
              title: 'Income',
              child: GoatSetupIncomeReviewCard(
                rows: d.incomeStreams,
                onChanged: (i, next) {
                  final list = List<Map<String, dynamic>>.from(d.incomeStreams);
                  list[i] = next;
                  _patchRaw('income_streams', list);
                },
              ),
            ),
            _addRowBar(
              label: 'Recurring bill',
              onAdd: () {
                final list = List<Map<String, dynamic>>.from(d.recurringItems)..add(GoatSetupInterpretResult.templateRecurringRow());
                _patchRaw('recurring_items', list);
              },
            ),
            GoatSetupDraftReviewCard(
              title: 'Recurring',
              child: GoatSetupRecurringReviewCard(
                rows: d.recurringItems,
                onChanged: (i, next) {
                  final list = List<Map<String, dynamic>>.from(d.recurringItems);
                  list[i] = next;
                  _patchRaw('recurring_items', list);
                },
              ),
            ),
            _addRowBar(
              label: 'Planned event',
              onAdd: () {
                final list = List<Map<String, dynamic>>.from(d.plannedEvents)..add(GoatSetupInterpretResult.templatePlannedRow());
                _patchRaw('planned_cashflow_events', list);
              },
            ),
            GoatSetupDraftReviewCard(
              title: 'Planned cashflow',
              child: GoatSetupPlannedEventsReviewCard(
                rows: d.plannedEvents,
                onChanged: (i, next) {
                  final list = List<Map<String, dynamic>>.from(d.plannedEvents);
                  list[i] = next;
                  _patchRaw('planned_cashflow_events', list);
                },
              ),
            ),
            _addRowBar(
              label: 'Goal',
              onAdd: () {
                final list = List<Map<String, dynamic>>.from(d.goals)..add(GoatSetupInterpretResult.templateGoalRow());
                _patchRaw('goals', list);
              },
            ),
            GoatSetupDraftReviewCard(
              title: 'Goals',
              child: GoatSetupGoalsReviewCard(
                rows: d.goals,
                onChanged: (i, next) {
                  final list = List<Map<String, dynamic>>.from(d.goals);
                  list[i] = next;
                  _patchRaw('goals', list);
                },
              ),
            ),
            GoatSetupDraftReviewCard(
              title: 'Source preference',
              child: GoatSetupSourcePreferenceCard(
                pref: d.sourcePreference,
                onChanged: (next) => _patchRaw('source_preference', next),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _apply,
              style: FilledButton.styleFrom(
                backgroundColor: GoatTokens.gold,
                foregroundColor: Colors.black87,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Save confirmed items'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addRowBar({required String label, required VoidCallback onAdd}) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded, size: 18, color: GoatTokens.gold),
        label: Text('Add $label', style: const TextStyle(color: GoatTokens.gold)),
      ),
    );
  }
}
