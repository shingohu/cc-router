import 'package:ccrouter_contracts/ccrouter_contracts.dart';

/// Validates authored and persisted versions with the Runtime SemVer parser.
/// Callers retain their source-specific diagnostics; no whitespace is normalized.
bool isContractSemanticVersion(String value) {
  try {
    CCSemVer.parse(value);
    return true;
  } on FormatException {
    return false;
  }
}
