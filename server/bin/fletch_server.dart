// Copyright (c) 2015, the Fletch project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:entelechy_server/utils.dart';

const HOST = "127.0.0.1";
const PORT = 11001;

String targetPath;
String fletchPath;

void main(List<String> args) {
  if (args.length != 2) {
    print ("Fletch Server, proxies select commands over a network connection");
    print ("Usage dart fletch_server.dart [path_to_fletch] [path_to_test_file]");
    print ("Run this from the root of the fletch checkout");
    exit(1);
  }

  fletchPath = args[0];
  targetPath = args[1];

  HttpServer.bind(HOST, PORT).then((server) {
    server.listen((HttpRequest request) {
      log("${request.method}: ${request.uri}");

      switch (request.method) {
        case "GET":
          handleGet(request);
          break;
        case "POST":
          handlePost(request);
          break;
        case "OPTIONS":
          handleOptions(request);
          break;
        default:
          defaultHandler(request);
      }

      log("Request handling complete");
    }, onError: printError);

    log("Listening for GET and POST on http://$HOST:$PORT");
  }, onError: printError);
}

void handleGet(HttpRequest req) {
  HttpResponse res = req.response;
  addCorsHeaders(res);

  res.write("Liveness is entelechy\n");
  res.write("State: $_systemState\n");

  res.close();
}

void handlePost(HttpRequest req) {
  HttpResponse res = req.response;
  addCorsHeaders(res);

  String path = req.uri.path;
  List<int> dataBytes = [];
  var jsonMap = {};

  req.listen((List<int> buffer) async {
    dataBytes.addAll(buffer);
  }, onDone: () async {
    jsonMap = JSON.decode(UTF8.decode(dataBytes));
    switch (path) {
      case "/update":
        log("Calling update $jsonMap");
        String result = await update(jsonMap['src']);
        res.write(result);
        break;
      case "/startup":
        log("Calling update $jsonMap");
        String result = await startup(jsonMap['src']);
        res.write(result);
        break;
      case "/":
      default:
        log("Path not found: $path");
        res.statusCode = 404;
        break;
    }
    res.close();
    log("Request handling done");
  });
}

/**
 * Add Cross-site headers to enable accessing this server from pages
 * not served by this server
 *
 * See: http://www.html5rocks.com/en/tutorials/cors/
 * and http://enable-cors.org/server.html
 */
void addCorsHeaders(HttpResponse res) {
  res.headers.add("Access-Control-Allow-Origin", "*");
  res.headers.add("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  res.headers.add("Access-Control-Allow-Headers",
      "Origin, X-Requested-With, Content-Type, Accept");
}

void handleOptions(HttpRequest req) {
  log("handleOptions");
  HttpResponse res = req.response;
  addCorsHeaders(res);
  print("${req.method}: ${req.uri.path}");
  res.statusCode = HttpStatus.NO_CONTENT;
  res.close();
}

void defaultHandler(HttpRequest req) {
  HttpResponse res = req.response;
  addCorsHeaders(res);
  res.statusCode = HttpStatus.NOT_FOUND;
  res.write("Not found: ${req.method}, ${req.uri.path}");
  res.close();
}

void printError(error) => print(error);

Future<String> update(String src) async {
  new File(targetPath).writeAsStringSync(src);

  await _runFletchCommnand("compile --fatal-incremental-failures $targetPath in session Live");
  await _runFletchCommnand("debug apply in session Live");
  String result = await _runFletchCommnand("debug restart in session Live");
  return result;
}

Future<String> startup(String src) async {
  new File(targetPath).writeAsStringSync(src);

  await _runFletchCommnand("quit");
  String result = await _runFletchCommnand("run $targetPath in session Live");
  return result;
}

enum State {
  NOT_STARTED, // No known script
  READY // Ready for a live update
}

State _systemState = State.NOT_STARTED;


Future<String> _runFletchCommnand(String command) async {
  log ("Calling Fletch: $command");
  var processResult =
      await Process.run(fletchPath, command.split(" "));

  log ("stdOut: ${processResult.stdout}");
  log ("stdErr: ${processResult.stderr}");

  return new Future.value(processResult.stdout);
}
