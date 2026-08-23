import 'package:flutter_test/flutter_test.dart';
import 'package:voice_assistant/services/architecture_service.dart';

void main() {
  group('ArchitectureCanvasData displayability and ranking', () {
    test('identifies non-displayable single-node architectures without connections', () {
      final data = ArchitectureCanvasData.fromJson({
        'architecture_id': 'arch-single-node',
        'title': 'Test Single Node',
        'current_blueprint': {
          'components': [
            {'id': 'node-1', 'name': 'Single Node', 'type': 'service'},
          ],
          'connections': [],
        },
      });

      expect(data.componentCount, equals(1));
      expect(data.connectionCount, equals(0));
      expect(data.isDisplayable, isFalse);
    });

    test('identifies displayable multi-node architectures', () {
      final data = ArchitectureCanvasData.fromJson({
        'architecture_id': 'arch-multi-node',
        'title': 'Web and API',
        'current_blueprint': {
          'components': [
            {'id': 'web', 'name': 'Frontend', 'type': 'frontend'},
            {'id': 'api', 'name': 'Backend', 'type': 'service'},
          ],
          'connections': [],
        },
      });

      expect(data.componentCount, equals(2));
      expect(data.connectionCount, equals(0));
      expect(data.isDisplayable, isTrue);
    });

    test('identifies displayable single-node architecture with connection', () {
      final data = ArchitectureCanvasData.fromJson({
        'architecture_id': 'arch-connected-node',
        'title': 'Self Loop Node',
        'current_blueprint': {
          'components': [
            {'id': 'node-1', 'name': 'Loop Node', 'type': 'service'},
          ],
          'connections': [
            {'id': 'conn-1', 'from': 'node-1', 'to': 'node-1'},
          ],
        },
      });

      expect(data.componentCount, equals(1));
      expect(data.connectionCount, equals(1));
      expect(data.isDisplayable, isTrue);
    });
  });
}
