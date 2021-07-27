import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:core';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// icon
// https://fonts.google.com/icons?selected=Material+Icons

// local notification
// https://pub.dev/documentation/flutter_local_notifications/latest/flutter_local_notifications/FlutterLocalNotificationsPlugin-class.html

// https://web.archive.org/web/20210127075231/https://codingwithjoe.com/dart-fundamentals-isolates/
Isolate? isolate;

List<void Function()> setStateStack = [];

FlutterLocalNotificationsPlugin
  flutterLocalNotificationsPlugin
    = new FlutterLocalNotificationsPlugin();

var flutterInitSettings = new InitializationSettings(
    android: new AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: new IOSInitializationSettings());

void showNotification() async {
  var android = new AndroidNotificationDetails(
    'cancel', 'KeepRoom', 'KeepRoomOperation',
    priority: Priority.high, importance: Importance.max,
    autoCancel: false, ongoing: false,  playSound: false,
    onlyAlertOnce: true,
    // because I cannot use onDestroy, so I can't set ongoing as true
  );
  var iOS = new IOSNotificationDetails(presentSound: false);
  var platform = new NotificationDetails(android: android, iOS: iOS);
  await flutterLocalNotificationsPlugin.show(
      NoteID.cancelKeepRoom.index, 'Dollars keep alive',
      'Click to undo keep', platform, payload: ShrPrefKey.keepAlive.toString());
}

enum ShrPrefKey {
  alwaysMe,
  keepAlive,
  keepRoom,
}

class ShrPrefSwitch {
  bool value = false;
  ShrPrefKey key;
  String title;
  final Icon icon;

  // consider template function
  void Function(bool, InAppWebViewController?, ShrPrefSwitch) change;

  // consider template function
  void Function(InAppWebViewController?, ShrPrefSwitch data) onDocLoaded;

  // consider template function
  void onChanged(bool _value, InAppWebViewController? webview, ShrPrefSwitch data) {
    this.value = _value;
    saveSwitchState(key.toString(), value);
    change(value, webview, data);
  }

  ShrPrefSwitch(this.key, this.title, this.icon, this.onDocLoaded, this.change);

  init(commitView) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    this.value = prefs.getBool(this.key.toString()) ?? false;
    commitView();
  }
}

void setShrPrefSwitches(key, value, webview){
  var dep = shrPrefSwitches.firstWhere(
          (s) => s.key == key);
  if(dep.value == value) return;
  dep.value = value;
  dep.onChanged(value, webview, dep);
  setStateStack.last();
}

void start(onData, onDone) async {
  if (isolate != null)  return;
  ReceivePort receivePort= ReceivePort(); //port for this main isolate to receive messages.
  isolate = await Isolate.spawn(runTimer, receivePort.sendPort);
  receivePort.listen(onData, onDone: onDone);
}

void stop() {
  if (isolate != null) {
    isolate!.kill(priority: Isolate.immediate);
    isolate = null;
  }
  print("stopped");
}
void runTimer(SendPort sendPort) {
  int counter = 0;
  Timer.periodic(new Duration(seconds: 10), (Timer t) {
    counter = (counter + 1) % 60;
    String msg = 'notification ' + counter.toString();
    print('SEND: ' + msg + ' - ');
    sendPort.send(counter.toString());
  });
}

// config
List<ShrPrefSwitch> shrPrefSwitches = [
  ShrPrefSwitch(
      ShrPrefKey.alwaysMe, "Auto /me",
      Icon(Icons.try_sms_star),
          (webViewController, data) => {
        webViewController?.evaluateJavascript(
            source: 'window.autoMe = ${data.value}')
      }, (value, webViewController, data) =>
  {
    webViewController?.evaluateJavascript(
        source: 'window.autoMe = $value')
  }),
  ShrPrefSwitch(
      ShrPrefKey.keepAlive, "Keep Alive", Icon(Icons.auto_awesome),
          (webViewController, data) => {
        if(data.value){
          showNotification(),
          start((data) async {
            print('RECEIVE: ' + data + ', ');
            showNotification();
            bool keepRoom = int.parse(data) == 59 &&
                shrPrefSwitches.firstWhere(
                        (s) => ShrPrefKey.keepRoom == s.key).value;
            var action =  keepRoom ?
              ''' \$.ajax({
                         type: "POST",
                         url: `https://drrr.com/room/?ajax=1&api=json`,
                         data: {'message': "keep!", 'to': profile.id},
                         success: function(data){ },
                         error: function(data){ }
                       }); ''' :
                          ''' \$.ajax({
                         type: "GET",
                         url: `https://drrr.com/json.php?\${Math.round(new Date().getTime()/1000) - 60}`,
                         success: function(data){ /* alert(JSON.stringify(data)); */ },
                         error: function(data){ }
                       });''';
              webViewController?.evaluateJavascript(source: action);
          }, (){ stop(); })
        }
      },
          (value, webViewController, data) => {
        if(value){
          showNotification(), start((data) async {
            print('RECEIVE: ' + data + ', ');
            showNotification();
            bool keepRoom = int.parse(data) == 59 &&
                shrPrefSwitches.firstWhere(
                        (s) => ShrPrefKey.keepRoom == s.key).value;
            var action =  keepRoom ?
            ''' \$.ajax({
                       type: "POST",
                       url: `https://drrr.com/room/?ajax=1&api=json`,
                       data: {'message': "keep!", 'to': profile.id},
                       success: function(data){ },
                       error: function(data){ }
                     }); ''' :
            ''' \$.ajax({
                       type: "GET",
                       url: `https://drrr.com/json.php?\${Math.round(new Date().getTime()/1000) - 60}`,
                       success: function(data){ /* alert(JSON.stringify(data)); */ },
                       error: function(data){ }
                     });''';
            webViewController?.evaluateJavascript(source: action);
          }, (){ stop(); })
        }
        else {
          setShrPrefSwitches(ShrPrefKey.keepRoom, false, webViewController),
          flutterLocalNotificationsPlugin.cancel(NoteID.cancelKeepRoom.index),
          stop()
        }
      }),
  ShrPrefSwitch(
      ShrPrefKey.keepRoom, "Keep Room",
      Icon(Icons.auto_fix_high),
          (app, data) => {

      },
          (bool value, webViewController, data) => {
        if(data.value){
          setShrPrefSwitches(ShrPrefKey.keepAlive, true, webViewController)
        }
        //setting.webViewController?.evaluateJavascript(
        //    source: 'alert("press always/me");')
      }),
];


