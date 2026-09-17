import 'package:ccrouter/ccrouter.dart';

abstract interface class PaymentService {
  Future<String> pay(int amount);
}

final class CreateOrder implements CCCommand<String> {
  const CreateOrder(this.amount);
  final int amount;
}
