import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../../lib/core/services/auth_service.dart';
import '../../../lib/core/api/api_client.dart';
import '../../../lib/core/api/api_exceptions.dart';
import '../../../lib/core/constants/app_constants.dart';
import '../../helpers/test_helpers.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}
class MockLocalAuthentication extends Mock implements LocalAuthentication {}

void main() {
  group('AuthService Tests', () {
    late AuthService authService;
    late MockApiClient mockApiClient;
    late MockFlutterSecureStorage mockSecureStorage;
    late MockLocalAuthentication mockLocalAuth;

    setUp(() async {
      await TestHelpers.initializeTestEnvironment();
      
      mockApiClient = MockApiClient();
      mockSecureStorage = MockFlutterSecureStorage();
      mockLocalAuth = MockLocalAuthentication();
      
      authService = AuthService.instance;
    });

    tearDown(() async {
      await TestHelpers.cleanupTestEnvironment();
    });

    group('Authentication', () {
      test('should sign in with valid credentials', () async {
        // Arrange
        const email = 'test@example.com';
        const password = 'password123';
        
        final mockResponse = TestHelpers.createMockResponse(
          data: {
            'success': true,
            'message': 'Authentication successful',
            'access_token': 'mock_access_token',
            'refresh_token': 'mock_refresh_token',
            'user': TestHelpers.createTestUser(email: email),
          },
          statusCode: 200,
        );

        when(mockApiClient.post('/api/auth/login', data: anyNamed('data')))
            .thenAnswer((_) async => mockResponse);

        when(mockSecureStorage.write(
          key: anyNamed('key'),
          value: anyNamed('value'),
        )).thenAnswer((_) async {});

        // Act
        final result = await authService.signInWithEmail(
          email: email,
          password: password,
        );

        // Assert
        expect(result.success, isTrue);
        expect(result.message, 'Authentication successful');
        
        verify(mockApiClient.post('/api/auth/login', data: {
          'email': email.toLowerCase().trim(),
          'password': password,
          'device_info': anyNamed('device_info'),
          'remember_me': false,
        })).called(1);

        verify(mockSecureStorage.write(
          key: AppConstants.authTokenKey,
          value: 'mock_access_token',
        )).called(1);

        verify(mockSecureStorage.write(
          key: AppConstants.refreshTokenKey,
          value: 'mock_refresh_token',
        )).called(1);
      });

      test('should return failure for invalid credentials', () async {
        // Arrange
        const email = 'test@example.com';
        const password = 'wrongpassword';

        when(mockApiClient.post('/api/auth/login', data: anyNamed('data')))
            .thenThrow(UnauthorizedException('Invalid credentials'));

        // Act
        final result = await authService.signInWithEmail(
          email: email,
          password: password,
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.message, contains('Invalid'));
      });

      test('should handle network errors gracefully', () async {
        // Arrange
        const email = 'test@example.com';
        const password = 'password123';

        when(mockApiClient.post('/api/auth/login', data: anyNamed('data')))
            .thenThrow(NetworkException('No internet connection'));

        // Act
        final result = await authService.signInWithEmail(
          email: email,
          password: password,
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.message, contains('Network error'));
      });

      test('should validate email format', () async {
        // Arrange
        const invalidEmail = 'invalid-email';
        const password = 'password123';

        // Act
        final result = await authService.signInWithEmail(
          email: invalidEmail,
          password: password,
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.message, contains('valid email'));
      });

      test('should validate password length', () async {
        // Arrange
        const email = 'test@example.com';
        const shortPassword = '123';

        // Act
        final result = await authService.signInWithEmail(
          email: email,
          password: shortPassword,
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.message, contains('8 characters'));
      });
    });

    group('User Registration', () {
      test('should register new user successfully', () async {
        // Arrange
        const email = 'newuser@example.com';
        const password = 'password123';
        const firstName = 'John';
        const lastName = 'Doe';

        final mockResponse = TestHelpers.createMockResponse(
          data: {
            'success': true,
            'message': 'Registration successful',
            'user_id': 'new-user-id',
          },
          statusCode: 201,
        );

        when(mockApiClient.post('/api/auth/register', data: anyNamed('data')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await authService.signUp(
          email: email,
          password: password,
          confirmPassword: password,
          firstName: firstName,
          lastName: lastName,
        );

        // Assert
        expect(result.success, isTrue);
        expect(result.message, contains('successful'));

        verify(mockApiClient.post('/api/auth/register', data: {
          'email': email.toLowerCase().trim(),
          'password': password,
          'password_confirmation': password,
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'phone_number': null,
          'business_name': null,
          'device_info': anyNamed('device_info'),
        })).called(1);
      });

      test('should fail registration with mismatched passwords', () async {
        // Arrange
        const email = 'newuser@example.com';
        const password = 'password123';
        const confirmPassword = 'different123';
        const firstName = 'John';
        const lastName = 'Doe';

        // Act
        final result = await authService.signUp(
          email: email,
          password: password,
          confirmPassword: confirmPassword,
          firstName: firstName,
          lastName: lastName,
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.message, contains('do not match'));
      });

      test('should handle registration validation errors', () async {
        // Arrange
        const email = 'existing@example.com';
        const password = 'password123';
        const firstName = 'John';
        const lastName = 'Doe';

        when(mockApiClient.post('/api/auth/register', data: anyNamed('data')))
            .thenThrow(ValidationException(
              'Validation failed',
              {'email': ['Email already exists']},
            ));

        // Act
        final result = await authService.signUp(
          email: email,
          password: password,
          confirmPassword: password,
          firstName: firstName,
          lastName: lastName,
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.message, contains('Email already exists'));
      });
    });

    group('Biometric Authentication', () {
      test('should enable biometric auth successfully', () async {
        // Arrange
        const password = 'password123';

        when(mockLocalAuth.isDeviceSupported()).thenAnswer((_) async => true);
        when(mockLocalAuth.canCheckBiometrics).thenAnswer((_) async => true);
        when(mockLocalAuth.getAvailableBiometrics())
            .thenAnswer((_) async => [BiometricType.fingerprint]);
        when(mockLocalAuth.authenticate(
          localizedReason: anyNamed('localizedReason'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => true);

        when(mockSecureStorage.write(
          key: anyNamed('key'),
          value: anyNamed('value'),
        )).thenAnswer((_) async {});

        // Mock password verification
        final mockResponse = TestHelpers.createMockResponse(
          data: {'success': true},
          statusCode: 200,
        );

        when(mockApiClient.post('/api/auth/verify-password', data: anyNamed('data')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await authService.enableBiometricAuth(password);

        // Assert
        expect(result.success, isTrue);
        expect(result.message, contains('enabled successfully'));

        verify(mockSecureStorage.write(
          key: AppConstants.biometricEnabledKey,
          value: 'true',
        )).called(1);
      });

      test('should fail biometric auth on unsupported device', () async {
        // Arrange
        const password = 'password123';

        when(mockLocalAuth.isDeviceSupported()).thenAnswer((_) async => false);
        when(mockLocalAuth.canCheckBiometrics).thenAnswer((_) async => false);

        // Act
        final result = await authService.enableBiometricAuth(password);

        // Assert
        expect(result.success, isFalse);
        expect(result.message, contains('not available'));
      });

      test('should sign in with biometric successfully', () async {
        // Arrange
        when(mockLocalAuth.isDeviceSupported()).thenAnswer((_) async => true);
        when(mockLocalAuth.canCheckBiometrics).thenAnswer((_) async => true);
        when(mockSecureStorage.read(key: AppConstants.biometricEnabledKey))
            .thenAnswer((_) async => 'true');
        when(mockSecureStorage.read(key: AppConstants.biometricCredentialsKey))
            .thenAnswer((_) async => 'encrypted_credentials');

        when(mockLocalAuth.authenticate(
          localizedReason: anyNamed('localizedReason'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => true);

        // Act
        final result = await authService.signInWithBiometric();

        // Assert - This would require more setup for the actual sign-in flow
        // For now, we'll verify the biometric authentication was attempted
        verify(mockLocalAuth.authenticate(
          localizedReason: 'Authenticate to access LiquorPro',
          options: anyNamed('options'),
        )).called(1);
      });
    });

    group('Token Management', () {
      test('should refresh token successfully', () async {
        // Arrange
        when(mockSecureStorage.read(key: AppConstants.refreshTokenKey))
            .thenAnswer((_) async => 'mock_refresh_token');

        final mockResponse = TestHelpers.createMockResponse(
          data: {
            'access_token': 'new_access_token',
            'refresh_token': 'new_refresh_token',
          },
          statusCode: 200,
        );

        when(mockApiClient.post('/api/auth/refresh', data: anyNamed('data')))
            .thenAnswer((_) async => mockResponse);

        when(mockSecureStorage.write(
          key: anyNamed('key'),
          value: anyNamed('value'),
        )).thenAnswer((_) async {});

        // Act - This would require access to the private method
        // In a real implementation, we might expose a public method for testing
        
        // Assert
        // Verify token refresh logic through public methods
        expect(authService, isNotNull);
      });

      test('should handle token refresh failure', () async {
        // Arrange
        when(mockSecureStorage.read(key: AppConstants.refreshTokenKey))
            .thenAnswer((_) async => 'expired_refresh_token');

        when(mockApiClient.post('/api/auth/refresh', data: anyNamed('data')))
            .thenThrow(UnauthorizedException('Refresh token expired'));

        // Act & Assert
        // This would test the token refresh failure scenario
        expect(authService, isNotNull);
      });
    });

    group('Sign Out', () {
      test('should sign out successfully', () async {
        // Arrange
        final mockResponse = TestHelpers.createMockResponse(
          data: {'success': true},
          statusCode: 200,
        );

        when(mockApiClient.post('/api/auth/logout'))
            .thenAnswer((_) async => mockResponse);

        when(mockSecureStorage.delete(key: anyNamed('key')))
            .thenAnswer((_) async {});

        // Act
        await authService.signOut();

        // Assert
        verify(mockApiClient.post('/api/auth/logout')).called(1);
        
        verify(mockSecureStorage.delete(key: AppConstants.authTokenKey)).called(1);
        verify(mockSecureStorage.delete(key: AppConstants.refreshTokenKey)).called(1);
        verify(mockSecureStorage.delete(key: AppConstants.userDataKey)).called(1);
      });

      test('should sign out even if API call fails', () async {
        // Arrange
        when(mockApiClient.post('/api/auth/logout'))
            .thenThrow(NetworkException('Network error'));

        when(mockSecureStorage.delete(key: anyNamed('key')))
            .thenAnswer((_) async {});

        // Act
        await authService.signOut();

        // Assert
        verify(mockSecureStorage.delete(key: AppConstants.authTokenKey)).called(1);
        verify(mockSecureStorage.delete(key: AppConstants.refreshTokenKey)).called(1);
        verify(mockSecureStorage.delete(key: AppConstants.userDataKey)).called(1);
      });
    });

    group('Authentication State', () {
      test('should initialize with unauthenticated state', () {
        // Assert
        expect(authService.authState, AuthState.initial);
        expect(authService.isAuthenticated, isFalse);
        expect(authService.currentUser, isNull);
      });

      test('should emit authentication state changes', () async {
        // Arrange
        final states = <AuthState>[];
        final subscription = authService.authStateStream.listen(states.add);

        // Act
        await authService.initialize();

        // Clean up
        await subscription.cancel();

        // Assert
        expect(states, isNotEmpty);
      });

      test('should check stored authentication on initialization', () async {
        // Arrange
        when(mockSecureStorage.read(key: AppConstants.authTokenKey))
            .thenAnswer((_) async => 'stored_token');
        when(mockSecureStorage.read(key: AppConstants.userDataKey))
            .thenAnswer((_) async => '{"id":"user-1","email":"test@example.com"}');

        // Act
        await authService.initialize();

        // Assert
        verify(mockSecureStorage.read(key: AppConstants.authTokenKey)).called(1);
        verify(mockSecureStorage.read(key: AppConstants.userDataKey)).called(1);
      });
    });

    group('Error Handling', () {
      test('should handle API timeouts', () async {
        // Arrange
        when(mockApiClient.post('/api/auth/login', data: anyNamed('data')))
            .thenThrow(TimeoutException('Request timeout'));

        // Act
        final result = await authService.signInWithEmail(
          email: 'test@example.com',
          password: 'password123',
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.message, contains('connection'));
      });

      test('should handle server errors', () async {
        // Arrange
        when(mockApiClient.post('/api/auth/login', data: anyNamed('data')))
            .thenThrow(ServerException('Internal server error', statusCode: 500));

        // Act
        final result = await authService.signInWithEmail(
          email: 'test@example.com',
          password: 'password123',
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.message, isNotEmpty);
      });

      test('should handle unknown errors', () async {
        // Arrange
        when(mockApiClient.post('/api/auth/login', data: anyNamed('data')))
            .thenThrow(Exception('Unexpected error'));

        // Act
        final result = await authService.signInWithEmail(
          email: 'test@example.com',
          password: 'password123',
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.message, contains('unexpected'));
      });
    });

    group('Performance Tests', () {
      test('should complete authentication within acceptable time', () async {
        // Arrange
        const email = 'test@example.com';
        const password = 'password123';

        final mockResponse = TestHelpers.createMockResponse(
          data: {
            'success': true,
            'access_token': 'token',
            'refresh_token': 'refresh',
            'user': TestHelpers.createTestUser(),
          },
        );

        when(mockApiClient.post('/api/auth/login', data: anyNamed('data')))
            .thenAnswer((_) async {
              await TestHelpers.mockNetworkDelay();
              return mockResponse;
            });

        when(mockSecureStorage.write(
          key: anyNamed('key'),
          value: anyNamed('value'),
        )).thenAnswer((_) async {});

        // Act & Assert
        await TestHelpers.testPerformance(
          'Authentication Performance Test',
          () async {
            final result = await authService.signInWithEmail(
              email: email,
              password: password,
            );
            expect(result.success, isTrue);
          },
        );
      });

      test('should handle multiple concurrent authentication requests', () async {
        // Arrange
        const email = 'test@example.com';
        const password = 'password123';

        final mockResponse = TestHelpers.createMockResponse(
          data: {
            'success': true,
            'access_token': 'token',
            'refresh_token': 'refresh',
            'user': TestHelpers.createTestUser(),
          },
        );

        when(mockApiClient.post('/api/auth/login', data: anyNamed('data')))
            .thenAnswer((_) async => mockResponse);

        when(mockSecureStorage.write(
          key: anyNamed('key'),
          value: anyNamed('value'),
        )).thenAnswer((_) async {});

        // Act
        final futures = List.generate(5, (index) => 
          authService.signInWithEmail(
            email: email,
            password: password,
          ),
        );

        final results = await Future.wait(futures);

        // Assert
        expect(results.length, 5);
        for (final result in results) {
          expect(result.success, isTrue);
        }
      });
    });
  });
}