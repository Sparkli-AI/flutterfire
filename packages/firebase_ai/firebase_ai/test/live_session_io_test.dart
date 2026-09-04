// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_ai/src/live_api.dart';
import 'package:firebase_ai/src/live_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retains extra configuration when resuming a session', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final firstSetupMessage = Completer<Map<String, dynamic>>();
    final resumedSetupMessage = Completer<Map<String, dynamic>>();
    final serverSubscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen(
        (message) {
          final setupMessage =
              jsonDecode(message as String) as Map<String, dynamic>;
          if (!firstSetupMessage.isCompleted) {
            firstSetupMessage.complete(setupMessage);
          } else {
            resumedSetupMessage.complete(setupMessage);
          }
        },
        onDone: () => unawaited(socket.close()),
      );
    });
    LiveSession? session;
    addTearDown(() async {
      await session?.close();
      await serverSubscription.cancel();
      await server.close(force: true);
    });

    session = await LiveSession.create(
      uri: 'ws://${server.address.address}:${server.port}',
      headers: {},
      modelString: 'models/test-model',
      extraConfig: {
        'realtime_input_config': {
          'automatic_activity_detection': {'disabled': true},
        },
      },
    );

    expect(
      await firstSetupMessage.future.timeout(const Duration(seconds: 5)),
      {
        'setup': {
          'model': 'models/test-model',
          'realtime_input_config': {
            'automatic_activity_detection': {'disabled': true},
          },
        },
      },
    );

    await session.resumeSession(
      sessionResumption: SessionResumptionConfig.resume('resume-handle'),
    );

    expect(
      await resumedSetupMessage.future.timeout(const Duration(seconds: 5)),
      {
        'setup': {
          'model': 'models/test-model',
          'realtime_input_config': {
            'automatic_activity_detection': {'disabled': true},
          },
          'session_resumption': {'handle': 'resume-handle'},
        },
      },
    );
  });
}
