import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/profile_provider.dart';
import '../models/goat_models.dart';
import '../services/goat_mode_service.dart';

/// The currently-selected scope chip on the Goat Mode screen. Pure UI state —
/// switching scopes does NOT re-trigger a backend run; it only re-renders from
/// the latest snapshot (which already contains all pillars in `metrics_json`).
final goatSelectedScopeProvider =
    StateProvider<GoatScope>((_) => GoatScope.overview);

/// The consolidated state object the screen reads.
///
/// Immutable so widget rebuilds stay cheap and motion transitions are clean.
@immutable
class GoatModeState {
  final GoatSnapshot? latestSnapshot;
  final GoatJob? latestJob;
  final List<GoatRecommendation> recommendations;
  final DateTime? lastRefreshedAt;
  final bool isRefreshing;
  final bool pollingTimedOut;
  final String? errorMessage;

  const GoatModeState({
    this.latestSnapshot,
    this.latestJob,
    this.recommendations = const [],
    this.lastRefreshedAt,
    this.isRefreshing = false,
    this.pollingTimedOut = false,
    this.errorMessage,
  });

  bool get hasSnapshot => latestSnapshot != null;
  bool get isFirstLoad => latestSnapshot == null && latestJob == null;

  /// Shown as the top-level status chip. Prefers job status while a run is in
  /// flight, then falls back to snapshot freshness.
  GoatJobStatus get effectiveStatus {
    if (isRefreshing) {
      return latestJob?.status == GoatJobStatus.unknown
          ? GoatJobStatus.queued
          : (latestJob?.status ?? GoatJobStatus.queued);
    }
    return latestJob?.status ?? GoatJobStatus.unknown;
  }

