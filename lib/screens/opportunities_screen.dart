import 'package:flutter/material.dart';

import 'package:adfoot/screens/event_list_screen.dart';
import 'package:adfoot/screens/offre_screen.dart';
import 'package:adfoot/screens/talent_search_screen.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';

/// Offres and Événements, under the one thing they both are.
///
/// They were two of five entries in the navigation bar, and on
/// adfoot-production they held one offer and two events between them: two
/// destinations spending forty percent of the bar on three documents. They
/// are also the same thing seen twice — an opportunity published by a club, a
/// recruiter or an agent, for a player to answer. One destination, two tabs,
/// and the slot that frees pays for the publish action the bar never had.
///
/// Neither screen was rewritten. Each keeps its own content, its own
/// controller and its own filters; this only owns the chrome they used to
/// draw for themselves.
class OpportunitiesScreen extends StatefulWidget {
  const OpportunitiesScreen({
    super.key,
    this.initialTab = 0,
    this.tabRequestSerial = 0,
    this.showTalentSearch = false,
  });

  /// Ajoute l'onglet « Joueurs », reserve a ceux qui recrutent.
  ///
  /// Un joueur n'a rien a faire d'une recherche de joueurs, et l'onglet lui
  /// couterait un tiers de la largeur de la barre pour rien. Le role est passe
  /// par l'appelant plutot que relu ici : cet ecran n'a jamais eu besoin de
  /// connaitre l'utilisateur, et lui donner un controleur pour un booleen
  /// serait payer cher une information que `MainScreen` tient deja.
  final bool showTalentSearch;

  /// Which tab a caller wants open.
  final int initialTab;

  /// Bumped by the caller each time it asks, even for the same tab.
  ///
  /// A notification for an event, tapped twice, has to land on the events tab
  /// both times — and the host rebuilds this screen rather than recreating
  /// it, so `initialTab` alone would be read once in `initState` and never
  /// again.
  final int tabRequestSerial;

  @override
  State<OpportunitiesScreen> createState() => _OpportunitiesScreenState();
}

class _OpportunitiesScreenState extends State<OpportunitiesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Which tabs have ever been looked at.
  ///
  /// `MainScreen` builds one screen at a time — `_screens[_selectedIndex]`,
  /// not an `IndexedStack` — so Offres and Événements have never been alive
  /// together, and a plain `TabBarView` would change that: two controllers,
  /// two sets of Firestore listeners, for a tab nobody has opened.
  ///
  /// A tab is built the first time it is reached and kept afterwards, so
  /// coming back to it costs nothing and never opened costs nothing either.
  final Set<int> _visitedTabs = <int>{0};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: _safeTab(widget.initialTab),
    );
    _visitedTabs.add(_tabController.index);
    _tabController.addListener(_markCurrentTabVisited);
  }

  @override
  void didUpdateWidget(covariant OpportunitiesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabRequestSerial == widget.tabRequestSerial) return;

    final target = _safeTab(widget.initialTab);
    if (_tabController.index == target) return;
    _tabController.animateTo(target);
  }

  /// Deux onglets, trois pour qui recrute.
  ///
  /// « Joueurs » est ajoute **en dernier** : les notifications ouvrent cet
  /// ecran par index (0 = Offres, 1 = Evenements), et inserer un onglet avant
  /// eux ferait atterrir une notification d'evenement sur une autre page.
  int get _tabCount => widget.showTalentSearch ? 3 : 2;

  int _safeTab(int value) => value.clamp(0, _tabCount - 1).toInt();

  @override
  void dispose() {
    _tabController.removeListener(_markCurrentTabVisited);
    _tabController.dispose();
    super.dispose();
  }

  void _markCurrentTabVisited() {
    final index = _tabController.index;
    if (_visitedTabs.contains(index)) return;
    setState(() => _visitedTabs.add(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdColors.surface,
      appBar: AdAppBar(
        title: 'Carrière',
        subtitle: widget.showTalentSearch
            ? 'Offres, événements et joueurs'
            : 'Offres et événements',
        showBottomDivider: false,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AdColors.brand,
          unselectedLabelColor: AdColors.onSurfaceMuted,
          indicatorColor: AdColors.brand,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          tabs: [
            const Tab(text: 'Offres'),
            const Tab(text: 'Événements'),
            if (widget.showTalentSearch) const Tab(text: 'Joueurs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _tabAt(0, const OffreScreen(showAppBar: false)),
          _tabAt(1, const EventListScreen(showAppBar: false)),
          if (widget.showTalentSearch)
            _tabAt(2, const TalentSearchScreen()),
        ],
      ),
    );
  }

  Widget _tabAt(int index, Widget child) {
    if (!_visitedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    return child;
  }
}
