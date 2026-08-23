import 'package:care_navigator_ph/src/repositories/care_assistant_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

void main() {
  test('413 function errors become a clear image-size message', () {
    const error = FunctionException(
      status: 413,
      details: {'error': 'Request is too large'},
    );

    expect(
      careAssistantFunctionErrorMessage(error),
      'The attached image is too large. Choose an image smaller than 2 MB.',
    );
  });

  test('function error JSON is shown without map formatting', () {
    const error = FunctionException(
      status: 400,
      details: {'error': 'The attached image is invalid or too large'},
    );

    expect(
      careAssistantFunctionErrorMessage(error),
      'The attached image is invalid or too large',
    );
  });

  test('browser fetch failures are retried and shown safely', () {
    final error = FunctionsFetchException(
      details: Exception(
        'ClientException: Failed to fetch, uri=https://example.supabase.co',
      ),
    );

    expect(isRetriableCareAssistantFunctionError(error), isTrue);
    expect(
      careAssistantFunctionErrorMessage(error),
      'The care assistant could not connect. Check your connection and try again.',
    );
  });

  test('gateway errors are retried but validation errors are not', () {
    const gatewayError = FunctionsRelayException(status: 502);
    const validationError = FunctionsHttpException(status: 400);

    expect(isRetriableCareAssistantFunctionError(gatewayError), isTrue);
    expect(isRetriableCareAssistantFunctionError(validationError), isFalse);
  });
}
