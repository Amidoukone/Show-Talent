class EmailActionLinkParser {
  EmailActionLinkParser._();

  static const List<String> _nestedParamKeys = <String>[
    'link',
    'continueUrl',
    'deep_link_id',
  ];

  static Map<String, String> extract(Uri uri, {int maxDepth = 3}) {
    return _extract(uri, depth: 0, maxDepth: maxDepth);
  }

  static Map<String, String> _extract(
    Uri uri, {
    required int depth,
    required int maxDepth,
  }) {
    final params = <String, String>{...uri.queryParameters};

    if (uri.fragment.isNotEmpty) {
      try {
        params.addAll(Uri.splitQueryString(uri.fragment));
      } catch (_) {}
    }

    if (depth >= maxDepth) {
      return params;
    }

    for (final key in _nestedParamKeys) {
      final nestedUri = _tryParseNestedUri(params[key]);
      if (nestedUri == null) {
        continue;
      }

      final nestedParams = _extract(
        nestedUri,
        depth: depth + 1,
        maxDepth: maxDepth,
      );

      for (final entry in nestedParams.entries) {
        params.putIfAbsent(entry.key, () => entry.value);
      }
    }

    return params;
  }

  static Uri? _tryParseNestedUri(String? rawValue) {
    if (rawValue == null) {
      return null;
    }

    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    return Uri.tryParse(trimmed);
  }
}
