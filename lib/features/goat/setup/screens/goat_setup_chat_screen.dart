import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/goat_theme.dart';
import '../../../../providers/profile_provider.dart';
import '../goat_setup_interpret_service.dart';
import '../goat_setup_models.dart';
import '../goat_setup_providers.dart';
import '../goat_setup_repository.dart';
import '../goat_setup_applier.dart';
import '../widgets/goat_setup_message_composer.dart';
import '../widgets/goat_setup_profile_fields.dart';
import '../widgets/goat_setup_section_review_cards.dart';
import 'goat_setup_form_fallback_screen.dart';

class GoatSetupChatScreen extends ConsumerStatefulWidget {
  const GoatSetupChatScreen({super.key, this.guidedOneAtATime = false});

  final bool guidedOneAtATime;

  @override
  ConsumerState<GoatSetupChatScreen> createState() => _GoatSetupChatScreenState();
}

class _GoatSetupChatScreenState extends ConsumerState<GoatSetupChatScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _messages = <_ChatMsg>[];
  GoatSetupInterpretResult? _draft;
  String? _serverDraftId;
  bool _loading = false;
  String? _error;

  final _gIncome = TextEditingController();
  final _gAccounts = TextEditingController();
  final _gBills = TextEditingController();
  final _gGoals = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _messages.add(
      const _ChatMsg(
        text:
            'Tell me what you already know — GOAT will structure it. Nothing is saved until you confirm on the Review tab.',
        fromUser: false,
      ),
    );
    _hydrateLastDraft();
  }

  Future<void> _hydrateLastDraft() async {
    final row = await GoatSetupRepository.fetchLatestDraft();
    if (row == null) return;
    final status = row['parse_status'] as String? ?? '';
    if (status != 'draft') return;
    final payload = row['parsed_payload'];
    if (payload is! Map) return;
    if (!mounted) return;
    setState(() {
      _draft = GoatSetupInterpretResult.fromJson(Map<String, dynamic>.from(payload)).copyForReview();
      _serverDraftId = row['id'] as String?;
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _gIncome.dispose();
    _gAccounts.dispose();
    _gBills.dispose();
    _gGoals.dispose();
    super.dispose();
  }

  int _aiCallsUsed() {
    final row = ref.read(goatSetupStateProvider).valueOrNull;
    return goatAiCallsUsed(row) ?? 0;
  }

  Future<void> _sendUserMessage(String text) async {
    setState(() {
      _error = null;
      _loading = true;
      _messages.add(_ChatMsg(text: text, fromUser: true));
    });

    final prefill = await ref.read(setupPrefillProvider.future);
    final callIndex = _aiCallsUsed() >= 1 ? 2 : 1;
    final context = <String, dynamic>{
      ...prefill,
      if (callIndex == 2 && _draft != null) 'previous_draft': _draft!.raw,
    };

    try {
      final out = await GoatSetupInterpretService.interpret(
        message: text,
        callIndex: callIndex,
        context: context,
      );
      if (!mounted) return;
      setState(() {
        _draft = out.interpretation.copyForReview();
        _serverDraftId = out.draftId;
        _loading = false;
        final summary = (out.interpretation.readinessHints['summary'] as String?)?.trim();
        _messages.add(
          _ChatMsg(
            text: summary != null && summary.isNotEmpty
                ? 'Here is a structured draft (${(out.interpretation.overallConfidence * 100).round()}% overall confidence). Review before saving.\n$summary'
                : 'Here is a structured draft. Open the Review tab to confirm or edit each section before saving.',
            fromUser: false,
          ),
        );
        if (out.followupSuggested && (out.callsAfter ?? 0) < 2) {
          _messages.add(
            const _ChatMsg(
              text: 'If something important still looks off, send one short follow-up — I can merge it (uses your second AI pass).',
              fromUser: false,
            ),
          );
        }
      });
      ref.invalidate(goatSetupStateProvider);
      _tabs.animateTo(1);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        if (e.toString().contains('ai_call_limit')) {
          _messages.add(
            const _ChatMsg(
              text: 'This setup session has already used both AI interpretation passes. Continue editing manually on the Review tab.',
              fromUser: false,
            ),
          );
        }
      });
    }
  }

  Future<void> _sendGuidedBundle() async {
    final parts = <String>[];
    if (_gIncome.text.trim().isNotEmpty) parts.add('Income: ${_gIncome.text.trim()}');
    if (_gAccounts.text.trim().isNotEmpty) parts.add('Accounts & balances: ${_gAccounts.text.trim()}');
    if (_gBills.text.trim().isNotEmpty) parts.add('Bills & subscriptions: ${_gBills.text.trim()}');
    if (_gGoals.text.trim().isNotEmpty) parts.add('Goals: ${_gGoals.text.trim()}');
    if (parts.isEmpty) {
      setState(() => _error = 'Add at least one answer.');
      return;
    }
    await _sendUserMessage(parts.join('\n'));
  }

  void _patchRaw(String key, dynamic value) {
    final d = _draft;
    if (d == null) return;
    final j = Map<String, dynamic>.from(d.raw);
    j[key] = value;
    setState(() => _draft = GoatSetupInterpretResult.fromJson(j));
  }

  Future<void> _apply() async {
    final d = _draft;
    if (d == null) return;
    final currency = ref.read(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'INR';
    setState(() => _loading = true);
    try {
      await GoatSetupApplier.applyInterpretation(
        draft: d,
        draftId: _serverDraftId,
        preferredCurrencyFallback: currency,
      );
      await refreshGoatSetupAfterApply(ref);
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == '/goat');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final used = _aiCallsUsed();
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('GOAT setup chat'),
          bottom: TabBar(
            controller: _tabs,
            indicatorColor: GoatTokens.gold,
            labelColor: GoatTokens.gold,
            unselectedLabelColor: GoatTokens.textMuted,
            tabs: const [
              Tab(text: 'Chat'),
              Tab(text: 'Review'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Text(
                    'AI passes used: $used / 2',
                    style: TextStyle(color: GoatTokens.textMuted, fontSize: 12),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(builder: (_) => const GoatSetupFormFallbackScreen()),
                    ),
                    child: const Text('Use forms'),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade200, fontSize: 12)),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildChatTab(),
                  _buildReviewTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatTab() {
    final used = _aiCallsUsed();
    if (widget.guidedOneAtATime) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Text(
            'Answer in any order — we bundle into one message so GOAT uses a single AI pass when possible.',
            style: TextStyle(color: GoatTokens.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          _guidedField('Income & pay schedule', _gIncome),
          _guidedField('Accounts & balances', _gAccounts),
          _guidedField('Bills, EMI, subscriptions', _gBills),
          _guidedField('Goals or sinking funds', _gGoals),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _sendGuidedBundle,
            style: FilledButton.styleFrom(backgroundColor: GoatTokens.gold, foregroundColor: Colors.black87),
            child: const Text('Interpret with AI'),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            itemCount: _messages.length,
            itemBuilder: (_, i) => _bubble(_messages[i]),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2, color: GoatTokens.gold),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: GoatSetupMessageComposer(
            enabled: !_loading && used < 2,
            onSend: _sendUserMessage,
          ),
        ),
      ],
    );
  }

  Widget _guidedField(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: 3,
        style: const TextStyle(color: GoatTokens.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: GoatTokens.textMuted),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: GoatTokens.borderSubtle)),
          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: GoatTokens.gold)),
        ),
      ),
    );
  }

  Widget _bubble(_ChatMsg m) {
    final align = m.fromUser ? Alignment.centerRight : Alignment.centerLeft;
    final bg = m.fromUser ? GoatTokens.gold.withValues(alpha: 0.18) : GoatTokens.surfaceElevated;
    final fg = GoatTokens.textPrimary;
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GoatTokens.borderSubtle),
        ),
        child: Text(m.text, style: TextStyle(color: fg, height: 1.35)),
      ),
    );
  }

  Widget _buildReviewTab() {
    final d = _draft;
    if (d == null) {
      return Center(
        child: Text(
          'No draft yet — chat on the first tab.',
          style: TextStyle(color: GoatTokens.textMuted),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Text(
          'Review extracted values. Toggle off anything you do not want saved.',
          style: TextStyle(color: GoatTokens.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 14),
        GoatSetupDraftReviewCard(
          title: 'Profile defaults',
          subtitle: 'Currency & GOAT lens',
          child: GoatSetupProfileFields(
            initial: d.profileDefaults,
            onChanged: (m) => _patchRaw('profile_defaults', m),
          ),
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
    );
  }
}

class _ChatMsg {
  const _ChatMsg({required this.text, required this.fromUser});
  final String text;
  final bool fromUser;
}