// TODO: clear all notofication on app terminated
// TODO: try ajax on webView

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    await AndroidInAppWebViewController
        .setWebContentsDebuggingEnabled(true);
  }
  runApp(new MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {

  final GlobalKey webViewKey = GlobalKey();

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
    shrPrefSwitches.forEach((elt) => elt.init((){}));

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
  }

  @override
  void dispose() { super.dispose(); }

  @override
  Widget build(BuildContext context) {
    setStateStack.add(() {setState((){});});
    return MaterialApp(
      theme: ThemeData(
        primaryColor: Colors.black,
      ),
      routes: {
        '/botSettings': (context) => BotSettingsRoute(),
      },
      home: Scaffold(
          appBar: AppBar(
            title: const Text("LambdaBotApp"),
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
                              source: '''
                                  (function(){
                                    let load = () => setTimeout(function(){
                                      if(!window.\$) return load();
                                      \$.origAjax = \$.ajax;
                                      \$.ajax = function(...args){
                                          if(window.autoMe
                                          && typeof args[0].data == "string"
                                          && args[0].data.includes("message=")
                                          && args[0].data.match(/to=\$|to=&/))
                                        args[0].data = args[0].data.replace("message=", "message=/me"),
                                          \$("#talks").children()[0].remove();
                                        return \$.origAjax.apply(\$, args);
                                      }
                                     }, 200);
                                     load();
                                   })();
                                  ''',
                              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END),
                          // UserScript(
                          //     source: "var bar = 2;",
                          //     injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END),
                        ]),
                        onLoadStart: (controller, url) {
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
                                  (elt) => elt.onDocLoaded(this.webViewController, elt));
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
  about,
}

enum NoteID {
  cancelKeepRoom,
}

class SampleMenu extends StatelessWidget {

  SampleMenu(this.controller);

  final Future<InAppWebViewController> controller;
  final CookieManager cookieManager = CookieManager();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InAppWebViewController>(
      future: controller,
      builder:
          (BuildContext context, AsyncSnapshot<InAppWebViewController> controller) {
        return PopupMenuButton<MenuOptions>(
          onSelected: (MenuOptions value) {
            switch (value) {
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
              value: MenuOptions.botSettings,
              child: Text('Bot Settings'),
            ),
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
          const Text('lambda.catノ#L/CaT//Hsk\na.k.a 浪打貓ノ，也有人叫我蘭達\n約於 2017 秋開始出沒於 drrr.com。\nmail:lambdacat.tw@gmail.com\n'),
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
    await cookieManager.deleteAllCookies();
    String message = 'There were cookies. Now, they are gone!';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
    ));
  }

  void _onBotSettings(InAppWebViewController? controller, BuildContext context) async {
    Navigator.pushNamed(
      context,
      '/botSettings',
      arguments: BotSettingsArgs(controller),
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

/// This is the stateful widget that the main application instantiates.
class BotSettingsRoute extends StatefulWidget {
  const BotSettingsRoute({Key? key}) : super(key: key);

  @override
  State<BotSettingsRoute> createState() => _BotSettingsRouteState();
}

Future<bool> saveSwitchState(String key, bool value) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  prefs.setBool(key, value);
  return prefs.setBool(key, value);
}

class BotSettingsArgs {
  InAppWebViewController? webViewController;
  BotSettingsArgs(this.webViewController);
}

/// This is the private State class that goes with MyStatefulWidget.
class _BotSettingsRouteState extends State<BotSettingsRoute> {

  InAppWebViewController? webViewController;

  @override
  void initState() {
    super.initState();
  }

  void commitView() {
    setState((){});
  }

  @override
  Widget build(BuildContext context) {

    setStateStack.add(() {setState((){});});

    final args = ModalRoute.of(context)!.settings.arguments as BotSettingsArgs;
    this.webViewController = args.webViewController;
    // this.shrPrefSwitches!.forEach((elt) => elt.init(this.commitView));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Bot Settings"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Dollars',
          onPressed: () {
            setStateStack.removeLast();
            Navigator.pop(context);
          },
        )
      ),
      body: Column(
        children: shrPrefSwitches.map<Widget>(
            (data) => SwitchListTile(
                title: Text(data.title),
                value: data.value,
                onChanged: (bool value) {
                  setState(() {
                    data.onChanged(value, this.webViewController, data);
                  });
                },
                secondary: data.icon
            )
        ).toList()
      ),
    );
  }
}