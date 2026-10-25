part of 'order_panel_fragment.dart';

/// A separate closed data union with inherited, immutable identity.
sealed class OrderPanelTarget {
  const OrderPanelTarget(this.id);
  final String id;
}

final class OrderPanelUser extends OrderPanelTarget {
  const OrderPanelUser(super.id);
}

final class OrderPanelScore extends OrderPanelTarget {
  const OrderPanelScore(super.id);
}

final class OrderPanelVideo extends OrderPanelTarget {
  const OrderPanelVideo(super.id);
}

final class OrderPanelArtist extends OrderPanelTarget {
  const OrderPanelArtist(super.id);
}
