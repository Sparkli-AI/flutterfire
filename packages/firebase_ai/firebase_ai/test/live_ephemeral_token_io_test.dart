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

import 'package:firebase_ai/src/error.dart';
import 'package:firebase_ai/src/live_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ephemeral connection setup contains only the constrained model',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final setup = Completer<Object?>();
    final subscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) => setup.complete(jsonDecode(message as String)),
          onDone: () => unawaited(socket.close()));
    });
    LiveSession? session;
    addTearDown(() async {
      await session?.close();
      await subscription.cancel();
      await server.close(force: true);
    });
    session = await LiveSession.create(
      uri: 'ws://${server.address.address}:${server.port}',
      headers: const {},
      modelString: 'models/test-model',
      useEphemeralToken: true,
    );
    expect(await setup.future.timeout(const Duration(seconds: 5)), {
      'setup': {'model': 'models/test-model'},
    });
  });

  test('sanitizes startup failures through the shared connection boundary',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    await expectLater(
      LiveSession.create(
        uri: 'ws://${server.address.address}:${server.port}'
            '?access_token=auth_tokens/test-secret-123',
        headers: const {},
        modelString: 'models/test-model',
        useEphemeralToken: true,
      ),
      throwsA(isA<LiveWebSocketClosedException>().having(
        (error) => error.message,
        'safe message',
        'The Live API connection failed.',
      )),
    );
  });
}
