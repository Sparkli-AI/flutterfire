// Copyright 2025 Google LLC
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

import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens a WebSocket, aborting its owned HTTP request if readiness times out.
Future<WebSocketChannel> connectWebSocket({
  required Uri uri,
  required Map<String, String> headers,
  required Duration timeout,
}) async {
  final client = HttpClient();
  var connected = false;
  try {
    final channel = IOWebSocketChannel.connect(
      uri,
      headers: headers,
      customClient: client,
    );
    await channel.ready.timeout(timeout);
    connected = true;
    return channel;
  } finally {
    // A successful upgrade detaches its socket from the HTTP client.
    client.close(force: !connected);
  }
}
