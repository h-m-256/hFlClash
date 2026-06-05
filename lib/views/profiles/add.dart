import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/pages/scan.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';

class AddProfileView extends StatelessWidget {
  final BuildContext context;

  const AddProfileView({super.key, required this.context});

  Future<void> _handleAddProfileFormFile() async {
    globalState.container
        .read(profilesActionProvider.notifier)
        .addProfileFormFile();
  }

  Future<void> _handleAddProfileFormURL(String url) async {
    globalState.container
        .read(profilesActionProvider.notifier)
        .addProfileFormURL(url);
  }

  Future<void> _handleAddCustomSubscription(
    CustomSubscriptionFormResult result,
  ) async {
    globalState.container
        .read(profilesActionProvider.notifier)
        .addProfileFormURL(result.url, userAgent: result.userAgent);
  }

  Future<void> _toScan() async {
    if (system.isDesktop) {
      globalState.container
          .read(profilesActionProvider.notifier)
          .addProfileFormQrCode();
      return;
    }
    final url = await BaseNavigator.push(context, const ScanPage());
    if (url != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleAddProfileFormURL(url);
      });
    }
  }

  Future<void> _toAdd() async {
    final appLocalizations = context.appLocalizations;
    final url = await globalState.showCommonDialog<String>(
      child: InputDialog(
        autovalidateMode: AutovalidateMode.onUnfocus,
        title: appLocalizations.importFromURL,
        labelText: appLocalizations.url,
        value: '',
        validator: (value) {
          if (value == null || value.isEmpty) {
            return appLocalizations.emptyTip('').trim();
          }
          if (!value.isUrl && !subscriptionConverter.canConvert(value)) {
            return appLocalizations.urlTip('').trim();
          }
          return null;
        },
      ),
    );
    if (url != null) {
      _handleAddProfileFormURL(url);
    }
  }

  Future<void> _toAddCustomSubscription() async {
    final result = await globalState
        .showCommonDialog<CustomSubscriptionFormResult>(
          child: const CustomSubscriptionDialog(),
        );
    if (result != null) {
      _handleAddCustomSubscription(result);
    }
  }

  @override
  Widget build(context) {
    final appLocalizations = context.appLocalizations;
    return ListView(
      children: [
        ListItem(
          leading: const Icon(Icons.qr_code_sharp),
          title: Text(appLocalizations.qrcode),
          subtitle: Text(appLocalizations.qrcodeDesc),
          onTap: _toScan,
        ),
        ListItem(
          leading: const Icon(Icons.upload_file_sharp),
          title: Text(appLocalizations.file),
          subtitle: Text(appLocalizations.fileDesc),
          onTap: _handleAddProfileFormFile,
        ),
        ListItem(
          leading: const Icon(Icons.cloud_download_sharp),
          title: Text(appLocalizations.url),
          subtitle: Text(appLocalizations.urlDesc),
          onTap: _toAdd,
        ),
        ListItem(
          leading: const Icon(Icons.extension_sharp),
          title: Text(appLocalizations.customSubscription),
          subtitle: Text(appLocalizations.customSubscriptionDesc),
          onTap: _toAddCustomSubscription,
        ),
      ],
    );
  }
}

class CustomSubscriptionFormResult {
  final String url;
  final String userAgent;

  const CustomSubscriptionFormResult({
    required this.url,
    required this.userAgent,
  });
}

class CustomSubscriptionDialog extends StatefulWidget {
  const CustomSubscriptionDialog({super.key});

  @override
  State<CustomSubscriptionDialog> createState() =>
      _CustomSubscriptionDialogState();
}

class _CustomSubscriptionDialogState extends State<CustomSubscriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _userAgentController = TextEditingController(
    text: defaultCustomSubscriptionUserAgent,
  );

  Future<void> _handleSubmit() async {
    if (_formKey.currentState?.validate() == false) return;
    Navigator.of(context).pop(
      CustomSubscriptionFormResult(
        url: _urlController.text.trim(),
        userAgent: _userAgentController.text.trim().takeFirstValid([
          defaultCustomSubscriptionUserAgent,
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userAgentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonDialog(
      title: appLocalizations.customSubscription,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(appLocalizations.cancel),
        ),
        TextButton(
          onPressed: _handleSubmit,
          child: Text(appLocalizations.submit),
        ),
      ],
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUnfocus,
        child: Wrap(
          runSpacing: 16,
          children: [
            TextFormField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              maxLines: 5,
              minLines: 1,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: appLocalizations.url,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return appLocalizations.emptyTip('').trim();
                }
                if (!value.isUrl && !subscriptionConverter.canConvert(value)) {
                  return appLocalizations.urlTip('').trim();
                }
                return null;
              },
            ),
            TextFormField(
              controller: _userAgentController,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: appLocalizations.userAgent,
                helperText: appLocalizations.userAgentDesc,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return appLocalizations.emptyTip(appLocalizations.userAgent);
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}

class URLFormDialog extends StatefulWidget {
  const URLFormDialog({super.key});

  @override
  State<URLFormDialog> createState() => _URLFormDialogState();
}

class _URLFormDialogState extends State<URLFormDialog> {
  final _urlController = TextEditingController();

  Future<void> _handleAddProfileFormURL() async {
    final url = _urlController.value.text;
    if (url.isEmpty) return;
    Navigator.of(context).pop<String>(url);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonDialog(
      title: appLocalizations.importFromURL,
      actions: [
        TextButton(
          onPressed: _handleAddProfileFormURL,
          child: Text(appLocalizations.submit),
        ),
      ],
      child: SizedBox(
        width: 300,
        child: Wrap(
          runSpacing: 16,
          children: [
            TextField(
              keyboardType: TextInputType.url,
              minLines: 1,
              maxLines: 5,
              onSubmitted: (_) {
                _handleAddProfileFormURL();
              },
              onEditingComplete: _handleAddProfileFormURL,
              controller: _urlController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: appLocalizations.url,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
