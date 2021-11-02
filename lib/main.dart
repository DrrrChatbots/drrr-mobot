import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:core';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Cookie;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/services.dart';
import 'LmdBotAppEditor.dart';
import 'LmdBotAppGlobal.dart';
import 'LmdBotAppSetting.dart';
import 'LmdBotAppScript.dart';
import 'LmdBotAppSession.dart';

// icon
// https://fonts.google.com/icons?selected=Material+Icons

// local notification
// https://pub.dev/documentation/flutter_local_notifications/latest/flutter_local_notifications/FlutterLocalNotificationsPlugin-class.html

// https://web.archive.org/web/20210127075231/https://codingwithjoe.com/dart-fundamentals-isolates/

// TODO: clear all notification on app terminated
// TODO: try ajax on webView
Future main() async {

  //SharedPreferences prefs = await SharedPreferences.getInstance();
  //await prefs.clear();
  //return;

  WidgetsFlutterBinding.ensureInitialized();

  await AndroidAlarmManager.initialize();

  if (Platform.isAndroid) {
    await AndroidInAppWebViewController
        .setWebContentsDebuggingEnabled(true);
  }

  await initConfig();

  for(var sps in shrPrefSwitches) sps.start?.call(sps);

  runApp(new MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {

  final GlobalKey webViewKey = GlobalKey();
  final _messangerKey = GlobalKey<ScaffoldMessengerState>();

  InAppWebViewController? webViewController;
  final Completer<InAppWebViewController>
    _controller = Completer<InAppWebViewController>();

  InAppWebViewGroupOptions options = InAppWebViewGroupOptions(
      crossPlatform: InAppWebViewOptions(
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
      ),
      android: AndroidInAppWebViewOptions(
        useHybridComposition: true,
      ),
      ios: IOSInAppWebViewOptions(
        allowsInlineMediaPlayback: true,
      ));

  late PullToRefreshController pullToRefreshController;
  String url = "";
  double progress = 0;
  final urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    pullToRefreshController = PullToRefreshController(
      options: PullToRefreshOptions(
        color: Colors.black,
      ),
      onRefresh: () async {
        if (Platform.isAndroid) {
          webViewController?.reload();
        } else if (Platform.isIOS) {
          webViewController?.loadUrl(
              urlRequest: URLRequest(
                  url: await webViewController?.getUrl()));
        }
      },
    );
    setStateStack.add(() {setState((){});});
  }

  @override
  void dispose() { super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messangerKey,
      theme: ThemeData(
        primaryColor: Colors.black,
      ),
      routes: {
        '/botSettings': (context) => BotSettingsRoute(),
        '/userScripts': (context) => UserScriptsRoute(),
        '/userSessions': (context) => UserSessionsRoute(),
        '/editScripts': (context) => EditScriptsRoute(),
      },
      home: Scaffold(
          appBar: AppBar(
            title: const Text("LmdBotApp"),
            actions: <Widget>[
              NavigationControls(_controller.future),
              SampleMenu(_controller.future),
            ],
          ),
          body: SafeArea(
              child: Column(children: <Widget>[
                Expanded(
                  child: Stack(
                    children: [
                      InAppWebView(
                        key: webViewKey,
                        initialUrlRequest:
                        URLRequest(url: Uri.parse("https://drrr.com")),
                        initialOptions: options,
                        pullToRefreshController: pullToRefreshController,
                        onWebViewCreated: (controller) {
                          webViewController = controller;
                          _controller.complete(controller);
                          flutterLocalNotificationsPlugin.initialize(
                              flutterInitSettings,
                              onSelectNotification: (String? payload) async => {
                                setShrPrefSwitches(
                                    ShrPrefKey.values.firstWhere((e) => e.toString() == payload),
                                    false, webViewController)
                              });
                        },
                        initialUserScripts: UnmodifiableListView<UserScript>([
                          UserScript(
                              source: settingsCode(
                                  Scripts.enabledMergedCode()),
                              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END),
                          // UserScript(
                          //     source: "var bar = 2;",
                          //     injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END),
                        ]),
                        onLoadStart: (controller, url) async {
                          controller.addJavaScriptHandler(
                              handlerName: 'login',
                              callback: (args) => {
                                print("===================> do login"),
                                doLogin(args[0], args[1], args[2], controller, context),
                                jsonEncode("done")
                          });
                          controller.addJavaScriptHandler(
                              handlerName: 'exception',
                              callback: (args) => {
                                print("===================> show exception"),
                                _messangerKey.currentState!.showSnackBar(
                                  SnackBar(content: Text(args[0]))),
                                jsonEncode("reported")
                          });
                          setState(() {
                            this.url = url.toString();
                            urlController.text = this.url;
                          });
                        },
                        androidOnPermissionRequest: (controller, origin, resources) async {
                          return PermissionRequestResponse(
                              resources: resources,
                              action: PermissionRequestResponseAction.GRANT);
                        },
                        shouldOverrideUrlLoading: (controller, navigationAction) async {
                          var uri = navigationAction.request.url!;
                          var url = uri.toString();

                          if (![ "http", "https", "file", "chrome",
                            "data", "javascript", "about"].contains(uri.scheme)) {
                            if (await canLaunch(url)) {
                              // Launch the App
                              await launch(url);
                              // and cancel the request
                              return NavigationActionPolicy.CANCEL;
                            }
                          }

                          if (url.startsWith('https://drrr.com')){
                            if(['room', 'lounge', 'login']
                                .any((x) => uri.path.contains(x)))
                              return NavigationActionPolicy.ALLOW;
                            else if(uri.path == '/')
                              return NavigationActionPolicy.ALLOW;
                          }
                          await launch(url);
                          return NavigationActionPolicy.CANCEL;
                        },
                        onLoadStop: (controller, uri) async {
                          pullToRefreshController.endRefreshing();
                          setState(() {
                            this.url = uri.toString();
                            urlController.text = this.url;
                          });
                          shrPrefSwitches.forEach(
                                  (elt) => elt.ready?.call(this.webViewController, elt));
                          controller.evaluateJavascript(source: "console.log('================================>', \$)");
                        },
                        onLoadError: (controller, url, code, message) {
                          pullToRefreshController.endRefreshing();
                        },
                        onProgressChanged: (controller, progress) {
                          if (progress == 100) {
                            pullToRefreshController.endRefreshing();
                          }
                          setState(() {
                            this.progress = progress / 100;
                            urlController.text = this.url;
                          });
                        },
                        onUpdateVisitedHistory: (controller, url, androidIsReload) {
                          setState(() {
                            this.url = url.toString();
                            urlController.text = this.url;
                          });
                        },
                        onConsoleMessage: (controller, consoleMessage) {
                          print(consoleMessage);
                        },
                      ),
                      progress < 1.0
                          ? LinearProgressIndicator(value: progress)
                          : Container(),
                    ],
                  ),
                ),
              ]))),
      );
  }
}

