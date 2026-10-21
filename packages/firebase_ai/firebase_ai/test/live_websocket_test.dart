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

import 'dart:async';

import 'package:firebase_ai/src/live_api.dart';
import 'package:firebase_ai/src/live_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'aborts a handshake that never upgrades before returning its timeout',
    () async {
      final peer = spawnHybridUri(
        'support/live_websocket_peer.dart',
        message: 'stall',
      );
      final messages = StreamIterator<Object?>(peer.stream);
      addTearDown(() async {
        await messages.cancel();
        await peer.sink.close();
      });
      expect(await messages.moveNext(), isTrue);
      final connecting = LiveSession.create(
        uri: '${messages.current}',
        headers: const {},
        modelString: 'models/test-model',
      );
      final timedOut = expectLater(
        connecting,
        throwsA(isA<TimeoutException>()),
      );
      expect(
        await messages.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(messages.current, 'upgrade received');

      await timedOut.timeout(const Duration(seconds: 12));

      expect(
        await messages.moveNext().timeout(const Duration(seconds: 1)),
        isTrue,
      );
      expect(messages.current, 'connection closed');
    },
  );

  test(
    'a successful handshake sends setup and parses text and binary frames',
    () async {
      final peer = spawnHybridUri(
        'support/live_websocket_peer.dart',
        message: 'connect',
      );
      final messages = StreamIterator<Object?>(peer.stream);
      LiveSession? session;
      addTearDown(() async {
        await session?.close();
        await messages.cancel();
        await peer.sink.close();
      });
      expect(await messages.moveNext(), isTrue);
      session = await LiveSession.create(
        uri: '${messages.current}',
        headers: const {},
        modelString: 'models/test-model',
      );
      final responses = session.receive().take(2).toList();
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, {
        'setup': {'model': 'models/test-model'},
      });
      peer.sink.add('send frames');
      final received = await responses.timeout(const Duration(seconds: 5));
      expect(received[0].message, isA<LiveServerSetupComplete>());
      expect(
        received[1].message,
        isA<LiveServerContent>().having(
          (content) => content.turnComplete,
          'turnComplete',
          isTrue,
        ),
      );
    },
  );
}
