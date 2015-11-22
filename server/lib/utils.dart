// Copyright (c) 2015, the Fletch project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

library entelechy_server.logging;

log(String str) => print("${new DateTime.now().toIso8601String()}: $str");