class NavigationControls extends StatelessWidget {
  const NavigationControls(this._webViewControllerFuture);

  final Future<InAppWebViewController> _webViewControllerFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InAppWebViewController>(
      future: _webViewControllerFuture,
      builder:
          (BuildContext context, AsyncSnapshot<InAppWebViewController> snapshot) {
        final bool webViewReady =
            snapshot.connectionState == ConnectionState.done;
        final InAppWebViewController? controller = snapshot.data;

        return Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              onPressed: !webViewReady
                  ? null
                  : () async {
                if (await controller!.canGoBack()) {
                  controller.goBack();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No back history item")),
                  );
                  return;
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios),
              onPressed: !webViewReady
                  ? null
                  : () async {
                if (await controller!.canGoForward()) {
                  controller.goForward();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("No forward history item")),
                  );
                  return;
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.replay),
              onPressed: !webViewReady
                  ? null
                  : () {
                controller!.reload();
              },
            ),
          ],
        );
      },
    );
  }
}

enum MenuOptions {
  listCookies,
  clearCookies,
  addToCache,
  listCache,
  clearCache,
  botSettings,
  userScripts,
  userSessions,
  copySession,
  pasteSession,
  about,
}

class SampleMenu extends StatelessWidget {

  SampleMenu(this.controller);

