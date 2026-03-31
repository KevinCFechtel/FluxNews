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
  final TextEditingController _authHeadersController = TextEditingController();

  bool _isLoading = false;
  String? _errorText;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }

    final appState = context.read<FluxNewsState>();
    if (appState.minifluxURL != null) {
      _urlController.text = appState.minifluxURL!;
    }
    if (appState.minifluxAPIKey != null) {
      _apiKeyController.text = appState.minifluxAPIKey!;
    }
    if (appState.customHeaders.isNotEmpty) {
      _authHeadersController.text =
          appState.customHeaders.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n');
    }

    _initialized = true;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    _authHeadersController.dispose();
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

  Map<String, String>? _parseAuthHeaders(String rawHeaders) {
    final parsedHeaders = <String, String>{};
    final lines = rawHeaders.split('\n');
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) {
        continue;
      }

      final separatorIndex = trimmedLine.indexOf(':');
      if (separatorIndex <= 0 || separatorIndex >= trimmedLine.length - 1) {
        return null;
      }

      final headerName = trimmedLine.substring(0, separatorIndex).trim();
      final headerValue = trimmedLine.substring(separatorIndex + 1).trim();
      if (headerName.isEmpty || headerValue.isEmpty) {
        return null;
      }

      parsedHeaders[headerName] = headerValue;
    }

    return parsedHeaders;
  }

  Future<void> _submit() async {
    if (_isLoading) {
      return;
    }

    final appState = context.read<FluxNewsState>();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final normalizedUrl = _normalizeUrl(_urlController.text);
    final apiKey = _apiKeyController.text.trim();
    final parsedHeaders = _parseAuthHeaders(_authHeadersController.text);
    if (parsedHeaders == null) {
      setState(() {
        _errorText = 'Auth Header muessen im Format "Header-Name: Wert" eingegeben werden.';
      });
      return;
    }

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
    appState.refreshView();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.minifluxServer),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
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
                    hintText: 'https://example.com/v1/',
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
                TextFormField(
                  controller: _authHeadersController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Zusaetzliche Auth Header',
                    hintText: 'Authorization: Bearer abc123\nX-Api-User: max.mustermann',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Optional. Ein Header pro Zeile im Format "Header-Name: Wert".',
                ),
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
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                              )
                            : Text(localization.save),
                      )
                    : ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
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
          ),
        ),
      ),
    );
  }
}
