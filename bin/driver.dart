// Copyright (c) 2015, the Fletch project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

import 'dart:async';
import 'dart:io' as io;
import 'dart:convert' as convert;
import 'package:entelechy/utils.dart';

main(List<String> args) async {
  if (args.length != 1) {
    print ("Test driver for fletch server");
    print ("Usage: dart driver.dart [path_to_sample_target]");
  }

  String path = args[0];
  String src = new io.File(path).readAsStringSync();

  await startup(src);
  await update(src);

  print ("call done");
}

Future startup(String src) async {
  var res = await send ("/startup", convert.JSON.encode({"src" :src}));
  log (await readResponse(res));
}

Future update(String src) async {
  var res = await send ("/update", convert.JSON.encode({"src" :src}));
  log (await readResponse(res));
}


Future<String> readResponse(io.HttpClientResponse res) {
  StringBuffer sb = new StringBuffer();
  Completer completer = new Completer();
  res.transform(convert.UTF8.decoder).listen((dataString) {
    sb.write(dataString);
  }, onDone: () {
    completer.complete(sb.toString());
  });
  return completer.future;
}

Future<io.HttpClientResponse> send (String path, String message) async {
  var bytes = convert.UTF8.encode(message);

  var client = new io.HttpClient();
  var req = await client.post("localhost", 11001, path);
  req.add(bytes);
  print ("byte added");
  // await req.flush();
  // print ("flush complete");
  var res = await req.close();
  print ("close complete");

  return res;
}
