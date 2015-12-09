library playground;

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:google_diff_match_patch/diff_match_patch.dart' as dmp;
import 'package:http/browser_client.dart';
import 'package:http/http.dart';

import 'package:entelechy_ui/editing/editor.dart';
import 'package:entelechy_ui/editing/editor_codemirror.dart';
import 'package:entelechy_ui/editing/completion.dart';
import 'package:entelechy_ui/editing/keys.dart';
import 'package:entelechy_ui/services/dartservices.dart';

const serverURL = 'https://dart-services.appspot.com/';
const HOST = "localhost:11001";
final Duration serviceCallTimeout = new Duration(seconds: 10);

Playground get playground => _playground;
Keys get keys => _keys;
DartservicesApi get dartServices => _dartServices;

Playground _playground;
Keys _keys;
DartservicesApi _dartServices;

void init() {
  _keys = new Keys();
  _dartServices =
      new DartservicesApi(new SanitizingBrowserClient(), rootUrl: serverURL);

  _playground = new Playground();
}

class Playground {
  Editor editor;

  bool _startupRan = false;
  bool _buttonsDisabled = false;

  String previousSource = '';
  bool justUpdated = false;

  Future _analysisRequest;

  Playground() {
    html.DivElement container = html.querySelector('#container');
    html.DivElement editorElement = container.querySelector('.code');

    EditorFactory editorFactory = codeMirrorFactory;

    // Set up the editing area.
    editor = editorFactory.createFromElement(editorElement);
    editorElement.querySelector('.CodeMirror')
      ..attributes['flex'] = ''
      ..style.height = '${editorElement.clientHeight}px';
    editor.resize();
    editor.mode = 'dart';

    editorElement.onKeyUp.listen((e) {
      _clearDiff();
      _updateDiff();
      _handleAutoCompletion(editor, e);
      _performAnalysis();
    });

    editorFactory.registerCompleter(
        'dart', new DartCompleter(dartServices, editor.document));

    keys.bind(['ctrl-s', 'ctrl-r'], () {
      // Don't run if the buttons are diabled (sign that the code has errors).
      if (_buttonsDisabled) {
        return;
      }
      // By default, run the update. However, if startup has never been run, then
      // we run it instead.
      var action = 'update';
      if (!_startupRan) {
        action = 'startup';
        _startupRan = true;
      }
      _handleRun(dartSource, action);
    }, "Save", hidden: true);

    keys.bind(['alt-enter', 'ctrl-1'], () {
      editor.showCompletions(onlyShowFixes: true);
    }, "Quick fix");

    keys.bind(['ctrl-space', 'macctrl-space'], () {
      editor.showCompletions();
    }, "Completion");

    // The startup and update buttons in the top right corner of the editor.
    container.querySelector('#startupbutton').onClick.listen((e) {
      // Don't run if the buttons are diabled (sign that the code has errors).
      if (_buttonsDisabled) {
        return;
      }
      _handleRun(dartSource, 'startup');
      _startupRan = true;
    });
    container.querySelector('#updatebutton').onClick.listen((e) {
      // Don't run if the buttons are diabled (sign that the code has errors).
      if (_buttonsDisabled) {
        return;
      }
      _handleRun(dartSource, 'update');
    });
  }

  String get dartSource => editor.document.value;
  Document get dartDocument => editor.document;

  _handleAutoCompletion(Editor editor, html.KeyboardEvent e) {
    if (editor.hasFocus) {
      if (e.keyCode == html.KeyCode.PERIOD) {
        editor.showCompletions(autoInvoked: true);
      }
    }
    if (editor.completionActive || !editor.hasFocus) {
      return;
    }

    // TODO: I don't know what this is trying to achieve, but commenting it out
    // stops odd behaviour like triggering code completion on C&P. However, in
    // Dartpad, this code work fine, so there must be something else missing.
//  if (editor.hasFocus) {
//    RegExp exp = new RegExp(r"[A-Z]");
//    if (exp.hasMatch(new String.fromCharCode(e.keyCode))) {
//      editor.showCompletions(autoInvoked: true);
//    }
//  }
  }

