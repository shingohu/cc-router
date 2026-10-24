import 'package:markdown/markdown.dart' as md;

/// A rendered Markdown link or image, after Markdown escaping and references.
/// The parser does not expose source spans; callers report the file and target
/// rather than guessing a line from another occurrence inside a code example.
class MarkdownReference {
  const MarkdownReference(this.target, {required this.isImage});

  final String target;
  final bool isImage;
}

/// Uses the same GFM parser for repository docs and the isolated Skill bundle.
/// Code, escaped syntax, comments and unused reference definitions are not
/// rendered links. Inline and reference-style destinations share one path.
List<MarkdownReference> markdownReferences(String source) {
  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final references = <MarkdownReference>[];
  void visit(Iterable<md.Node> nodes) {
    for (final node in nodes) {
      if (node is! md.Element) continue;
      final isImage = node.tag == 'img';
      final target = node.attributes[isImage ? 'src' : 'href'];
      if ((isImage || node.tag == 'a') && target != null) {
        references.add(MarkdownReference(target, isImage: isImage));
      }
      if (node.children != null) visit(node.children!);
    }
  }

  visit(document.parse(source));
  return references;
}

/// Resolves a local file destination, removing URL query/fragment components.
/// HTTP and other external schemes, protocol-relative URLs and fragment-only
/// links are outside the file check. Normalize decoded path segments so an
/// encoded parent traversal cannot bypass the Skill bundle containment check.
Uri? localMarkdownTarget(String target, Uri source) {
  final uri = Uri.parse(target);
  if (uri.hasScheme && uri.scheme != 'file') return null;
  if (uri.hasAuthority && uri.scheme != 'file') return null;
  if (uri.scheme == 'file' && uri.host.isNotEmpty && uri.host != 'localhost') {
    throw const FormatException('Non-local file URI');
  }
  if (uri.path.isEmpty) return null;
  final resolved = source.resolveUri(uri);
  return Uri(scheme: 'file', path: resolved.path).normalizePath();
}
