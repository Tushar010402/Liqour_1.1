import 'package:integration_test/integration_test.dart';
import 'brand_management_integration_test.dart' as brand_management;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Run all integration tests
  brand_management.main();
}
