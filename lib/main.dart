import 'package:flutter/material.dart';
import 'api/api_config.dart';
import 'app.dart';

void main() {
  assertSecureApiBaseUrl();
  runApp(const HomeServantApp());
}
