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

import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens a WebSocket, aborting the browser connection attempt on timeout.
Future<WebSocketChannel> connectWebSocket({
  required Uri uri,
  required Map<String, String> headers,
  required Duration timeout,
}) async {
  final channel = HtmlWebSocketChannel.connect(uri);
  try {
    await channel.ready.timeout(timeout);
    return channel;
  } on Object {
    // Closing the channel sink waits for readiness; close the attempt itself.
    channel.innerWebSocket.close();
    rethrow;
  }
}
