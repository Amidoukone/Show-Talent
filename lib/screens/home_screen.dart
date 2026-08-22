import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:adfoot/config/feature_controller_registry.dart';
import 'package:adfoot/screens/add_video.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/connectivity_controller.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/services/home/home_feed_repository.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/utils/video_search_matcher.dart';

import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:adfoot/widgets/video_feed_pager.dart';
import 'package:adfoot/videos/video_manager.dart';
import 'package:adfoot/services/app_logger.dart';

part 'home_screen_search_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.homeFeedRepository = const HomeFeedRepository(),
  });

  final HomeFeedRepository homeFeedRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final VideoController videoController;
  final UserController userController = Get.find<UserController>();
  final FollowController followController = Get.find<FollowController>();
  final VideoFeedPagerController _pager = VideoFeedPagerController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ValueNotifier<int> _searchUiRevision = ValueNotifier<int>(0);
  final VideoManager videoManager = VideoManager();


  static const int _searchUidBatchSize = 10;
  static const int _searchResultLimit = 60;
  static const int _searchRecentScanLimit = 120;

  bool _isConnected = true;
  bool _isSearchLoading = false;
  bool _searchUsersHydrated = false;
  String _searchQuery = '';
  String? _searchError;
  List<Video> _searchResults = const <Video>[];

  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _searchDebounce;
  bool _hasHandledRouteRefresh = false;
  bool _routeRefreshRequested = false;
  String? _routeFocusVideoId;
  bool _isSearchSheetOpen = false;
  bool _wasHomeFeedEmpty = true;
  int _searchRequestToken = 0;
  int? _feedIndexBeforeSearch;

  bool get _isSearchActive => _searchQuery.trim().isNotEmpty;

  // ---------------------------------------------------------------------------
  // Wakelock
  // ---------------------------------------------------------------------------
  //
  // Owned by SmartVideoPlayer, and only by it.
  //
  // `WakelockPlus` is a single device-wide switch, and this screen used to
  // drive it too, from its own cached boolean. Two owners, one switch, two
  // caches that could not see each other: the player disabling it on pause
  // left this screen still believing it was on, so the next
  // `_setWakelock(true)` short-circuited on `_wakelockOn == enable` and never
  // re-enabled anything — the screen could dim in the middle of a video.
  //
  // The player is also the only one that can answer the question correctly:
  // it is driven by the controller's own tick, where this screen sampled
  // `isPlaying` once, 50 ms after a focus, and hoped.

  // ---------------------------------------------------------------------------
  // Focus orchestrator helpers
  // ---------------------------------------------------------------------------

  List<Video> get _currentVideos => _isSearchActive
      ? _searchResults.toList(growable: false)
      : videoController.videoList.toList(growable: false);

  void _captureRoutePlaybackRequest() {
    if (_hasHandledRouteRefresh) return;
    _hasHandledRouteRefresh = true;

    final args = Get.arguments;
    if (args is! Map) return;

    _routeRefreshRequested = args['refresh'] == true;
    final rawVideoId = args['videoId'] ?? args['focusVideoId'];
    if (rawVideoId is String && rawVideoId.trim().isNotEmpty) {
      _routeFocusVideoId = rawVideoId.trim();
      _routeRefreshRequested = true;
    }
  }

  int _indexForVideoId(String? videoId) {
    final targetId = videoId?.trim();
    if (targetId == null || targetId.isEmpty) return 0;

    final videos = _currentVideos;
    final index = videos.indexWhere((video) => video.id == targetId);
    return index >= 0 ? index : 0;
  }

  Future<int> _ensureFocusedVideoVisible(String? videoId) async {
    final targetId = videoId?.trim();
    if (targetId == null || targetId.isEmpty || _isSearchActive) {
      return 0;
    }

    final existingIndex = _indexForVideoId(targetId);
    if (existingIndex > 0 ||
        _currentVideos.any((video) => video.id == targetId)) {
      return existingIndex;
    }

    try {
      final video = await widget.homeFeedRepository.fetchReadyVideoById(
        targetId,
      );
      if (!mounted || video == null) {
        return 0;
      }

      final current = videoController.videoList
          .where((item) => item.id != video.id)
          .toList(growable: false);
      videoController.replaceVideos([video, ...current], selectedIndex: 0);
      return 0;
    } catch (error) {
      AppLogger.debug('[HomeScreen] focused video lookup failed: $error');
      return 0;
    }
  }

  Future<bool> _activateHomeIndex(
    int index, {
    bool alignPageView = false,
  }) async {
    final videos = _currentVideos;
    if (index < 0 || index >= videos.length) {
      return false;
    }

    if (alignPageView) {
      _jumpToPageSilently(index);
    }

    await _onPageChanged(index);
    return true;
  }

  Future<bool> _refreshHomeFeed({
    bool alignPageView = true,
    String? focusVideoId,
  }) async {
    if (_isSearchActive) {
      await _runVideoSearch(_searchQuery);
      return _searchResults.isNotEmpty;
    }

    final refreshed = await videoController.refreshVideosKeepingFeed();
    if (!mounted) return refreshed;

    if (!refreshed || videoController.videoList.isEmpty) {
      return false;
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return false;

    final targetIndex = await _ensureFocusedVideoVisible(focusVideoId);
    if (!mounted) return false;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return false;

    return _activateHomeIndex(targetIndex, alignPageView: alignPageView);
  }

  Future<void> _retryHomeFeed() async {
    final connected = await ConnectivityService().checkInitialConnection();
    if (!mounted) return;

    setState(() => _isConnected = connected);
    if (connected) {
      await _refreshHomeFeed();
    }
  }

  Future<void> _openAddVideo() async {
    await videoManager.pauseAll('home');
    final result = await Get.to(() => const AddVideo());
    if (result == true) {
      await _refreshHomeFeed();
    }
  }

  Future<void> _openPendingLiveVideos() async {
    final inserted = videoController.applyBufferedLiveVideos(moveToTop: true);
    if (!mounted || inserted == 0) return;

    unawaited(HapticFeedback.lightImpact().catchError((_) {}));
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    _jumpToPageSilently(0);

    await _onPageChanged(0);
  }

  void _scheduleHomeFeedActivationAfterEmptyFeed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isSearchActive || videoController.videoList.isEmpty) {
        return;
      }

      final safeIndex = videoController.currentIndex.value
          .clamp(0, videoController.videoList.length - 1)
          .toInt();
      videoController.currentIndex.value = safeIndex;

      _jumpToPageSilently(safeIndex);

      unawaited(_onPageChanged(safeIndex));
    });
  }

  void _jumpToPageSilently(int index) => _pager.jumpToPage(index);

  /// Loads the next feed page as the user nears the end.
  ///
  /// Never during a search: those results are a fixed answer to a question,
  /// not a window onto the feed.
  Future<void> _loadMoreHomeVideos() async {
    if (_isSearchActive) return;
    if (!videoController.hasMore || videoController.isLoading) return;
    await videoController.fetchPaginatedVideos();
  }

  void _notifySearchUi() {
    _searchUiRevision.value++;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _captureRoutePlaybackRequest();

    videoController = FeatureControllerRegistry.ensureVideoController(
      contextKey: 'home',
      enableLiveStream: true,
      enableFeedFetch: true,
      permanent: true,
    );

    _initConnectivityListener();
    _loadInitialVideos();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _captureRoutePlaybackRequest();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _searchUiRevision.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // Pausing on background and re-focusing on resume belong to
  // VideoFeedPager, which observes the lifecycle for every feed. This screen
  // did both as well: the app was paused twice, and on resume the current
  // video was focused twice — once by the pager, once from here.

  // ---------------------------------------------------------------------------
  // Connectivity & initial load
  // ---------------------------------------------------------------------------

  void _initConnectivityListener() {
    _connectivitySubscription = ConnectivityService().connectionStream
        .distinct()
        .listen((connected) async {
          if (!mounted) return;
          setState(() => _isConnected = connected);

          if (connected && videoController.videoList.isEmpty) {
            final ok = await videoController.fetchPaginatedVideos();
            if (ok && mounted && videoController.videoList.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                unawaited(_activateHomeIndex(0, alignPageView: true));
              });
            }
          }
        });
  }

  Future<void> _loadInitialVideos() async {
    final connected = await ConnectivityService().checkInitialConnection();
    if (!mounted) return;

    setState(() => _isConnected = connected);

    if (connected && _routeRefreshRequested) {
      await _refreshHomeFeed(focusVideoId: _routeFocusVideoId);
      return;
    }

    if (connected && videoController.videoList.isEmpty) {
      await videoController.fetchPaginatedVideos();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final videos = videoController.videoList;
      if (videos.isNotEmpty) {
        final targetIndex = await _ensureFocusedVideoVisible(
          _routeFocusVideoId,
        );
        if (!mounted) return;
        await _activateHomeIndex(targetIndex, alignPageView: true);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Global video search
  // ---------------------------------------------------------------------------

  void _onSearchChanged(String value) {
    final query = value.trim();
    _searchDebounce?.cancel();

    if (query.isEmpty) {
      _clearVideoSearch();
      return;
    }

    setState(() {
      _feedIndexBeforeSearch ??= videoController.currentIndex.value;
      _searchQuery = query;
      _isSearchLoading = true;
      _searchError = null;
    });
    _notifySearchUi();

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_runVideoSearch(query));
    });
  }

  void _clearVideoSearch() {
    _searchRequestToken++;
    _searchDebounce?.cancel();
    _searchController.clear();

    setState(() {
      _searchQuery = '';
      _searchResults = const <Video>[];
      _isSearchLoading = false;
      _searchError = null;
    });
    _notifySearchUi();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (videoController.videoList.isEmpty) {
        _feedIndexBeforeSearch = null;
        return;
      }
      final restoreIndex = (_feedIndexBeforeSearch ?? 0)
          .clamp(0, videoController.videoList.length - 1)
          .toInt();
      _feedIndexBeforeSearch = null;
      _jumpToPageSilently(restoreIndex);
      unawaited(_onPageChanged(restoreIndex));
    });
  }

  Future<void> _runVideoSearch(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      _clearVideoSearch();
      return;
    }

    final requestToken = ++_searchRequestToken;
    if (mounted) {
      setState(() {
        _searchQuery = query;
        _isSearchLoading = true;
        _searchError = null;
      });
      _notifySearchUi();
    }

    try {
      await _hydrateSearchUsersIfNeeded();
      final matchesById = <String, Video>{};
      final matchingAuthors = _matchingAuthorsForQuery(query);

      if (matchingAuthors.isNotEmpty) {
        try {
          await _loadVideosForAuthors(
            matchingAuthors.map((user) => user.uid).toSet(),
            query: query,
            matchesById: matchesById,
          );
        } catch (error) {
          AppLogger.debug('Video search author query fallback: $error');
        }
      }

      if (matchesById.isEmpty) {
        await _loadRecentVideosMatchingQuery(query, matchesById: matchesById);
      }

      if (!mounted || requestToken != _searchRequestToken) {
        return;
      }

      setState(() {
        _searchResults = matchesById.values
            .take(_searchResultLimit)
            .toList(growable: false);
        _isSearchLoading = false;
      });
      _notifySearchUi();

      await _activateFirstSearchResult();
    } catch (error) {
      if (!mounted || requestToken != _searchRequestToken) {
        return;
      }

      setState(() {
        _searchResults = const <Video>[];
        _isSearchLoading = false;
        _searchError = VideoUiStrings.videoSearchUnavailable;
      });
      _notifySearchUi();
    }
  }

  Future<void> _hydrateSearchUsersIfNeeded() async {
    final hasWatchedPlayers = userController.userList.any(
      (user) => user.isPlayer,
    );
    if (_searchUsersHydrated || hasWatchedPlayers) {
      return;
    }

    final players = await widget.homeFeedRepository.fetchSearchablePlayers(
      limit: 300,
    );
    for (final user in players) {
      userController.usersCache[user.uid] = user;
    }

    _searchUsersHydrated = true;
  }

  List<AppUser> _matchingAuthorsForQuery(String query) {
    final seen = <String>{};
    final authors = <AppUser>[];

    for (final user in userController.usersCache.values) {
      if (user.uid.trim().isEmpty || !seen.add(user.uid)) {
        continue;
      }
      if (!user.isPlayer) {
        continue;
      }
      if (matchesUserVideoSearch(user, query)) {
        authors.add(user);
      }
    }

    return authors;
  }

  Future<void> _loadVideosForAuthors(
    Set<String> authorIds, {
    required String query,
    required Map<String, Video> matchesById,
  }) async {
    final ids = authorIds.where((id) => id.trim().isNotEmpty).toList();
    if (ids.isEmpty) {
      return;
    }

    for (var start = 0; start < ids.length; start += _searchUidBatchSize) {
      if (matchesById.length >= _searchResultLimit) {
        return;
      }

      final end = (start + _searchUidBatchSize).clamp(0, ids.length).toInt();
      final batch = ids.sublist(start, end);
      final videos = await widget.homeFeedRepository.fetchReadyVideosForAuthors(
        batch,
        limit: _searchResultLimit,
      );

      for (final video in videos) {
        final author = userController.usersCache[video.uid];
        if (!matchesVideoSearch(video, author, query)) {
          continue;
        }
        matchesById[video.id] = video;
        if (matchesById.length >= _searchResultLimit) {
          return;
        }
      }
    }
  }

  Future<void> _loadRecentVideosMatchingQuery(
    String query, {
    required Map<String, Video> matchesById,
  }) async {
    final videos = await widget.homeFeedRepository.fetchRecentReadyVideos(
      limit: _searchRecentScanLimit,
    );

    for (final video in videos) {
      if (matchesById.length >= _searchResultLimit) {
        return;
      }

      final author = userController.usersCache[video.uid];
      if (!matchesVideoSearch(video, author, query)) {
        continue;
      }
      matchesById[video.id] = video;
    }
  }

  Future<void> _activateFirstSearchResult() async {
    await videoManager.pauseAll('home');
    if (_searchResults.isEmpty) {
      return;
    }

    _jumpToPageSilently(0);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _onPageChanged(0);
  }

  Future<void> _focusSearchResult(Video video) async {
    final index = _searchResults.indexWhere((item) => item.id == video.id);
    if (index < 0) {
      return;
    }

    _jumpToPageSilently(index);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _onPageChanged(index);
  }

  Future<void> _openVideoSearchSheet() async {
    if (_isSearchSheetOpen) {
      return;
    }

    await videoManager.pauseAll('home');

    if (!mounted) return;
    setState(() => _isSearchSheetOpen = true);

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.56),
        builder: (sheetContext) {
          return ValueListenableBuilder<int>(
            valueListenable: _searchUiRevision,
            builder: (context, _, _) {
              return _VideoSearchSheet(
                controller: _searchController,
                focusNode: _searchFocusNode,
                query: _searchQuery,
                isLoading: _isSearchLoading,
                error: _searchError,
                results: _searchResults,
                userController: userController,
                onChanged: _onSearchChanged,
                onClear: _clearVideoSearch,
                onResultSelected: (video) {
                  Navigator.of(sheetContext).pop();
                  unawaited(_focusSearchResult(video));
                },
              );
            },
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isSearchSheetOpen = false);
      }
    }

    if (!mounted) return;
  }

  // ---------------------------------------------------------------------------
  // Page change / playback orchestration
  // ---------------------------------------------------------------------------

  /// Moves the feed to [index] and focuses it.
  ///
  /// Kept as the home screen's own entry point — route focus, search restore,
  /// empty-feed activation and the profile round trip all call it — while the
  /// page controller, the orchestrator and the lifecycle belong to
  /// [VideoFeedPager].
  Future<void> _onPageChanged(int index) => _pager.activate(index);

  /// Runs before the pager focuses [index].
  ///
  /// Returning `false` hands the move back: reaching the top of the feed with
  /// live videos waiting means the feed is about to change under us, so
  /// focusing this index would only be undone by the jump that follows.
  Future<bool> _onBeforeIndexChanged(
    int index, {
    required int previousIndex,
  }) async {
    if (_isSearchActive) return true;

    final shouldApplyPendingLiveOnTop = videoController
        .shouldSurfacePendingLiveAt(
          previousIndex: previousIndex,
          index: index,
        );
    if (!shouldApplyPendingLiveOnTop) return true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_openPendingLiveVideos());
    });
    return false;
  }

  /// Runs once the pager has attached [index]'s controller.
  Future<void> _onIndexFocused(int index) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  String _firstRune(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return String.fromCharCode(trimmed.runes.first);
  }

  String _profileInitials(AppUser user) {
    final parts = user.nom
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);

    if (parts.isEmpty) return 'AD';

    if (parts.length == 1) {
      final letters = parts.first.runes
          .take(2)
          .map(String.fromCharCode)
          .join()
          .toUpperCase();
      return letters.isEmpty ? 'AD' : letters;
    }

    final initials = parts.take(2).map(_firstRune).join().toUpperCase();
    return initials.isEmpty ? 'AD' : initials;
  }

  IconData _profileRoleIcon(AppUser user) {
    if (user.isPlayer) return Icons.sports_soccer_rounded;
    if (user.isClub) return Icons.business_rounded;
    if (user.isRecruiter) return Icons.workspace_premium_rounded;
    if (user.isCoach) return Icons.groups_rounded;
    return Icons.person_rounded;
  }

  Widget _buildProfileInitialsSurface(AppUser user) {
    return Container(
      alignment: Alignment.center,
      color: AdColors.surfaceCardAlt,
      child: Text(
        _profileInitials(user),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AdColors.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }

  Widget _buildProfileRoleBadge(AppUser user) {
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AdColors.surface,
        border: Border.all(color: AdColors.brand, width: 1.4),
      ),
      child: Icon(_profileRoleIcon(user), color: AdColors.brand, size: 9.5),
    );
  }

  Widget _buildHomeProfileAvatar(AppUser user) {
    final photoUrl = user.photoProfil.trim();
    final fallback = _buildProfileInitialsSurface(user);

    return Semantics(
      label: VideoUiStrings.profile,
      button: true,
      child: SizedBox.square(
        dimension: 40,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AdColors.brand,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AdColors.surfaceCard,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(1),
                    child: ClipOval(
                      child: photoUrl.isEmpty
                          ? fallback
                          : Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              cacheWidth: 96,
                              cacheHeight: 96,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return fallback;
                                  },
                              errorBuilder: (context, error, stackTrace) {
                                return fallback;
                              },
                            ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: _buildProfileRoleBadge(user),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSearchLauncher() {
    final active = _isSearchActive;
    final label = active ? _searchQuery : VideoUiStrings.videoSearchIdleLabel;
    final countLabel = _isSearchLoading
        ? null
        : active
        ? '${_searchResults.length}'
        : null;

    return Semantics(
      button: true,
      label: VideoUiStrings.videoSearchTitle,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AdRadius.pill),
          onTap: () => unawaited(_openVideoSearchSheet()),
          child: Ink(
            height: 42,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: active ? 0.48 : 0.32),
              borderRadius: BorderRadius.circular(AdRadius.pill),
              border: Border.all(
                color: Colors.white.withValues(alpha: active ? 0.36 : 0.16),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: AdSpacing.sm),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 20,
                ),
                const SizedBox(width: AdSpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.78),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_isSearchLoading)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                else if (countLabel != null)
                  Container(
                    constraints: const BoxConstraints(minWidth: 26),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AdSpacing.xs,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AdColors.brand.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(AdRadius.pill),
                    ),
                    child: Text(
                      countLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AdColors.brand,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                if (active) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _clearVideoSearch,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchState({
    required IconData icon,
    required String title,
    required String message,
    bool showClearAction = true,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AdStatePanel(
          icon: icon,
          title: title,
          message: message,
          action: showClearAction
              ? AdButton(
                  expanded: false,
                  leading: Icons.close_rounded,
                  label: VideoUiStrings.videoSearchClear,
                  onPressed: _clearVideoSearch,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildPendingLiveVideosChip(int pending) {
    final label = VideoUiStrings.pendingVideosLabel(pending);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(
          top: kToolbarHeight + 10,
          left: AdSpacing.md,
          right: AdSpacing.md,
        ),
        child: Semantics(
          button: true,
          label: VideoUiStrings.pendingVideosSemantic(pending),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AdRadius.pill),
              onTap: () => unawaited(_openPendingLiveVideos()),
              child: Ink(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.76),
                  borderRadius: BorderRadius.circular(AdRadius.pill),
                  border: Border.all(
                    color: AdColors.brand.withValues(alpha: 0.44),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AdSpacing.sm,
                  vertical: 9,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width - 48,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AdColors.brand,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.fiber_new_rounded,
                          color: AdColors.brandOn,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        VideoUiStrings.pendingVideosAction,
                        style: const TextStyle(
                          color: AdColors.brand,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdColors.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        titleSpacing: 12,
        centerTitle: false,
        title: _buildVideoSearchLauncher(),
        actions: [
          Obx(() {
            final user = userController.user;
            if (user == null) {
              return const Padding(
                padding: EdgeInsets.all(8.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(right: AdSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (user.role == 'joueur') ...[
                    Tooltip(
                      message: VideoUiStrings.addVideoSemantic,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AdRadius.pill),
                        onTap: () => unawaited(_openAddVideo()),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AdColors.brand,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: AdColors.brandOn,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AdSpacing.xs),
                  ],
                  GestureDetector(
                    onTap: () async {
                      await videoManager.pauseAll('home');
                      await Get.to(
                        () => ProfileScreen(uid: user.uid, isReadOnly: false),
                      );
                      videoController.currentIndex.refresh();
                      await _onPageChanged(videoController.currentIndex.value);
                    },
                    child: Tooltip(
                      message: VideoUiStrings.profile,
                      child: Hero(
                        tag: 'profileAvatar',
                        child: _buildHomeProfileAvatar(user),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
      body: !_isConnected
          ? _buildNoInternet()
          : Obx(() {
              final feedVideos = videoController.videoList;
              final videos = _currentVideos;
              final feedBecameAvailable =
                  !_isSearchActive &&
                  _wasHomeFeedEmpty &&
                  feedVideos.isNotEmpty;
              if (!_isSearchActive) {
                _wasHomeFeedEmpty = feedVideos.isEmpty;
              }

              if (_isSearchActive && videos.isEmpty) {
                if (_isSearchLoading) {
                  return _buildSearchState(
                    icon: Icons.search_rounded,
                    title: VideoUiStrings.videoSearchLoadingTitle,
                    message: VideoUiStrings.videoSearchLoadingMessage,
                    showClearAction: false,
                  );
                }

                return _buildSearchState(
                  icon: Icons.search_off_rounded,
                  title: VideoUiStrings.videoSearchEmptyTitle,
                  message:
                      _searchError ?? VideoUiStrings.videoSearchEmptyMessage,
                );
              }

              if (!_isSearchActive && feedVideos.isEmpty) {
                final user = userController.user;
                return _buildEmptyFeed(userRole: user?.role);
              }

              if (feedBecameAvailable) {
                _scheduleHomeFeedActivationAfterEmptyFeed();
              }

              return VideoFeedPager(
                pagerController: _pager,
                contextKey: 'home',
                videos: videos,
                videoController: videoController,
                userController: userController,
                followController: followController,
                onBeforeIndexChanged: _onBeforeIndexChanged,
                onIndexFocused: _onIndexFocused,
                onRequestMore: _loadMoreHomeVideos,
                onRefreshRequested: _refreshHomeFeed,
                // L'auteur supprime depuis son profil, pas depuis le feed
                // public.
                showDeleteAction: false,
              );
            }),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerTop,
      floatingActionButton: Obx(() {
        final pending = videoController.pendingLiveCount.value;
        if (pending <= 0 ||
            !_isConnected ||
            _isSearchActive ||
            _isSearchSheetOpen) {
          return const SizedBox.shrink();
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey<int>(pending),
            child: _buildPendingLiveVideosChip(pending),
          ),
        );
      }),
    );
  }

  Widget _buildEmptyFeed({required String? userRole}) {
    final canPublish = userRole == 'joueur';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AdStatePanel(
          icon: Icons.sports_soccer_rounded,
          title: VideoUiStrings.emptyHomeVideoFeedTitle,
          message: canPublish
              ? VideoUiStrings.emptyHomeVideoFeedPlayerMessage
              : VideoUiStrings.emptyHomeVideoFeedDefaultMessage,
          action: AdButton(
            expanded: false,
            leading: canPublish ? Icons.add_rounded : Icons.refresh_rounded,
            label: canPublish
                ? VideoUiStrings.addVideoSemantic
                : VideoUiStrings.refresh,
            onPressed: canPublish
                ? () => unawaited(_openAddVideo())
                : () => unawaited(_retryHomeFeed()),
          ),
        ),
      ),
    );
  }

  Widget _buildNoInternet() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AdStatePanel(
          icon: Icons.wifi_off_rounded,
          title: VideoUiStrings.noInternetTitle,
          message: VideoUiStrings.noInternetMessage,
          action: AdButton(
            expanded: false,
            kind: AdButtonKind.outline,
            leading: Icons.refresh_rounded,
            label: VideoUiStrings.retry,
            onPressed: () => unawaited(_retryHomeFeed()),
          ),
        ),
      ),
    );
  }
}
