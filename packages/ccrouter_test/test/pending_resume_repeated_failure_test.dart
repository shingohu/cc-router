import 'review_repros/completed_invocation/repeated_resume.dart' as regression;

// Repeated replay callers keep their local failure even when the original
// navigation recovers, including across distinct error Zones.
void main() => regression.main();
