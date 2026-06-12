import 'package:flutter/material.dart';
import 'customer/customer_main_shell.dart';

// Thin wrapper kept so existing imports in main.dart and login_screen.dart
// continue to resolve without changes.
class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const CustomerMainShell();
}
