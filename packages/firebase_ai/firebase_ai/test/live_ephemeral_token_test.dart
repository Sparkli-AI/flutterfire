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

// ignore_for_file: close_sinks

import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/src/error.dart';
import 'package:firebase_ai/src/live_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _credentialMessage =
    'wss://example.invalid/?access_token=auth_tokens/test-secret-123';

class _FakeWebSocketSink implements WebSocketSink {
  bool failSend = false;
  bool failClose = false;

  @override
  void add(dynamic data) {
    if (failSend) throw StateError(_credentialMessage);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (failClose) throw StateError(_credentialMessage);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWebSocketChannel implements WebSocketChannel {
  final events = StreamController<Object?>();

  @override
  final _FakeWebSocketSink sink = _FakeWebSocketSink();

  @override
  Stream get stream => events.stream;

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  Future<void> get ready async {}

  @override
  String? get protocol => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('rejects API keys and invalid models without echoing arguments',
      () async {
    await expectLater(
      LiveSession.connectWithEphemeralToken(
          token: 'test-secret-123', model: 'test-model'),
      throwsA(isArgumentError.having((error) => '$error', 'safe message',
          isNot(contains('test-secret-123')))),
    );
    await expectLater(
      LiveSession.connectWithEphemeralToken(
          token: 'auth_tokens/test-secret-123',
          model: 'bad?secret=test-secret-123'),
      throwsA(isArgumentError.having((error) => '$error', 'safe message',
          isNot(contains('test-secret-123')))),
    );
  });

  group('ephemeral sessions', () {
    late _FakeWebSocketChannel socket;
    late LiveSession session;
    final safeError = throwsA(isA<LiveWebSocketClosedException>().having(
      (error) => error.message,
      'safe message',
      'The Live API connection failed.',
    ));

    setUp(() {
      socket = _FakeWebSocketChannel();
      session = LiveSession.forTesting(socket, useEphemeralToken: true);
    });
    tearDown(() async {
      await session.close();
      await socket.events.close();
    });

    for (final source in ['socket', 'server']) {
      test('sanitizes $source errors on the shared receive stream', () async {
        final receivedError = expectLater(session.receive().first, safeError);
        // receive() is an async generator; let its subscription attach.
        await Future<void>.delayed(Duration.zero);
        if (source == 'socket') {
          socket.events.addError(StateError(_credentialMessage));
        } else {
          socket.events.add(jsonEncode({
            'error': {
              'code': 403,
              'status': 'PERMISSION_DENIED',
              'message': _credentialMessage,
            },
          }));
        }
        await receivedError;
      });
    }

    test('sanitizes send failures', () async {
      socket.sink.failSend = true;
      await expectLater(session.send(turnComplete: true), safeError);
    });

    test('sanitizes socket close details', () async {
      socket.closeCode = 1008;
      socket.closeReason = _credentialMessage;
      await expectLater(
        session.send(turnComplete: true),
        throwsA(isA<LiveWebSocketClosedException>().having(
          (error) => error.message,
          'safe message',
          'The Live API connection closed.',
        )),
      );
    });

    test('requires a fresh token to reconnect', () async {
      await expectLater(session.resumeSession(), throwsStateError);
    });

    test('tolerates socket close failures', () async {
      socket.sink.failClose = true;
      await expectLater(session.close(), completes);
      socket.sink.failClose = false;
    });
  });
}