  /// Perform static analysis of the source code. Return whether the code
  /// analyzed cleanly (had no errors or warnings).
  /// From Dartpad: https://github.com/dart-lang/dart-pad/blob/master/lib/playground.dart
  Future<bool> _performAnalysis() {
    SourceRequest input = new SourceRequest()..source = dartSource;

    Future request = dartServices.analyze(input).timeout(serviceCallTimeout);
    _analysisRequest = request;

    return request.then((AnalysisResults result) {
      // Discard if we requested another analysis.
      if (_analysisRequest != request) return false;

      // Discard if the document has been mutated since we requested analysis.
      if (input.source != dartSource) return false;

      _displayIssues(result.issues);

      bool hasErrors = result.issues.any((issue) => issue.kind == 'error');
      bool hasWarnings = result.issues.any((issue) => issue.kind == 'warning');

      _updateRunButton(hasErrors: hasErrors, hasWarnings: hasWarnings);

      return hasErrors == false && hasWarnings == false;
    }).catchError((e) {
      dartDocument.setAnnotations([]);
      _updateRunButton();
    });
  }

  void _displayIssues(List<AnalysisIssue> issues) {
    // TODO: Implement.
  }

  void _updateRunButton({bool hasErrors, bool hasWarnings}) {
    if (hasErrors != null && hasErrors) {
      html.querySelectorAll('.button').classes.add('disabled');
      _buttonsDisabled = true;
    } else {
      html.querySelectorAll('.button').classes.remove('disabled');
      _buttonsDisabled = false;
    }
  }

  void _updateDiff() {
    dmp.DiffMatchPatch differ = new dmp.DiffMatchPatch();
    List<dmp.Diff> diffs = differ.diff_main(previousSource, dartSource);
    var line = 0;
    var ch = 0;
    for (dmp.Diff diff in diffs) {
      switch (diff.operation) {
        case dmp.DIFF_INSERT:
          List<String> lines = diff.text.split('\n');
          for (String ln in lines) {
            int skip = ln.length - ln.trimLeft().length;
            Position from = new Position(line, ch + skip);
            Position to = new Position(line, ch + ln.length);
            colour(from, to, 'insert-code');
            if (lines.last != ln) {
              line++; ch = 0;
            } else {
              ch = ln.length;
            }
          }
          break;
        case dmp.DIFF_EQUAL:
          List<String> lines = diff.text.split('\n');
          line = line + lines.length - 1;
          ch = lines.last.length;
          break;
        case dmp.DIFF_DELETE:
//          List<String> lines = diff.text.split('\n');
//          line = line + lines.length - 1;
//          ch = lines.last.length;
          break;
      }
    }
  }

  void _clearDiff() {
    editor.document.clearText();
  }

  void colour(Position from, Position to, String colour) {
    editor.document.colorText(from, to, 'insert-code');
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
  Future _handleRun(String code, String action) async {
    var url = "http://${HOST}/${action}";
    var msg = {'src': code};
    var msgPacked = UTF8.encode(JSON.encode(msg));

    // Send the code to the server
    var req = new html.HttpRequest()..open("POST", url);
    req.send(msgPacked);

    // Add a throbber overlaying the results panel until we receive the response
    // from the server.
    html.querySelector('#results-loader').style.visibility = 'visible';

    // Compute the diff from the previous code that was sent to the server.
    _clearDiff();
    justUpdated = true;
    previousSource = dartSource;

    req.onLoad.listen((event) {
      print("onLoad - listen");
      print("event.target.toString(): ${event.target.toString()}");
      print(event.target.responseText);

      Map answer = JSON.decode(event.target.responseText);
      print("answer $answer");

      html.DivElement container = html.querySelector('#container');
      html.DivElement resultElement = container.querySelector('.result');
      html.PreElement result = resultElement.querySelector('pre');
      result.text = answer['output'];

      // Remove the throbber.
      html.querySelector('#results-loader').style.visibility = 'hidden';

      editor.clearBreakpoints();
      if (answer.containsKey('breakpoint')) {
        editor.setBreakpoint(answer['breakpoint']);
      }
      editor.clearLineInfos();
      if (answer.containsKey('line-infos')) {
        List infos = answer['line-infos'];
        infos.forEach((Map info) =>
            editor.setLineInfo(info['line-number'], info['line-info']));
      }
    });
  }
}

/// When sending requests from a browser we sanitize the headers to avoid
/// client side warnings for any blacklisted headers.
/// From Dartpad: https://github.com/dart-lang/dart-pad/blob/master/lib/modules/dartservices_module.dart
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
