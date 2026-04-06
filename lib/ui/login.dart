import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:provider/provider.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _headerKeyController = TextEditingController();
  final TextEditingController _headerValueController = TextEditingController();

  Map<String, String> _headers = {};
  bool _isLoading = false;
  String? _errorText;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }

    FluxNewsState appState = context.read<FluxNewsState>();
    if (appState.minifluxURL != null) {
      _urlController.text = appState.minifluxURL!;
    }
    if (appState.minifluxAPIKey != null) {
      _apiKeyController.text = appState.minifluxAPIKey!;
    }
    if (appState.customHeaders.isNotEmpty) {
      _headers = Map<String, String>.from(appState.customHeaders);
    }

    _initialized = true;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    _headerKeyController.dispose();
    _headerValueController.dispose();
    super.dispose();
  }

  String _normalizeUrl(String url) {
    var normalizedUrl = url.trim();
    if (!normalizedUrl.endsWith('/v1/')) {
      if (!normalizedUrl.endsWith('/v1')) {
        if (normalizedUrl.endsWith('/')) {
          normalizedUrl = normalizedUrl + FluxNewsState.apiVersionPath;
        } else {
          normalizedUrl = '$normalizedUrl/${FluxNewsState.apiVersionPath}';
        }
      } else {
        normalizedUrl = '$normalizedUrl/';
      }
    }
    return normalizedUrl;
  }

  void _addHeader() {
    final key = _headerKeyController.text.trim();
    final value = _headerValueController.text.trim();
    if (key.isEmpty) {
      return;
    }
    setState(() {
      _headers[key] = value;
      _headerKeyController.clear();
      _headerValueController.clear();
    });
  }

  Future<void> _submit(BuildContext context) async {
    if (_isLoading) {
      return;
    }

    FluxNewsState appState = context.read<FluxNewsState>();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final normalizedUrl = _normalizeUrl(_urlController.text);
    final apiKey = _apiKeyController.text.trim();
    final parsedHeaders = Map<String, String>.from(_headers);

    final previousHeaders = Map<String, String>.from(appState.customHeaders);

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    appState.customHeaders = parsedHeaders;
    final authCheck =
        await checkMinifluxCredentials(normalizedUrl, apiKey, appState).onError((error, stackTrace) => false);

    if (!authCheck) {
      appState.customHeaders = previousHeaders;
      appState.errorOnMinifluxAuth = true;
      appState.insecureMinifluxURL = !normalizedUrl.toLowerCase().startsWith('https');
      appState.refreshView();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorText = AppLocalizations.of(context)!.authError;
        });
      }
      return;
    }

    appState.storage.write(key: FluxNewsState.secureStorageMinifluxURLKey, value: normalizedUrl);
    appState.storage.write(key: FluxNewsState.secureStorageMinifluxAPIKey, value: apiKey);
    appState.minifluxURL = normalizedUrl;
    appState.minifluxAPIKey = apiKey;
    appState.customHeaders = parsedHeaders;
    appState.saveCustomHeadersToStorage();
    appState.errorOnMinifluxAuth = false;
    appState.insecureMinifluxURL = !normalizedUrl.toLowerCase().startsWith('https');
    bool emptyFeeds = await checkEmptyFeeds(appState);
    if (emptyFeeds) {
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, FluxNewsState.feedOnboardingRouteString, (route) => false);
      }
      setState(() {
        _isLoading = false;
      });
      return;
    }
    appState.syncNow = true;
    appState.refreshView();

    if (context.mounted) {
      setState(() {
        _isLoading = false;
      });
      Navigator.pushNamedAndRemoveUntil(context, FluxNewsState.rootRouteString, (route) => false);
    }
  }

  Widget _buildLogo(BuildContext context) {
    final bool isLightMode = MediaQuery.of(context).platformBrightness == Brightness.light;

    return isLightMode
        ? Image.asset(
            'assets/Flux_News_Starticon_Transparent.png',
            width: 160,
            height: 160,
          )
        : Image.asset(
            'assets/Flux_News_Starticon_Invert_Transparent.png',
            width: 160,
            height: 160,
          );
  }

  Widget _buildFormContent(BuildContext context, AppLocalizations localization) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            localization.provideMinifluxCredentials,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: localization.apiUrl,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autofillHints: const [AutofillHints.url],
            validator: (value) {
              final url = value?.trim() ?? '';
              if (url.isEmpty) {
                return localization.enterURL;
              }

              final regex = RegExp(FluxNewsState.urlValidationRegex);
              if (!regex.hasMatch(url)) {
                return localization.enterValidURL;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _apiKeyController,
            decoration: InputDecoration(
              labelText: localization.apiKey,
              border: const OutlineInputBorder(),
            ),
            autofillHints: const [AutofillHints.password],
            obscureText: true,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return localization.enterAPIKey;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Text(
            localization.headers,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            children: [
              Text(localization.headerKey),
              TextField(
                controller: _headerKeyController,
              ),
            ],
          ),
          Wrap(
            children: [
              Text(localization.headerValue),
              TextField(
                controller: _headerValueController,
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _addHeader,
            child: Text(localization.saveHeader),
          ),
          if (_headers.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(localization.headerKey)),
                  DataColumn(label: Text(localization.headerValue)),
                  const DataColumn(label: Text('')),
                ],
                rows: _headers.entries
                    .map(
                      (entry) => DataRow(cells: [
                        DataCell(Text(entry.key)),
                        DataCell(Text(entry.value)),
                        DataCell(TextButton(
                          onPressed: () {
                            setState(() {
                              _headers.remove(entry.key);
                            });
                          },
                          child: Text(localization.delete),
                        )),
                      ]),
                    )
                    .toList(),
              ),
            ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          Platform.isIOS
              ? CupertinoButton.filled(
                  onPressed: _isLoading ? null : () => _submit(context),
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                        )
                      : Text(localization.save),
                )
              : ElevatedButton(
                  onPressed: _isLoading ? null : () => _submit(context),
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                        )
                      : Text(localization.save),
                ),
        ],
      ),
    );
  }

  Widget _buildPhoneLayout(BuildContext context, AppLocalizations localization) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: _buildFormContent(context, localization),
    );
  }

  Widget _buildTabletLayout(BuildContext context, AppLocalizations localization) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Row(
            children: [
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLogo(context),
                      const SizedBox(height: 28),
                      Text(
                        localization.minifluxServer,
                        style: theme.textTheme.headlineMedium?.copyWith(fontSize: 36),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        localization.provideMinifluxCredentials,
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 5,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: SingleChildScrollView(
                      child: _buildFormContent(context, localization),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context)!;
    FluxNewsState appState = context.watch<FluxNewsState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.minifluxServer),
      ),
      body: SafeArea(
        child: appState.isTablet ? _buildTabletLayout(context, localization) : _buildPhoneLayout(context, localization),
      ),
    );
  }
}
