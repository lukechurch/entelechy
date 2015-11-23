// Copyright (c) 2015, the Fletch project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

library entelechy_ui;

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:http/browser_client.dart';
import 'package:http/http.dart';

import 'package:entelechy_ui/editing/editor.dart';
import 'package:entelechy_ui/editing/editor_codemirror.dart';
import 'package:entelechy_ui/editing/completion.dart';
import 'package:entelechy_ui/editing/keys.dart';
import 'package:entelechy_ui/services/dartservices.dart';

const serverURL = 'https://dart-services.appspot.com/';
const HOST = "localhost:11001";
Keys keys = new Keys();

Editor editor;

void main() {
  DivElement container = querySelector('#container');
  DivElement editorElement = container.querySelector('.code');

  EditorFactory editorFactory = codeMirrorFactory;

  // Set up the editing area.
  editor = editorFactory.createFromElement(editorElement);
  editorElement.querySelector('.CodeMirror')
    ..attributes['flex'] = ''
    ..style.height = '${editorElement.clientHeight}px';
  editor.resize();
  editor.mode = 'dart';

  editorElement.onKeyUp.listen((e) {
    _handleAutoCompletion(editor, e);
  });

  var client = new SanitizingBrowserClient();
  DartservicesApi dartServices =
      new DartservicesApi(client, rootUrl: serverURL);

  editorFactory.registerCompleter(
      'dart', new DartCompleter(dartServices, editor.document));

  // No actions yet for Save and Run.
  keys.bind(['ctrl-s'], () {}, "Save", hidden: true);
  keys.bind(['ctrl-enter'], () {}, "Run");

  keys.bind(['alt-enter', 'ctrl-1'], () {
    editor.showCompletions(onlyShowFixes: true);
  }, "Quick fix");

  keys.bind(['ctrl-space', 'macctrl-space'], () {
    editor.showCompletions();
  }, "Completion");

  // The startup and update buttons in the top right corner of the editor.
  container
      .querySelector('#startupbutton')
      .onClick
      .listen((e) => handleRun(editor.document.value, 'startup'));
  container
      .querySelector('#updatebutton')
      .onClick
      .listen((e) => handleRun(editor.document.value, 'update'));
}

_handleAutoCompletion(Editor editor, KeyboardEvent e) {
  if (editor.hasFocus) {
    if (e.keyCode == KeyCode.PERIOD) {
      editor.showCompletions(autoInvoked: true);
    }
  }
  if (editor.completionActive || !editor.hasFocus) {
    return;
  }

  RegExp exp = new RegExp(r"[A-Z]");
  if (exp.hasMatch(new String.fromCharCode(e.keyCode))) {
    editor.showCompletions(autoInvoked: true);
  }
}

// When sending requests from a browser we sanitize the headers to avoid
// client side warnings for any blacklisted headers.
class SanitizingBrowserClient extends BrowserClient {
  // The below list of disallowed browser headers is based on list at:
  // http://www.w3.org/TR/XMLHttpRequest/#the-setrequestheader()-method
  static const List<String> disallowedHeaders = const [
    'accept-charset',
    'accept-encoding',
    'access-control-request-headers',
    'access-control-request-method',
    'connection',
    'content-length',
    'cookie',
    'cookie2',
    'date',
    'dnt',
    'expect',
    'host',
    'keep-alive',
    'origin',
    'referer',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
    'user-agent',
    'via'
  ];

  /// Strips all disallowed headers for an HTTP request before sending it.
  Future<StreamedResponse> send(BaseRequest request) {
    for (String headerKey in disallowedHeaders) {
      request.headers.remove(headerKey);
    }

    // Replace 'application/json; charset=utf-8' with text/plain. This will
    // avoid the browser sending an OPTIONS request before the actual POST (and
    // introducing an additional round trip between the client and the server).
    request.headers['Content-Type'] = 'text/plain; charset=utf-8';

    return super.send(request);
  }
}


/// Sends the [code] to the server, using the given [action], which is the
/// relative path to which to send the request.
/// Expects a response from the server of the form:
/// {
///   "output": "update successful",
///   "breakpoint": '21',
///   "line-infos": [
///     {'line-number': '41', 'line-info': 'foo'},
///     {'line-number': '12', 'line-info': 'bar baz!'}
///   ]
/// }
Future handleRun(String code, String action) async {
  var url = "http://${HOST}/${action}";
  var msg = {'src': code};
  var msgPacked = UTF8.encode(JSON.encode(msg));

  var req = new HttpRequest()..open("POST", url);
  req.send(msgPacked);

  req.onLoad.listen((event) {
      print ("onLoad - listen");
      print ("event.target.toString(): ${event.target.toString()}");
      print (event.target.responseText);



      Map answer = JSON.decode(event.target.responseText);
      print ("answer $answer");

      DivElement container = querySelector('#container');
      DivElement resultElement = container.querySelector('.result');
      PreElement result = resultElement.querySelector('pre');
      result.text = answer['output'];

      editor.clearBreakpoints();
      if (answer.containsKey('breakpoint')) {
        editor.setBreakpoint(answer['breakpoint']);
      }
      editor.clearLineInfos();
      if (answer.containsKey('line-infos')) {
        List infos = answer['line-infos'];
        infos.forEach((Map info) => editor.setLineInfo(
            int.parse(info['line-number']), info['line-info']));
      }
    });
}
