/// Versioned identities and compatibility checks for generated Contracts.
///
/// This file is deliberately Flutter-free. Build tooling, Host assembly, and
/// the Runtime use the same immutable values so a stale or mixed generated
/// graph fails deterministically instead of being silently downgraded.

/// The generated capability families that can cross a Package boundary.
enum CCContractKind {
  /// Typed destination and result contract.
  route,

  /// Repeatable capability interface.
  service,

  /// One-to-one requested operation.
  command,

  /// Already-completed fact published to subscribers.
  event,

  /// Runtime-lifetime initialization task.
  initTask,
}

/// Stable failure codes shared by Generator, Host assembly, and Runtime.
enum CCContractCompatibilityCode {
  /// A consumer names a Contract that is not installed.
  missing,

  /// A Contract is installed under a different owner component.
  ownerMismatch,

  /// The installed version does not satisfy the consumer range.
  versionOutOfRange,

  /// The installed public shape differs from the consumer fingerprint.
  fingerprintChanged,

  /// Two non-identical implementations claim the same Contract ID.
  duplicateImplementation,

  /// Generated output is internally inconsistent or stale.
  staleGeneratedOutput,
}

/// One parsed SemVer 2.0 value used by compatibility checks.
final class CCSemVer implements Comparable<CCSemVer> {
  /// Parses a strict `major.minor.patch[-pre][+build]` value.
  factory CCSemVer.parse(String source) {
    final match = _semVerPattern.firstMatch(source.trim());
    if (match == null) {
      throw FormatException('Invalid Contract SemVer: $source');
    }
    final pre = match.group(4);
    return CCSemVer._(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      pre == null || pre.isEmpty ? const [] : pre.substring(1).split('.'),
    );
  }

  const CCSemVer._(this.major, this.minor, this.patch, this.preRelease);

  /// Major compatibility number.
  final int major;

  /// Minor compatibility number.
  final int minor;

  /// Patch compatibility number.
  final int patch;

  /// Pre-release identifiers, without the leading hyphen.
  final List<String> preRelease;

  /// Whether this is a stable release without a pre-release suffix.
  bool get isStable => preRelease.isEmpty;

  @override
  int compareTo(CCSemVer other) {
    final core = major.compareTo(other.major);
    if (core != 0) return core;
    final minorResult = minor.compareTo(other.minor);
    if (minorResult != 0) return minorResult;
    final patchResult = patch.compareTo(other.patch);
    if (patchResult != 0) return patchResult;
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;
    for (var index = 0; index < preRelease.length; index++) {
      if (index >= other.preRelease.length) return 1;
      final left = preRelease[index];
      final right = other.preRelease[index];
      if (left == right) continue;
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      if (leftNumber != null) return -1;
      if (rightNumber != null) return 1;
      return left.compareTo(right);
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }

  @override
  bool operator ==(Object other) => other is CCSemVer && compareTo(other) == 0;

  /// Orders this version against [other].
  bool operator <(CCSemVer other) => compareTo(other) < 0;

  /// Orders this version against [other].
  bool operator <=(CCSemVer other) => compareTo(other) <= 0;

  /// Orders this version against [other].
  bool operator >(CCSemVer other) => compareTo(other) > 0;

  /// Orders this version against [other].
  bool operator >=(CCSemVer other) => compareTo(other) >= 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease.join('.'));

  @override
  String toString() =>
      '$major.$minor.$patch${preRelease.isEmpty ? '' : '-${preRelease.join('.')}'}';
}

final RegExp _semVerPattern = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'((?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)'
  r'(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?)'
  r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
);

/// A finite, deterministic Contract version range.
///
/// Supported forms are exact versions, `*`, caret ranges, tilde ranges, and
/// whitespace-separated `>=`/`>`/`<=`/`<` comparators. Arbitrary expressions
/// are rejected at generation time and never interpreted at Runtime.
final class CCContractVersionRange {
  /// Parses one supported range expression.
  factory CCContractVersionRange.parse(String source) {
    final expression = source.trim();
    if (expression.isEmpty || expression == '*') {
      return CCContractVersionRange._(source, (_) => true);
    }
    if (expression.startsWith('^')) {
      final minimum = CCSemVer.parse(expression.substring(1));
      final maximum = _caretUpperBound(minimum);
      return CCContractVersionRange._(
        source,
        (value) => value >= minimum && value < maximum,
      );
    }
    if (expression.startsWith('~')) {
      final minimum = CCSemVer.parse(expression.substring(1));
      final maximum = CCSemVer._(minimum.major, minimum.minor + 1, 0, const []);
      return CCContractVersionRange._(
        source,
        (value) => value >= minimum && value < maximum,
      );
    }
    if (expression.contains(' ')) {
      final predicates = expression
          .split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty)
          .map(_parseComparator)
          .toList(growable: false);
      if (predicates.isEmpty) throw FormatException('Empty Contract range.');
      return CCContractVersionRange._(
        source,
        (value) => predicates.every((predicate) => predicate(value)),
      );
    }
    final exact = CCSemVer.parse(
      expression.startsWith('=') ? expression.substring(1) : expression,
    );
    return CCContractVersionRange._(source, (value) => value == exact);
  }

  const CCContractVersionRange._(this.source, this._allows);

  /// Original normalized range expression retained for generated metadata.
  final String source;
  final bool Function(CCSemVer) _allows;

  /// Whether [version] satisfies this range.
  bool allows(CCSemVer version) => _allows(version);

  /// Whether a textual version satisfies this range.
  bool allowsText(String version) => allows(CCSemVer.parse(version));
}

