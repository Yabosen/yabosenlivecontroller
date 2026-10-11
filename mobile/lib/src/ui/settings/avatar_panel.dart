import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../api.dart';
import '../../settings.dart';
import '../../status_controller.dart';
import '../theme.dart';
import '../widgets.dart';

/// Picks an image from the gallery and uploads it as the site avatar.
class AvatarPanel extends StatefulWidget {
  const AvatarPanel({
    super.key,
    required this.api,
    required this.apiKey,
    required this.statusController,
  });

  final YabosenApi api;
  final ApiKeyController apiKey;
  final StatusController statusController;

  @override
  State<AvatarPanel> createState() => _AvatarPanelState();
}

class _AvatarPanelState extends State<AvatarPanel> {
  final _picker = ImagePicker();
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final XFile? file;
    try {
      // Resized/compressed on the device so it fits the 500 KB server limit.
      file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
    } on PlatformException catch (e) {
      if (mounted) {
        showErrorSnack(context, 'Could not open the gallery: ${e.message}');
      }
      return;
    }
    if (file == null) return;

    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final mimeType =
          YabosenApi.sniffImageMimeType(bytes) ??
          YabosenApi.avatarMimeTypeFor(file.name);
      if (mimeType == null) {
        throw const ApiException(
          'Unsupported image type. Use PNG, JPEG, GIF or WebP.',
        );
      }
      if (bytes.length > YabosenApi.maxAvatarBytes) {
        throw ApiException(
          'Image is ${(bytes.length / 1024).round()} KB after resizing; the '
          'limit is 500 KB. Try a JPEG or a simpler image.',
        );
      }
      final size = await widget.api.uploadAvatar(bytes, mimeType: mimeType);
      widget.statusController.bumpAvatar();
      await HapticFeedback.mediumImpact();
      if (mounted) showInfoSnack(context, 'Avatar updated ($size)');
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AppColors.muted);
    return Panel(
      title: 'Avatar',
      children: [
        Row(
          children: [
            ListenableBuilder(
              listenable: widget.statusController,
              builder: (context, _) => AvatarThumb(
                url: widget.api.avatarUri(
                  version: widget.statusController.avatarVersion,
                ),
                size: 88,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListenableBuilder(
                    listenable: widget.apiKey,
                    builder: (context, _) => FilledButton.tonalIcon(
                      onPressed: widget.apiKey.hasKey && !_uploading
                          ? _pickAndUpload
                          : null,
                      icon: _uploading
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_library_outlined, size: 18),
                      label: Text(_uploading ? 'Uploading…' : 'Choose image'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'PNG, JPEG, GIF or WebP, up to 500 KB. Photos are resized '
                    'to 512 px.',
                    style: muted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
