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
import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

/// Runs a local peer in a VM isolate for both VM and browser tests.
Future<void> hybridMain(StreamChannel<Object?> channel, String mode) async {
  if (mode == 'stall') {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    channel.sink.add('ws://${server.address.address}:${server.port}');
    final sockets = <Socket>[];
    final subscription = server.listen((socket) {
      sockets.add(socket);
      var headers = '';
      var receivedUpgrade = false;
      socket.listen(
        (bytes) {
          headers += utf8.decode(bytes);
          if (!receivedUpgrade && headers.contains('\r\n\r\n')) {
            receivedUpgrade = true;
            channel.sink.add('upgrade received');
          }
        },
        onDone: () {
          channel.sink.add('connection closed');
          socket.destroy();
        },
      );
    });
    await channel.stream.drain<void>();
    for (final socket in sockets) {
      socket.destroy();
    }
    await subscription.cancel();
    await server.close();
    return;
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  channel.sink.add('ws://${server.address.address}:${server.port}');
  final connected = Completer<WebSocket>();
  final subscription = server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    connected.complete(socket);
    socket.listen((frame) {
      channel.sink.add(jsonDecode(frame as String));
    }, onDone: () => unawaited(socket.close()));
  });
  await channel.stream.first;
  final socket = await connected.future;
  socket.add(jsonEncode({'setupComplete': {}}));
  socket.add(
    utf8.encode(
      jsonEncode({
        'serverContent': {'turnComplete': true},
      }),
    ),
  );
  await socket.close();
  await subscription.cancel();
  await server.close(force: true);
}
