import 'package:flutter/material.dart';

import '../../api.dart';
import '../../settings.dart';
import '../theme.dart';
import '../widgets.dart';

/// Enter, verify, save and clear the STATUS_API_KEY.
class ApiKeyPanel extends StatefulWidget {
  const ApiKeyPanel({super.key, required this.apiKey, required this.onChanged});

  final ApiKeyController apiKey;

  /// Called after the key was saved or cleared.
  final Future<void> Function() onChanged;

  @override
  State<ApiKeyPanel> createState() => _ApiKeyPanelState();
}

class _ApiKeyPanelState extends State<ApiKeyPanel> {
  final _field = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final candidate = _field.text.trim();
    if (candidate.isEmpty) {
      showErrorSnack(context, 'Enter your API key first.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    // Verify with a harmless heartbeat before saving.
    String? warning;
    final probe = YabosenApi(apiKey: candidate);
    try {
      await probe.sendHeartbeat();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        if (mounted) {
          setState(() => _busy = false);
          showErrorSnack(context, 'The server rejected this key (401).');
        }
        return;
      }
      warning = e.message;
    } finally {
      probe.close();
    }

    await widget.apiKey.save(candidate);
    _field.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    showInfoSnack(
      context,
      warning == null
          ? 'API key saved and verified'
          : 'API key saved, but could not verify it: $warning',
    );
    await widget.onChanged();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove API key?'),
        content: const Text(
          'The background heartbeat stops and you cannot change your status '
          'until you add the key again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.apiKey.clear();
    if (!mounted) return;
    showInfoSnack(context, 'API key removed');
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.apiKey,
      builder: (context, _) {
        final masked = widget.apiKey.maskedKey;
        return Panel(
          title: 'API key',
          children: [
            KeyValueRow(
              label: 'Saved key',
              value: masked ?? 'Not set',
              valueColor: masked == null ? AppColors.muted : null,
              action: masked == null
                  ? null
                  : TextButton(
                      onPressed: _busy ? null : _clear,
                      child: const Text('Clear'),
                    ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _field,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: masked == null ? 'API key' : 'Replace API key',
                hintText: 'STATUS_API_KEY',
                prefixIcon: const Icon(Icons.key_outlined, size: 20),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show' : 'Hide',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: InfoNote(
                    'Your website password (STATUS_API_KEY). '
                    'Stored only on this phone.',
                    icon: Icons.lock_outline,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
