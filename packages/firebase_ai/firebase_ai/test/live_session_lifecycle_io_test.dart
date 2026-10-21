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
import 'dart:io';

import 'package:firebase_ai/src/live_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('times out stalled setup and closes a connection that arrives late',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final request = Completer<HttpRequest>();
    final subscription = server.listen(request.complete);
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final connecting = LiveSession.create(
      uri: 'ws://${server.address.address}:${server.port}',
      headers: const {},
      modelString: 'models/test-model',
    );
    final timedOut = expectLater(connecting, throwsA(isA<TimeoutException>()));
    final pendingRequest =
        await request.future.timeout(const Duration(seconds: 5));

    await timedOut.timeout(const Duration(seconds: 12));

    final socket = await WebSocketTransformer.upgrade(pendingRequest);
    addTearDown(socket.close);
    expect(
      await socket.toList().timeout(const Duration(seconds: 5)),
      isEmpty,
    );
  });
}
