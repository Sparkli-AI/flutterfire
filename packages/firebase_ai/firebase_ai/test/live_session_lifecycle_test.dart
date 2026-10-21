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

import 'package:firebase_ai/src/live_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _TestWebSocketSink implements WebSocketSink {
  int closeCalls = 0;
  Future<void> Function()? onClose;

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    closeCalls++;
    return onClose?.call() ?? Future<void>.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestWebSocketChannel implements WebSocketChannel {
  _TestWebSocketChannel({FutureOr<void> Function()? onCancel})
      : events = StreamController<Object?>(onCancel: onCancel);

  final StreamController<Object?> events;

  @override
  final _TestWebSocketSink sink = _TestWebSocketSink();

  @override
  Stream<Object?> get stream => events.stream;

  @override
  int? get closeCode => null;

  Future<void> dispose() async {
    await sink.close();
    await events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('closes the socket and receive stream when cancellation fails',
      () async {
    final socket = _TestWebSocketChannel(
      onCancel: () => Future<void>.error(StateError('Cancellation failed.')),
    );
    final session = LiveSession.forTesting(socket);
    addTearDown(socket.dispose);
    final received = session.receive().drain<void>();
    await Future<void>.delayed(Duration.zero);

    await session.close().timeout(const Duration(seconds: 2));

    expect(socket.sink.closeCalls, 1);
    await received.timeout(const Duration(seconds: 2));
  });

  test('closes the socket without waiting for a paused receive stream',
      () async {
    final socket = _TestWebSocketChannel();
    final session = LiveSession.forTesting(socket);
    addTearDown(socket.dispose);
    final received = session.receive().listen((_) {});
    addTearDown(received.cancel);
    await Future<void>.delayed(Duration.zero);
    received.pause();

    await session.close().timeout(const Duration(seconds: 2));

    expect(socket.sink.closeCalls, 1);
  });

  test('bounds cleanup when socket closure stalls', () async {
    final socket = _TestWebSocketChannel();
    final closed = Completer<void>();
    socket.sink.onClose = () => closed.future;
    final session = LiveSession.forTesting(socket);
    addTearDown(socket.dispose);
    addTearDown(closed.complete);

    await session.close().timeout(const Duration(seconds: 2));

    expect(socket.sink.closeCalls, 1);
  });
}
