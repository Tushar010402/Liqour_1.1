import 'package:flutter/material.dart';
import 'package:flutter_driver/flutter_driver_extension.dart';
import 'package:liquorpro_mobile/main.dart' as app;

void main() {
  // Enable integration testing
  enableFlutterDriverExtension();
  
  // Start the app
  app.main();
}