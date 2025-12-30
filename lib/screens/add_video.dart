// lib/screens/add_video.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'package:adfoot/controller/upload_video_controller.dart';
import 'upload_form.dart';
import 'package:adfoot/theme/ad_colors.dart';

/// 🎨 Couleurs de marque centralisées (évite les doublons + warnings)
const Color kBrand = Color(0xFF2ED573); // vert lumineux (action)
const Color kBrandDark = Color(0xFF26C165); // variante plus sombre

class AddVideo extends StatefulWidget {
  const AddVideo({super.key});

  @override
  State<AddVideo> createState() => _AddVideoState();
}

class _AddVideoState extends State<AddVideo> {
  final UploadVideoController uploadVideoController =
      Get.put(UploadVideoController(), permanent: false);

  final ImagePicker _picker = ImagePicker();
  final RxBool isLoading = false.obs;

  Future<void> _pickVideoFromGallery() async {
    try {
      isLoading.value = true;

      // Galerie uniquement (caméra désactivée)
      final pickedFile = await _picker.pickVideo(source: ImageSource.gallery);

      isLoading.value = false;

      if (pickedFile == null) {
        Get.snackbar(
          'Info',
          'Aucune vidéo sélectionnée',
          backgroundColor: Colors.blueGrey.shade700,
          colorText: Colors.white,
        );
        return;
      }

      final file = File(pickedFile.path);
      // Navigation vers le formulaire d’upload
      Get.to(() => UploadForm(videoFile: file, videoPath: pickedFile.path));
    } on PlatformException catch (e) {
      isLoading.value = false;
      // Gestion permission/refus galerie
      Get.snackbar(
        'Autorisation requise',
        "Veuillez autoriser l'accès à la galerie pour sélectionner une vidéo.\n($e)",
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      isLoading.value = false;
      Get.snackbar(
        'Erreur',
        'Échec lors de la sélection : $e',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      // ❌ On n’étend plus derrière l’AppBar pour garantir lisibilité
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        title: const Text('Ajouter une vidéo'),
        backgroundColor: cs.surface, // ✅ fond sombre cohérent
        foregroundColor: cs.onSurface, // ✅ icônes + texte lisibles
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light, // ✅ icônes de statut en clair
          statusBarBrightness: Brightness.dark,      // iOS
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
            // Dégradé sombre et immersif
            gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AdColors.surface,
            AdColors.surfaceAlt,
            AdColors.surfaceCard,
          ],
        )),
        child: SafeArea(
          child: Obx(() {
            final uploading = uploadVideoController.isUploading.value;
            final optimizing = uploadVideoController.isOptimizing.value;
            final loading = isLoading.value;

            // Contenu principal
            final content = _BodyCard(
              onPick: _pickVideoFromGallery,
            );

            // Superpose un overlay “verre dépoli” quand on charge / upload / optimise
            final showOverlay = loading || uploading || optimizing;

            return Stack(
              children: [
                // Header décoratif
                const _Header(),
                // Contenu avec animations douces
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: media.size.height * 0.18,
                      left: 20,
                      right: 20,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: content,
                    ),
                  ),
                ),

                if (showOverlay)
                  _ProgressOverlay(controller: uploadVideoController, waiting: loading),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// En-tête décoratif avec gradient et icône
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Container(
      height: media.size.height * 0.26,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kBrand, kBrandDark], // ✅ cohérent avec la charte
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(28),
        ),
      ),
      child: const Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: _Bubble(size: 110, opacity: .08),
          ),
          Positioned(
            left: -40,
            bottom: -40,
            child: _Bubble(size: 160, opacity: .06),
          ),
          Align(
            alignment: Alignment.center,
            child: Icon(
              Icons.video_collection_rounded,
              color: Colors.white,
              size: 64,
            ),
          ),
        ],
      ),
    );
  }
}

/// Petite bulle décorative
class _Bubble extends StatelessWidget {
  final double size;
  final double opacity;
  const _Bubble({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Carte principale avec bouton “Choisir depuis la galerie”
class _BodyCard extends StatelessWidget {
  final VoidCallback onPick;

  const _BodyCard({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 10,
      shadowColor: kBrand.withValues(alpha: .15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Illustration cercle + icône
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: kBrand.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.video_library_rounded, size: 42, color: kBrand),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sélectionnez une vidéo depuis votre galerie',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    letterSpacing: .2,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Durée maximale 60s • Qualité conseillée 480×360+',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: AdColors.onSurfaceMuted,
              ),
            ),
            const SizedBox(height: 22),

            // Bouton principal
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.photo_library_rounded, color: Colors.white),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Choisir depuis la galerie',
                    style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrand,
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Tips + puces
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _TipChip(icon: Icons.timer_rounded, label: '≤ 60 secondes'),
                _TipChip(icon: Icons.hd_rounded, label: '≥ 480×360'),
                _TipChip(icon: Icons.data_saver_on_rounded, label: 'Compression auto'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TipChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Chip(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelPadding: const EdgeInsets.only(right: 8),
      // Correction: ne PAS mettre `const` ici car `icon` est une variable
      avatar: Icon(icon, size: 18, color: cs.primary),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: cs.primary,
        ),
      ),
      backgroundColor: cs.primary.withValues(alpha: .12),
    );
  }
}

/// Overlay de progression en “verre dépoli”
class _ProgressOverlay extends StatelessWidget {
  final UploadVideoController controller;
  final bool waiting; // état "chargement" avant d'ouvrir la galerie

  const _ProgressOverlay({required this.controller, required this.waiting});

  @override
  Widget build(BuildContext context) {
    final uploading = controller.isUploading.value;
    final optimizing = controller.isOptimizing.value;
    final progress = controller.uploadProgress.value;
    final hasValue = progress > 0 && progress <= 1;

    String title;
    String subtitle = '';
    Widget progressWidget;

    if (waiting) {
      title = 'Chargement…';
      progressWidget = const CircularProgressIndicator(strokeWidth: 3, color: Colors.white);
    } else if (optimizing) {
      title = 'Optimisation en cours…';
      progressWidget = const CircularProgressIndicator(strokeWidth: 3, color: Colors.white);
    } else if (uploading) {
      title = 'Téléversement en cours';
      subtitle = '${(progress * 100).toInt()}%';
      progressWidget = CircularProgressIndicator(
        strokeWidth: 3,
        color: Colors.white,
        value: hasValue ? progress : null,
      );
    } else {
      title = 'Veuillez patienter…';
      progressWidget = const CircularProgressIndicator(strokeWidth: 3, color: Colors.white);
    }

    return PositionedFill(
      child: Container(
        alignment: Alignment.center,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              width: 320,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .55), 
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: .08)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  progressWidget,
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .2,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .9), 
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                  if (uploading && hasValue) ...[
                    const SizedBox(height: 14),
                    LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 6,
                      color: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: .25),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Petit helper pour éviter le boilerplate Positioned.fill
class PositionedFill extends StatelessWidget {
  final Widget child;
  const PositionedFill({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      left: 0, right: 0, top: 0, bottom: 0,
      child: SizedBox.expand(child: null),
    );
  }
}