  GoatModeState copyWith({
    GoatSnapshot? latestSnapshot,
    GoatJob? latestJob,
    List<GoatRecommendation>? recommendations,
    DateTime? lastRefreshedAt,
    bool? isRefreshing,
    bool? pollingTimedOut,
    Object? errorMessage = _sentinel,
  }) {
    return GoatModeState(
      latestSnapshot: latestSnapshot ?? this.latestSnapshot,
      latestJob: latestJob ?? this.latestJob,
      recommendations: recommendations ?? this.recommendations,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      pollingTimedOut: pollingTimedOut ?? this.pollingTimedOut,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

const _sentinel = Object();

/// Polling policy — small, readable knobs.
///
/// Intervals deliberately start fast and back off so the UX feels snappy for
/// the common quick-run case but doesn't hammer Supabase if compute is slow.
class GoatPollingPolicy {
  final Duration initialDelay;
  final Duration interval;
  final Duration maxTotal;

  const GoatPollingPolicy({
    this.initialDelay = const Duration(milliseconds: 600),
    this.interval = const Duration(seconds: 2),
    this.maxTotal = const Duration(seconds: 120),
  });
}

/// Owns the Goat Mode screen lifecycle: initial load → trigger → poll → read.
class GoatModeController extends AsyncNotifier<GoatModeState> {
  Timer? _pollTimer;
  int _refreshGen = 0; // cancels stale polling loops on rapid re-triggers

  GoatPollingPolicy get policy => const GoatPollingPolicy();

  @override
  Future<GoatModeState> build() async {
    ref.onDispose(() {
      _pollTimer?.cancel();
      _pollTimer = null;
    });

    // Initial load: latest snapshot + open recs + latest job.
    // All reads are RLS-scoped; parallel fan-out keeps first paint fast.
    final results = await Future.wait<Object?>([
      GoatModeService.fetchLatestSnapshot(),
      GoatModeService.fetchOpenRecommendations(),
      GoatModeService.fetchLatestJob(),
    ]);

    return GoatModeState(
      latestSnapshot: results[0] as GoatSnapshot?,
      recommendations:
          (results[1] as List<GoatRecommendation>? ?? const <GoatRecommendation>[]),
      latestJob: results[2] as GoatJob?,
      lastRefreshedAt: (results[0] as GoatSnapshot?)?.generatedAt,
    );
  }

  /// Trigger a Goat Mode refresh. Optimistically flips to a "queued" state so
  /// the user sees motion immediately; the actual edge call + polling run in
  /// the background.
  ///
  /// We preserve any existing snapshot on screen so the user never sees a
  /// blank screen mid-refresh.
  Future<void> refresh({
    GoatScope scope = GoatScope.full,
    bool dryRun = false,
  }) async {
    final gen = ++_refreshGen;
    _pollTimer?.cancel();

    final current = state.valueOrNull ?? const GoatModeState();
    state = AsyncData(current.copyWith(
      isRefreshing: true,
      pollingTimedOut: false,
      errorMessage: null,
    ));

    Map<String, dynamic> triggerResp;
    try {
      triggerResp = await GoatModeService.triggerRefresh(
        scope: scope,
        dryRun: dryRun,
      );
    } on GoatModeException catch (e) {
      if (gen != _refreshGen) return; // stale
      state = AsyncData(current.copyWith(
        isRefreshing: false,
        errorMessage: e.message,
      ));
      return;
    } catch (e) {
      if (gen != _refreshGen) return;
      state = AsyncData(current.copyWith(
        isRefreshing: false,
        errorMessage: 'Something went wrong while starting the refresh.',
      ));
      if (kDebugMode) debugPrint('[GOAT] trigger error: $e');
      return;
    }

    final jobId = triggerResp['job_id'] as String?;
    if (jobId == null) {
      // Backend returned without a job (dry-run or inline path). Pull whatever
      // it wrote right away — snapshot may already be up-to-date.
      await _refetchAfterTerminal(gen);
      return;
    }

    // Start polling loop.
    _pollJob(jobId: jobId, gen: gen);
  }

  void _pollJob({required String jobId, required int gen}) {
    final p = policy;
    final deadline = DateTime.now().add(p.maxTotal);

    Future<void> tick() async {
      if (gen != _refreshGen) return;
      GoatJob? job;
      try {
        job = await GoatModeService.fetchJobById(jobId);
      } catch (e) {
        if (kDebugMode) debugPrint('[GOAT] poll error: $e');
        // soft-fail: keep polling until deadline
      }
      if (gen != _refreshGen) return;

      final current = state.valueOrNull ?? const GoatModeState();
      if (job != null) {
        state = AsyncData(current.copyWith(latestJob: job));
      }

      final reachedTerminal = job != null && job.status.isTerminal;
      final timedOut = DateTime.now().isAfter(deadline);

      if (reachedTerminal) {
        await _refetchAfterTerminal(gen, job: job);
        return;
      }
      if (timedOut) {
        final latest = state.valueOrNull ?? const GoatModeState();
        state = AsyncData(latest.copyWith(
          isRefreshing: false,
          pollingTimedOut: true,
          errorMessage:
              'Refresh is taking longer than usual — we\'ll keep the last snapshot here.',
        ));
        return;
      }

      _pollTimer = Timer(p.interval, tick);
    }

    _pollTimer = Timer(p.initialDelay, tick);
  }

  /// After a job reaches a terminal state we re-read snapshot + recs once and
  /// clear the refreshing flag. Partial/failed is still treated as terminal —
  /// we just surface the state accurately.
  Future<void> _refetchAfterTerminal(int gen, {GoatJob? job}) async {
    try {
      final results = await Future.wait<Object?>([
        GoatModeService.fetchLatestSnapshot(),
        GoatModeService.fetchOpenRecommendations(),
      ]);
      if (gen != _refreshGen) return;
      final snap = results[0] as GoatSnapshot?;
      final recs = (results[1] as List<GoatRecommendation>? ??
          const <GoatRecommendation>[]);
      final current = state.valueOrNull ?? const GoatModeState();

      String? errMsg;
      if (job?.status == GoatJobStatus.failed) {
        errMsg = job?.errorMessage?.isNotEmpty == true
            ? job!.errorMessage
            : 'The refresh failed. Try again in a moment.';
      }

      state = AsyncData(current.copyWith(
        latestSnapshot: snap ?? current.latestSnapshot,
        recommendations: recs,
        latestJob: job ?? current.latestJob,
        lastRefreshedAt: snap?.generatedAt ?? current.lastRefreshedAt,
        isRefreshing: false,
        errorMessage: errMsg,
      ));
    } catch (e) {
      if (gen != _refreshGen) return;
      final current = state.valueOrNull ?? const GoatModeState();
      state = AsyncData(current.copyWith(
        isRefreshing: false,
        errorMessage: 'Refresh completed but loading the result failed.',
      ));
      if (kDebugMode) debugPrint('[GOAT] post-terminal fetch error: $e');
    }
  }

  /// Manual re-pull of snapshot + recs without triggering a backend run.
  /// Used by pull-to-refresh.
  Future<void> reloadFromDb() async {
    final gen = ++_refreshGen; // cancels any in-flight polling
    _pollTimer?.cancel();
    state = const AsyncLoading<GoatModeState>()
        .copyWithPrevious(state);
    try {
      final results = await Future.wait<Object?>([
        GoatModeService.fetchLatestSnapshot(),
        GoatModeService.fetchOpenRecommendations(),
        GoatModeService.fetchLatestJob(),
      ]);
      if (gen != _refreshGen) return;
      state = AsyncData(GoatModeState(
        latestSnapshot: results[0] as GoatSnapshot?,
        recommendations:
            (results[1] as List<GoatRecommendation>? ?? const <GoatRecommendation>[]),
        latestJob: results[2] as GoatJob?,
        lastRefreshedAt: (results[0] as GoatSnapshot?)?.generatedAt,
      ));
    } catch (e, st) {
      if (gen != _refreshGen) return;
      state = AsyncError<GoatModeState>(e, st);
    }
  }

  /// Clear the current error banner without re-running anything.
  void dismissError() {
    final current = state.valueOrNull;
    if (current?.errorMessage == null) return;
    state = AsyncData(current!.copyWith(errorMessage: null));
  }

  /// Exposed so sibling providers (e.g. recommendation actions) can apply an
  /// optimistic edit to the cached `recommendations` list without rewriting
  /// the whole controller's lifecycle. Keeps writes honest:
  ///   - optimistic update goes through here
  ///   - on server error the caller passes the previous state right back
  /// Nothing in the refresh/poll lifecycle reads this method, so it cannot
  /// corrupt an in-flight run.
  ///
  /// Intentionally internal to the Goat feature — do not call from outside
  /// `lib/features/goat/`.
  void setStateForActions(GoatModeState next) {
    state = AsyncData(next);
  }
}

/// The Goat Mode controller — single source of truth for the screen.
final goatModeControllerProvider =
    AsyncNotifierProvider<GoatModeController, GoatModeState>(
  GoatModeController.new,
);

/// Thin derived provider — `true` iff the signed-in user's profile has
/// `goat_mode = true`. Mirrors `profileGoatModeEnabled` from profile provider.
final goatModeEntitlementProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  return profileGoatModeEnabled(profile);
});