CCSemVer _caretUpperBound(CCSemVer value) {
  if (value.major > 0) return CCSemVer._(value.major + 1, 0, 0, const []);
  if (value.minor > 0) return CCSemVer._(0, value.minor + 1, 0, const []);
  return CCSemVer._(0, 0, value.patch + 1, const []);
}

bool Function(CCSemVer) _parseComparator(String token) {
  final match = RegExp(r'^(>=|<=|>|<|=)?(.+)$').firstMatch(token);
  if (match == null)
    throw FormatException('Invalid Contract comparator: $token');
  final version = CCSemVer.parse(match.group(2)!);
  return switch (match.group(1)) {
    '>=' => (value) => value >= version,
    '>' => (value) => value > version,
    '<=' => (value) => value <= version,
    '<' => (value) => value < version,
    _ => (value) => value == version,
  };
}

/// Immutable descriptor of one generated Contract implementation.
final class CCContractDescriptor {
  /// Creates one generated Contract identity.
  const CCContractDescriptor({
    required this.kind,
    required this.id,
    required this.ownerComponentId,
    required this.version,
    required this.shapeFingerprint,
  });

  /// Contract family.
  final CCContractKind kind;

  /// Globally stable Contract ID.
  final String id;

  /// Component that owns the Contract implementation.
  final String ownerComponentId;

  /// Independent Contract SemVer.
  final String version;

  /// Canonical public-shape SHA-256 fingerprint.
  final String shapeFingerprint;
}

/// One generated consumer requirement for a Contract.
final class CCContractRequirement {
  /// Creates one consumer-side compatibility declaration.
  const CCContractRequirement({
    required this.kind,
    required this.contractId,
    required this.consumerPackage,
    required this.ownerComponentId,
    required this.requiredVersionRange,
    required this.requiredShapeFingerprint,
  });

  /// Contract family expected by the consumer.
  final CCContractKind kind;

  /// Contract ID requested by the consumer.
  final String contractId;

  /// Package that generated this requirement.
  final String consumerPackage;

  /// Owner component declared by the consumer metadata.
  final String ownerComponentId;

  /// Finite version range accepted by this consumer.
  final String requiredVersionRange;

  /// Exact shape fingerprint accepted by this consumer.
  final String requiredShapeFingerprint;
}

/// Generated compatibility payload carried by one Package Bundle.
final class CCContractBundleDescriptor {
  /// Creates a Package-local Contract descriptor and its consumer requirements.
  CCContractBundleDescriptor({
    required this.packageName,
    required this.packageVersion,
    Iterable<CCContractDescriptor> contracts = const [],
    Iterable<CCContractRequirement> requirements = const [],
  }) : contracts = List.unmodifiable(contracts),
       requirements = List.unmodifiable(requirements);

  /// Package publishing this local descriptor.
  final String packageName;

  /// Resolved Package version used for diagnostics.
  final String packageVersion;

  /// Contracts implemented by this Package's installed components.
  final List<CCContractDescriptor> contracts;

  /// Cross-Package requirements generated by this Package's consumers.
  final List<CCContractRequirement> requirements;