  final Future<InAppWebViewController> controller;


  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InAppWebViewController>(
      future: controller,
      builder:
          (BuildContext context, AsyncSnapshot<InAppWebViewController> controller) {
        return PopupMenuButton<MenuOptions>(
          onSelected: (MenuOptions value) {
            switch (value) {
              case MenuOptions.copySession:
                _onCopySession(context);
                break;
              case MenuOptions.pasteSession:
                _onPasteSession(controller.data, context);
                break;
              case MenuOptions.about:
                _onAbout(context);
                break;
              case MenuOptions.listCookies:
                _onListCookies(controller.data, context);
                break;
              case MenuOptions.clearCookies:
                _onClearCookies(context);
                break;
              case MenuOptions.addToCache:
                _onAddToCache(controller.data, context);
                break;
              case MenuOptions.listCache:
                _onListCache(controller.data, context);
                break;
              case MenuOptions.clearCache:
                _onClearCache(controller.data, context);
                break;
              case MenuOptions.botSettings:
                _onBotSettings(controller.data, context);
                break;
              case MenuOptions.userScripts:
                _onUserScripts(controller.data, context);
                break;
              case MenuOptions.userSessions:
                _onUserSessions(controller.data, context);
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuItem<MenuOptions>>[
            // PopupMenuItem<MenuOptions>(
            //   value: MenuOptions.showUserAgent,
            //   child: const Text('Show user agent'),
            //   enabled: controller.hasData,
            // ),
            // const PopupMenuItem<MenuOptions>(
            //   value: MenuOptions.listCookies,
            //   child: Text('List cookies'),
            // ),
            // const PopupMenuItem<MenuOptions>(
            //   value: MenuOptions.clearCookies,
            //   child: Text('Clear cookies'),
            // ),
            // const PopupMenuItem<MenuOptions>(
            //   value: MenuOptions.addToCache,
            //   child: Text('Add to cache'),
            // ),
            // const PopupMenuItem<MenuOptions>(
            //   value: MenuOptions.listCache,
            //   child: Text('List cache'),
            // ),
            // const PopupMenuItem<MenuOptions>(
            //   value: MenuOptions.clearCache,
            //   child: Text('Clear cache'),
            // ),
            const PopupMenuItem<MenuOptions>(
              value: MenuOptions.userScripts,
              child: Text('Scripts'),
            ),
            const PopupMenuItem<MenuOptions>(
              value: MenuOptions.botSettings,
              child: Text('Settings'),
            ),
            const PopupMenuItem<MenuOptions>(
              value: MenuOptions.userSessions,
              child: Text('Sessions'),
            ),
            // const PopupMenuItem<MenuOptions>(
            //   value: MenuOptions.copySession,
            //   child: Text('Copy Session'),
            // ),
            // const PopupMenuItem<MenuOptions>(
            //   value: MenuOptions.pasteSession,
            //   child: Text('Paste Session'),
            // ),
            const PopupMenuItem<MenuOptions>(
              value: MenuOptions.about,
              child: Text('About Developer'),
            ),
          ],
        );
      },
    );
  }

  // void _onShowUserAgent(
  //     InAppWebViewController? controller, BuildContext context) async {
  //   // Send a message with the user agent string to the Toaster JavaScript channel we registered
  //   // with the WebView.
  //   controller!.evaluateJavascript(source:
  //       'alert("User Agent: " + navigator.userAgent);');
  // }

  void _onAbout(BuildContext context) async {
    // Send a message with the user agent string to the Toaster JavaScript channel we registered
    // with the WebView.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('lambda.catノ#L/CaT//Hsk\na.k.a 浪打貓ノ，也有人叫我蘭達\n約於 2017 秋開始出沒於 drrr.com。\nmail: lambdacat.tw@gmail.com\n'),
        ],
      ),
    ));
  }

  void _onCopySession(BuildContext context) async {
    // Send a message with the user agent string to the Toaster JavaScript channel we registered
    // with the WebView.
    var cookie = 'No session, login first';
    if(botClient.cookie.length != 0){
      cookie = sessionCookieValue(botClient.cookie);
      Clipboard.setData(ClipboardData(text: cookie));
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Session: $cookie'),
        ],
      ),
    ));
  }

  void _onPasteSession(InAppWebViewController? controller, BuildContext context) async {
    // Send a message with the user agent string to the Toaster JavaScript channel we registered
    // with the WebView.
    var cookie = 'No session, login first';
    ClipboardData? data = await Clipboard.getData('text/plain');
    final _textFieldController = TextEditingController();
    // if(botClient.cookie.length != 0){
    //   cookie = botClient.cookie;
    //   Clipboard.setData(ClipboardData(text: cookie));
    // }
    showDialog(
        context: context,
        builder: (BuildContext context){
          var valueText = "";
          return AlertDialog(
            title: Text('Input new session'),
            content: TextField(
              autofocus: true,
              onChanged: (value) {
                //setState(() {
                valueText = value;
                //});
              },
              controller: _textFieldController..text = '$valueText',
              decoration: InputDecoration(hintText: "drrr-session-1="),
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () async {
                    _textFieldController.text = "";
                    Navigator.pop(context);
                  },
                  child: Text("Cancel", style: TextStyle(color: Colors.red))
              ),
              TextButton(
                  onPressed: () async {
                    await botClient.doLoadCookie(
                        sessionCookie(_textFieldController.text),
                        controller, true, context);
                    Navigator.pop(context);
                  },
                  child: Text("Paste", style: TextStyle(color: Colors.green))
              ),
            ],
          );
        }
    );

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Not impl yet'),
        ],
      ),
    ));
  }

  void _onListCookies(
      InAppWebViewController? controller, BuildContext context) async {
    final String cookies =
    await controller!.evaluateJavascript(source: 'document.cookie');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('Cookies:'),
          _getCookieList(cookies),
        ],
      ),
    ));
  }

  void _onAddToCache(InAppWebViewController? controller, BuildContext context) async {
    await controller!.evaluateJavascript(
        source: 'caches.open("test_caches_entry"); localStorage["test_localStorage"] = "dummy_entry";');
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Added a test entry to cache.'),
    ));
  }

  void _onListCache(InAppWebViewController? controller, BuildContext context) async {
    await controller!.evaluateJavascript(source: 'caches.keys()'
        '.then((cacheKeys) => JSON.stringify({"cacheKeys" : cacheKeys, "localStorage" : localStorage}))'
        '.then((caches) => alert(caches))');
  }

  void _onClearCache(InAppWebViewController? controller, BuildContext context) async {
    await controller!.clearCache();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Cache cleared."),
    ));
  }

  void _onClearCookies(BuildContext context) async {
    // await cookieManager.deleteAllCookies();
    // String message = 'There were cookies. Now, they are gone!';
    // ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    //   content: Text(message),
    // ));
  }

  void _onBotSettings(InAppWebViewController? controller, BuildContext context) async {
    Navigator.pushNamed(
      context,
      '/botSettings',
      arguments: BotArgs(controller),
    );
  }

  void _onUserScripts(InAppWebViewController? controller, BuildContext context) async {
    // TODO modify this
    Navigator.pushNamed(
      context,
      '/userScripts',
      arguments: BotArgs(controller),
    );
  }

  void _onUserSessions(InAppWebViewController? controller, BuildContext context) async {
    // TODO modify this
    Navigator.pushNamed(
      context,
      '/userSessions',
      arguments: BotArgs(controller),
    );
  }

  Widget _getCookieList(String cookies) {
    if (cookies == '""') { return Container(); }
    final List<String> cookieList = cookies.split(';');
    final Iterable<Text> cookieWidgets =
    cookieList.map((String cookie) => Text(cookie));
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: cookieWidgets.toList(),
    );
  }
}