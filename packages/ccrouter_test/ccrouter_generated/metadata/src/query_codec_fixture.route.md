# CCRouter Routes

Generated from `lib/src/query_codec_fixture.dart`. Do not edit by hand.

## `query_codec_fixture.detail`

- Owner: `query_codec_fixture`
- Component version: `1.0.0`
- Exposure: `internal`
- Deep link: `disabled`
- Result: `void`
- Declaration: `ccrouter_test:lib/src/query_codec_fixture.dart` (page)
- Placement: host `default`, outlet `root`, shell `none`, parent `none`
- Presentation: `page`
- Navigation sources: `typedIntent, internalUri`
- Restoration: `unsupported`
- Contract library: `ccrouter_test:lib/src/query_codec_fixture.dart`
- Patterns:
  - `/query-codec-fixture` (CCPathPattern, primary)
- Parameters:

| Name | Wire name | Source | Type | Cardinality | Codec | Required | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `tags` | `tags` | `query` | `List<String>` | `repeated` | `-` | true | Ordered repeated text values. |
| `ids` | `ids` | `query` | `Set<int>` | `repeated` | `-` | true | Unordered repeated integer values. |
| `states` | `states` | `query` | `List<QueryCodecFixtureState>?` | `repeated` | `-` | false | Optional repeated enum values. |
| `filter` | `filter` | `query` | `QueryCodecFixtureFilter?` | `repeated` | `QueryCodecFixtureFilterCodec` | false | Optional complex Query value. |
