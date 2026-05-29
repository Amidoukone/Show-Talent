import 'dart:async';
import 'dart:ui';

import 'package:adfoot/config/feature_controller_registry.dart';
import 'package:adfoot/screens/add_video.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/connectivity_controller.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/utils/video_search_matcher.dart';

import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/videos/domain/video_focus_orchestrator.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:adfoot/widgets/smart_video_player.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:adfoot/widgets/video_page_scroll_physics.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final VideoController videoController;
  final UserController userController = Get.find<UserController>();
  final FollowController followController = Get.find<FollowController>();
  final PageController _pageController = PageController();
  final TextEditingController _searchController = TextEditingController();
  final VideoManager videoManager = VideoManager();
  late final VideoFocusOrchestrator _focusOrchestrator;

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
  bool _wakelockOn = false;
  bool _hasHandledRouteRefresh = false;
  bool _routeRefreshRequested = false;
  String? _routeFocusVideoId;
  int? _silencedPageChangeIndex;
  int _searchRequestToken = 0;
  int? _feedIndexBeforeSearch;

  bool get _isSearchActive => _searchQuery.trim().isNotEmpty;

  // ---------------------------------------------------------------------------
  // Wakelock helpers
  // ---------------------------------------------------------------------------

  Future<void> _setWakelock(bool enable) async {
    if (_wakelockOn == enable) return;
    _wakelockOn = enable;
    try {
      enable ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (e) {
      debugPrint('⚠️ Wakelock error: $e');
    }
  }

  Future<void> _updateWakelockForCurrent() async {
    final idx = videoController.currentIndex.value;
    final videos = _currentVideos;
    if (idx < 0 || idx >= videos.length) {
      await _setWakelock(false);
      return;
    }

    final url = videos[idx].videoUrl;
    final player = videoManager.getController('home', url);
    final ctrl = player?.controller;

    final shouldKeepAwake = ctrl != null &&
        ctrl.value.isInitialized &&
        ctrl.value.isPlaying &&
        !ctrl.value.isBuffering;

    await _setWakelock(shouldKeepAwake);
  }

  // ---------------------------------------------------------------------------
  // Focus orchestrator helpers
  // ---------------------------------------------------------------------------

  List<Video> get _currentVideos => _isSearchActive
      ? _searchResults.toList(growable: false)
      : videoController.videoList.toList(growable: false);

  void _refreshFocusVideos() {
    _focusOrchestrator.updateVideos(_currentVideos);
  }

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
      final doc = await FirebaseFirestore.instance
          .collection('videos')
          .doc(targetId)
          .get();
      if (!mounted || !doc.exists) return 0;

      final video = Video.fromDoc(doc);
      if (video.status != 'ready' || video.videoUrl.isEmpty) {
        return 0;
      }

      final current = videoController.videoList
          .where((item) => item.id != video.id)
          .toList(growable: false);
      videoController.replaceVideos([video, ...current], selectedIndex: 0);
      _refreshFocusVideos();
      return 0;
    } catch (error) {
      debugPrint('[HomeScreen] focused video lookup failed: $error');
      return 0;
    }
  }

  Future<bool> _activateHomeIndex(
    int index, {
    bool alignPageView = false,
  }) async {
    final videos = _currentVideos;
    if (index < 0 || index >= videos.length) {
      await _setWakelock(false);
      return false;
    }

    if (alignPageView && _pageController.hasClients) {
      final currentPage = (_pageController.page ?? 0).round();
      if (currentPage != index) {
        _jumpToPageSilently(index);
      }
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
      await _setWakelock(false);
      return false;
    }

    _refreshFocusVideos();
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
    await _setWakelock(false);
    final result = await Get.to(() => const AddVideo());
    if (result == true) {
      await _refreshHomeFeed();
    }
  }

  Future<void> _openPendingLiveVideos() async {
    final inserted = videoController.applyBufferedLiveVideos(moveToTop: true);
    if (!mounted || inserted == 0) return;

    _refreshFocusVideos();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    if (_pageController.hasClients) {
      _jumpToPageSilently(0);
    }

    await _onPageChanged(0);
  }

  void _jumpToPageSilently(int index) {
    if (!_pageController.hasClients) {
      return;
    }
    final currentPage = (_pageController.page ?? 0).round();
    if (currentPage == index) {
      _silencedPageChangeIndex = null;
      return;
    }
    _silencedPageChangeIndex = index;
    _pageController.jumpToPage(index);
  }

  void _triggerPageChangeHaptic() {
    unawaited(HapticFeedback.selectionClick().catchError((_) {}));
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _captureRoutePlaybackRequest();

    videoController = FeatureControllerRegistry.ensureVideoController(
      contextKey: 'home',
      enableLiveStream: true,
      enableFeedFetch: true,
      permanent: true,
    );

    _focusOrchestrator = VideoFocusOrchestrator(
      contextKey: 'home',
      videoManager: videoManager,
      videos: _currentVideos,
      disposeWindow: 25,
      onRequestMore: () async {
        if (_isSearchActive) {
          return;
        }
        if (videoController.hasMore && !videoController.isLoading) {
          final fetched = await videoController.fetchPaginatedVideos();
          if (fetched) {
            _refreshFocusVideos();
          }
        }
      },
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
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _searchController.dispose();
    _pageController.dispose();
    _connectivitySubscription?.cancel();
    unawaited(_setWakelock(false));
    unawaited(_focusOrchestrator.onDispose());
    super.dispose();
  }

  @override
  void deactivate() {
    videoManager.pauseAll('home');
    unawaited(_setWakelock(false));
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      videoManager.pauseAll('home');
      unawaited(_setWakelock(false));
    } else if (state == AppLifecycleState.resumed) {
      final idx = videoController.currentIndex.value;
      if (idx >= 0 && idx < _currentVideos.length) {
        unawaited(_onPageChanged(idx));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_updateWakelockForCurrent());
        });
      }
    }
    super.didChangeAppLifecycleState(state);
  }

  // ---------------------------------------------------------------------------
  // Connectivity & initial load
  // ---------------------------------------------------------------------------

  void _initConnectivityListener() {
    _connectivitySubscription = ConnectivityService()
        .connectionStream
        .distinct()
        .listen((connected) async {
      if (!mounted) return;
      setState(() => _isConnected = connected);

      if (connected && videoController.videoList.isEmpty) {
        final ok = await videoController.fetchPaginatedVideos();
        if (ok && mounted && videoController.videoList.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _refreshFocusVideos();
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
      _refreshFocusVideos();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final videos = videoController.videoList;
      if (videos.isNotEmpty) {
        _refreshFocusVideos();
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (videoController.videoList.isEmpty) {
        _feedIndexBeforeSearch = null;
        unawaited(_setWakelock(false));
        return;
      }
      final restoreIndex = (_feedIndexBeforeSearch ?? 0)
          .clamp(0, videoController.videoList.length - 1)
          .toInt();
      _feedIndexBeforeSearch = null;
      _jumpToPageSilently(restoreIndex);
      _refreshFocusVideos();
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
          debugPrint('Video search author query fallback: $error');
        }
      }

      if (matchesById.isEmpty) {
        await _loadRecentVideosMatchingQuery(
          query,
          matchesById: matchesById,
        );
      }

      if (!mounted || requestToken != _searchRequestToken) {
        return;
      }

      setState(() {
        _searchResults =
            matchesById.values.take(_searchResultLimit).toList(growable: false);
        _isSearchLoading = false;
      });

      await _activateFirstSearchResult();
    } catch (error) {
      if (!mounted || requestToken != _searchRequestToken) {
        return;
      }

      setState(() {
        _searchResults = const <Video>[];
        _isSearchLoading = false;
        _searchError =
            'Recherche indisponible pour le moment. Réessayez dans un instant.';
      });
      await _setWakelock(false);
    }
  }

  Future<void> _hydrateSearchUsersIfNeeded() async {
    final hasWatchedPlayers =
        userController.userList.any((user) => user.isPlayer);
    if (_searchUsersHydrated || hasWatchedPlayers) {
      return;
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'joueur')
        .limit(300)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final user = AppUser.fromMap({
        ...data,
        'uid': data['uid'] ?? doc.id,
      });
      if (user.uid.trim().isNotEmpty) {
        userController.usersCache[user.uid] = user;
      }
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
      final snapshot = await FirebaseFirestore.instance
          .collection('videos')
          .where('status', isEqualTo: 'ready')
          .where('uid', whereIn: batch)
          .limit(_searchResultLimit)
          .get();

      for (final doc in snapshot.docs) {
        final video = Video.fromDoc(doc);
        final author = userController.usersCache[video.uid];
        if (video.videoUrl.isEmpty ||
            !matchesVideoSearch(video, author, query)) {
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
    final snapshot = await FirebaseFirestore.instance
        .collection('videos')
        .where('status', isEqualTo: 'ready')
        .orderBy('updatedAt', descending: true)
        .limit(_searchRecentScanLimit)
        .get();

    for (final doc in snapshot.docs) {
      if (matchesById.length >= _searchResultLimit) {
        return;
      }

      final video = Video.fromDoc(doc);
      final author = userController.usersCache[video.uid];
      if (video.videoUrl.isEmpty || !matchesVideoSearch(video, author, query)) {
        continue;
      }
      matchesById[video.id] = video;
    }
  }

  Future<void> _activateFirstSearchResult() async {
    await videoManager.pauseAll('home');
    if (_searchResults.isEmpty) {
      await _setWakelock(false);
      return;
    }

    _jumpToPageSilently(0);
    _refreshFocusVideos();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _onPageChanged(0);
  }

  // ---------------------------------------------------------------------------
  // Page change / playback orchestration
  // ---------------------------------------------------------------------------

  Future<void> _onPageChanged(int index) async {
    final videos = _currentVideos;
    if (index < 0 || index >= videos.length) return;

    if (_isSearchActive) {
      videoController.currentIndex.value = index;
    } else {
      final shouldApplyPendingLiveOnTop =
          videoController.updateCurrentIndex(index);
      if (shouldApplyPendingLiveOnTop) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_openPendingLiveVideos());
        });
        return;
      }

      videoController.prefetchThumbnailsAroundIndex(index);
    }

    _refreshFocusVideos();
    await _focusOrchestrator.onIndexChanged(index);

    await Future.delayed(const Duration(milliseconds: 50));
    await _updateWakelockForCurrent();
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AdColors.surfaceCardAlt,
            AdColors.surfaceCard,
          ],
        ),
      ),
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
        border: Border.all(
          color: AdColors.brand,
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        _profileRoleIcon(user),
        color: AdColors.brand,
        size: 9.5,
      ),
    );
  }

  Widget _buildHomeProfileAvatar(AppUser user) {
    final photoUrl = user.photoProfil.trim();
    final fallback = _buildProfileInitialsSurface(user);

    return Semantics(
      label: 'Profil',
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
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AdColors.brand,
                      AdColors.info,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AdColors.brand.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
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

  Widget _buildVideoSearchField() {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Rechercher attaquant, défenseur...',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: Colors.white.withValues(alpha: 0.82),
            size: 20,
          ),
          suffixIcon: _isSearchLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : (_isSearchActive
                  ? IconButton(
                      tooltip: 'Effacer la recherche',
                      onPressed: _clearVideoSearch,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    )
                  : null),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.34),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.72),
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
                  label: 'Effacer',
                  onPressed: _clearVideoSearch,
                )
              : null,
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
        title: _buildVideoSearchField(),
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
              padding: const EdgeInsets.only(right: 8.0),
              child: GestureDetector(
                onTap: () async {
                  await videoManager.pauseAll('home');
                  await _setWakelock(false);
                  await Get.to(
                    () => ProfileScreen(uid: user.uid, isReadOnly: false),
                  );
                  videoController.currentIndex.refresh();
                  _refreshFocusVideos();
                  await _onPageChanged(videoController.currentIndex.value);
                  await _updateWakelockForCurrent();
                },
                child: Tooltip(
                  message: 'Profil',
                  child: Hero(
                    tag: 'profileAvatar',
                    child: _buildHomeProfileAvatar(user),
                  ),
                ),
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

              if (_isSearchActive && videos.isEmpty) {
                if (_isSearchLoading) {
                  return _buildSearchState(
                    icon: Icons.search_rounded,
                    title: 'Recherche en cours',
                    message: 'Nous cherchons les vidéos correspondantes.',
                    showClearAction: false,
                  );
                }

                return _buildSearchState(
                  icon: Icons.search_off_rounded,
                  title: 'Aucune vidéo trouvée',
                  message: _searchError ??
                      'Essayez avec attaquant, défenseur, milieu, gardien ou un autre poste.',
                );
              }

              if (!_isSearchActive && feedVideos.isEmpty) {
                final user = userController.user;
                return _buildEmptyFeed(userRole: user?.role);
              }

              return PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: videos.length,
                physics: const VideoPageScrollPhysics(),
                dragStartBehavior: DragStartBehavior.down,
                allowImplicitScrolling: false,
                onPageChanged: (i) {
                  if (_silencedPageChangeIndex == i) {
                    _silencedPageChangeIndex = null;
                    return;
                  }
                  if (i != videoController.currentIndex.value) {
                    _triggerPageChangeHaptic();
                  }
                  unawaited(_onPageChanged(i));
                },
                itemBuilder: (context, index) {
                  final video = videos[index];
                  final player =
                      videoManager.getController('home', video.videoUrl);

                  return SmartVideoPlayer(
                    key: ValueKey(video.id),
                    player: player,
                    videoController: videoController,
                    userController: userController,
                    followController: followController,
                    contextKey: 'home',
                    videoUrl: video.videoUrl,
                    video: video,
                    currentIndex: index,
                    videoList: videos,
                    enableTapToPlay: true,
                    autoPlay: true,
                    showControls: true,
                    showProgressBar: true,
                    showDeleteAction: false,
                    onRefreshRequested: _refreshHomeFeed,
                  );
                },
              );
            }),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerTop,
      floatingActionButton: Obx(() {
        final pending = videoController.pendingLiveCount.value;
        if (pending <= 0 || !_isConnected || _isSearchActive) {
          return const SizedBox.shrink();
        }

        final label =
            pending > 1 ? '$pending nouvelles vidéos' : '1 nouvelle vidéo';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => unawaited(_openPendingLiveVideos()),
                child: Ink(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.fiber_new_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
          icon: Icons.play_circle_outline_rounded,
          title: 'Aucune vidéo disponible',
          message: canPublish
              ? 'Publiez votre première vidéo pour apparaître dans le feed.'
              : 'Revenez plus tard ou actualisez le feed.',
          action: AdButton(
            expanded: false,
            leading: canPublish ? Icons.add_rounded : Icons.refresh_rounded,
            label: canPublish ? 'Publier une vidéo' : 'Actualiser',
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
          title: 'Pas de connexion Internet',
          message:
              'Vérifiez votre réseau, puis relancez le chargement du feed.',
          action: AdButton(
            expanded: false,
            kind: AdButtonKind.outline,
            leading: Icons.refresh_rounded,
            label: 'Réessayer',
            onPressed: () => unawaited(_retryHomeFeed()),
          ),
        ),
      ),
    );
  }
}
