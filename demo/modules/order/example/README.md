# Order Example Host

This Flutter app is an independently runnable CCRouter Host for the
`demo_order` component. Its generated Host closure contains only the example,
the Order implementation, and the Order contracts Package. The Host-owned home
page is a generated Managed Route, so this example has no GoRouter dependency.

From the repository root, refresh its generated Host assembly with:

```sh
fvm dart run --verbosity=error \
  ccrouter_generator:ccrouter generate demo/modules/order/example
```

Run the macOS example with:

```sh
cd demo/modules/order/example
fvm flutter run -d macos
```
