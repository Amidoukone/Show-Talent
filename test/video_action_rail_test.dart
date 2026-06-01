import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:adfoot/widgets/video_action_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser buildUser({
  required String uid,
  required String role,
  String name = 'Test User',
  List<String> followings = const <String>[],
}) {
  return AppUser(
    uid: uid,
    nom: name,
    email: '$uid@example.com',
    role: role,
    photoProfil: '',
    estActif: true,
    emailVerified: true,
    followers: 0,
    followings: followings.length,
    dateInscription: DateTime(2026, 1, 1),
    dernierLogin: DateTime(2026, 1, 1),
    followersList: const <String>[],
    followingsList: List<String>.from(followings),
  );
}

Video buildVideo({
  String uid = 'author',
  List<String> likes = const <String>[],
  int shareCount = 0,
}) {
  return Video(
    id: 'video-1',
    videoUrl: 'https://example.com/video.mp4',
    thumbnailUrl: '',
    description: 'Highlight',
    caption: 'Caption',
    profilePhoto: '',
    uid: uid,
    likes: List<String>.from(likes),
    shareCount: shareCount,
  );
}

Widget host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox(
        width: 390,
        height: 760,
        child: Stack(children: [child]),
      ),
    ),
  );
}

void main() {
  testWidgets('action rail exposes guarded modern action states',
      (tester) async {
    var likes = 0;
    var shares = 0;
    var openedProfile = 0;

    await tester.pumpWidget(
      host(
        VideoActionRail(
          video: buildVideo(likes: const ['viewer'], shareCount: 1250),
          currentUser: buildUser(
            uid: 'viewer',
            role: 'joueur',
            followings: const ['author'],
          ),
          publisher: buildUser(uid: 'author', role: 'joueur'),
          bottomOffset: 24,
          safeRightInset: 0,
          actionSpacing: 16,
          sectionSpacing: 20,
          showDeleteAction: true,
          showProfileAction: true,
          isLikeLoading: false,
          isShareLoading: false,
          isReportLoading: false,
          isDeleteLoading: false,
          isAddVideoLoading: false,
          isFollowLoading: false,
          onDelete: null,
          onLike: () async => likes++,
          onShare: () async => shares++,
          onReport: null,
          onAddVideo: null,
          onOpenProfile: () async => openedProfile++,
          onFollowPublisher: null,
        ),
      ),
    );

    expect(find.byTooltip(VideoUiStrings.unlikeVideo), findsOneWidget);
    expect(find.byTooltip(VideoUiStrings.shareVideo), findsOneWidget);
    expect(find.byTooltip(VideoUiStrings.moreVideoActionsSemantic),
        findsOneWidget);
    expect(find.byTooltip(VideoUiStrings.followingProfile), findsWidgets);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('1.3k'), findsOneWidget);

    await tester.tap(find.byTooltip(VideoUiStrings.unlikeVideo));
    await tester.tap(find.byTooltip(VideoUiStrings.shareVideo));
    await tester.tap(find.byTooltip(VideoUiStrings.followingProfile).first);
    await tester.pump();

    expect(likes, 1);
    expect(shares, 1);
    expect(openedProfile, 1);

    await tester.tap(find.byTooltip(VideoUiStrings.moreVideoActionsSemantic));
    await tester.pumpAndSettle();

    expect(find.text(VideoUiStrings.addVideoSemantic), findsOneWidget);
    expect(find.text(VideoUiStrings.reportVideoSemantic), findsOneWidget);
  });

  testWidgets('follow badge calls the follow action when available',
      (tester) async {
    var follows = 0;

    await tester.pumpWidget(
      host(
        VideoActionRail(
          video: buildVideo(),
          currentUser: buildUser(uid: 'viewer', role: 'fan'),
          publisher: buildUser(uid: 'author', role: 'joueur'),
          bottomOffset: 24,
          safeRightInset: 0,
          actionSpacing: 16,
          sectionSpacing: 20,
          showDeleteAction: true,
          showProfileAction: true,
          isLikeLoading: false,
          isShareLoading: false,
          isReportLoading: false,
          isDeleteLoading: false,
          isAddVideoLoading: false,
          isFollowLoading: false,
          onDelete: null,
          onLike: null,
          onShare: null,
          onReport: null,
          onAddVideo: null,
          onOpenProfile: null,
          onFollowPublisher: () async => follows++,
        ),
      ),
    );

    expect(find.byTooltip(VideoUiStrings.followProfile), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);

    await tester.tap(find.byTooltip(VideoUiStrings.followProfile));
    await tester.pump();

    expect(follows, 1);
  });
}