  /// Validates all local and resolved descriptors without mutating them.
  static List<CCContractCompatibilityIssue> validate(
    Iterable<CCContractBundleDescriptor> bundles,
  ) {
    final issues = <CCContractCompatibilityIssue>[];
    final installed = <String, CCContractDescriptor>{};
    for (final bundle in bundles) {
      final localIds = <String>{};
      for (final contract in bundle.contracts) {
        if (!localIds.add(contract.id)) {
          issues.add(CCContractCompatibilityIssue.duplicate(contract));
          continue;
        }
        final existing = installed[contract.id];
        if (existing != null) {
          if (existing.kind != contract.kind ||
              existing.ownerComponentId != contract.ownerComponentId ||
              existing.version != contract.version ||
              existing.shapeFingerprint != contract.shapeFingerprint) {
            issues.add(CCContractCompatibilityIssue.duplicate(contract));
          }
          continue;
        }
        installed[contract.id] = contract;
        try {
          CCSemVer.parse(contract.version);
        } on FormatException {
          issues.add(
            CCContractCompatibilityIssue.stale(
              kind: contract.kind,
              id: contract.id,
              packageName: bundle.packageName,
              message: 'Contract version is not valid SemVer.',
            ),
          );
        }
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(contract.shapeFingerprint)) {
          issues.add(
            CCContractCompatibilityIssue.stale(
              kind: contract.kind,
              id: contract.id,
              packageName: bundle.packageName,
              message: 'Contract shape fingerprint is not SHA-256.',
            ),
          );
        }
      }
    }
    for (final bundle in bundles) {
      for (final requirement in bundle.requirements) {
        final contract = installed[requirement.contractId];
        if (contract == null) {
          issues.add(
            CCContractCompatibilityIssue(
              code: CCContractCompatibilityCode.missing,
              kind: requirement.kind,
              contractId: requirement.contractId,
              packageName: requirement.consumerPackage,
              message: 'Contract is not installed.',
            ),
          );
          continue;
        }
        if (contract.kind != requirement.kind ||
            contract.ownerComponentId != requirement.ownerComponentId) {
          issues.add(
            CCContractCompatibilityIssue(
              code: CCContractCompatibilityCode.ownerMismatch,
              kind: requirement.kind,
              contractId: requirement.contractId,
              packageName: requirement.consumerPackage,
              message:
                  'Installed Contract owner or kind differs from the requirement.',
            ),
          );
          continue;
        }
        try {
          final range = CCContractVersionRange.parse(
            requirement.requiredVersionRange,
          );
          if (!range.allowsText(contract.version)) {
            issues.add(
              CCContractCompatibilityIssue(
                code: CCContractCompatibilityCode.versionOutOfRange,
                kind: requirement.kind,
                contractId: requirement.contractId,
                packageName: requirement.consumerPackage,
                message:
                    'Installed Contract version is outside the required range.',
              ),
            );
          }
        } on FormatException {
          issues.add(
            CCContractCompatibilityIssue.stale(
              kind: requirement.kind,
              id: requirement.contractId,
              packageName: requirement.consumerPackage,
              message: 'Consumer version range is invalid.',
            ),
          );
        }
        if (contract.shapeFingerprint != requirement.requiredShapeFingerprint) {
          issues.add(
            CCContractCompatibilityIssue(
              code: CCContractCompatibilityCode.fingerprintChanged,
              kind: requirement.kind,
              contractId: requirement.contractId,
              packageName: requirement.consumerPackage,
              message: 'Installed Contract shape fingerprint differs.',
            ),
          );
        }
      }
    }
    return List.unmodifiable(issues);
  }
}

/// One deterministic Contract compatibility failure.
final class CCContractCompatibilityIssue {
  /// Creates a compatibility issue with a stable [code].
  const CCContractCompatibilityIssue({
    required this.code,
    required this.kind,
    required this.contractId,
    required this.packageName,
    required this.message,
  });

  /// Creates a duplicate implementation issue.
  factory CCContractCompatibilityIssue.duplicate(
    CCContractDescriptor contract,
  ) => CCContractCompatibilityIssue(
    code: CCContractCompatibilityCode.duplicateImplementation,
    kind: contract.kind,
    contractId: contract.id,
    packageName: contract.ownerComponentId,
    message: 'More than one incompatible implementation claims this Contract.',
  );

  /// Creates an invalid generated-output issue.
  factory CCContractCompatibilityIssue.stale({
    required CCContractKind kind,
    required String id,
    required String packageName,
    required String message,
  }) => CCContractCompatibilityIssue(
    code: CCContractCompatibilityCode.staleGeneratedOutput,
    kind: kind,
    contractId: id,
    packageName: packageName,
    message: message,
  );

  /// Stable failure code.
  final CCContractCompatibilityCode code;

  /// Contract family.
  final CCContractKind kind;

  /// Contract identity involved in the failure.
  final String contractId;

  /// Package used for diagnostics, never a business payload.
  final String packageName;

  /// Sanitized explanation.
  final String message;

  @override
  String toString() =>
      'CCContractCompatibilityIssue(${code.name}, ${kind.name}, $contractId): $message';
}

/// Runtime/Host error raised when generated Contract boundaries are invalid.
final class CCContractCompatibilityError implements Exception {
  /// Creates an error retaining the complete sanitized issue list.
  CCContractCompatibilityError(Iterable<CCContractCompatibilityIssue> issues)
    : issues = List.unmodifiable(issues);

  /// Stable failures that prevented assembly or Runtime startup.
  final List<CCContractCompatibilityIssue> issues;

  @override
  String toString() =>
      'CCContractCompatibilityError(${issues.map((issue) => issue.code.name).join(', ')}).';
}
