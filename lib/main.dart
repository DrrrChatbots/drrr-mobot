import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:core';
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Cookie;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:http/http.dart' as http;
import 'package:tuple/tuple.dart';
import 'package:http/retry.dart';

// icon
// https://fonts.google.com/icons?selected=Material+Icons

// local notification
// https://pub.dev/documentation/flutter_local_notifications/latest/flutter_local_notifications/FlutterLocalNotificationsPlugin-class.html

// https://web.archive.org/web/20210127075231/https://codingwithjoe.com/dart-fundamentals-isolates/
Isolate? isolate;
CookieManager cookieManager = CookieManager.instance();

List<void Function()> setStateStack = [];

// beg local notification
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
// end local notification

// beg ShrPrefSwitches
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

  // consider template function, on app start
  void Function(ShrPrefSwitch data)? start;

  // consider template function, on document ready
  void Function(InAppWebViewController?, ShrPrefSwitch data)? ready;

  // consider template function, on switch change
  void Function(bool, InAppWebViewController?, ShrPrefSwitch)? change;

  // consider template function
  void onChanged(bool _value, InAppWebViewController? webview, ShrPrefSwitch data) {
    this.value = _value;
    saveSwitchState(key.toString(), value);
    change?.call(value, webview, data);
  }

  ShrPrefSwitch(this.key, this.title, this.icon,
      {this.start, this.ready, this.change});

  init(commitView) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    this.value = prefs.getBool(this.key.toString()) ?? false;
    commitView();
  }
}

ShrPrefSwitch assocSPS(key){
  return shrPrefSwitches.firstWhere((s) => s.key == key);
}

void setShrPrefSwitches(key, value, webview){
  var dep = assocSPS(key);
  if(dep.value == value) return;
  dep.value = value;
  dep.onChanged(value, webview, dep);
  setStateStack.last();
}
// end ShrPrefSwitches

// config
List<ShrPrefSwitch> shrPrefSwitches = [
  ShrPrefSwitch(
      ShrPrefKey.alwaysMe, "Always /me",
      const Icon(Icons.try_sms_star),
      ready: (webViewController, data) => {
        webViewController?.evaluateJavascript(
            source: 'window.autoMe = ${data.value}')
      },
      change: (value, webViewController, data) => {
        webViewController?.evaluateJavascript(
            source: 'window.autoMe = $value')
      }),
  ShrPrefSwitch(
      ShrPrefKey.keepAlive, "Keeping Alive",
      const Icon(Icons.auto_awesome),
      start: (data) => {
        if(data.value){ start() }
      },
      change: (value, webViewController, data) => {
        if(value){ start() }
        else {
          setShrPrefSwitches(ShrPrefKey.keepRoom, false, webViewController),
          flutterLocalNotificationsPlugin.cancel(NoteID.cancelKeepRoom.index),
          stop()
        }
      }),
  ShrPrefSwitch(
      ShrPrefKey.keepRoom, "Keeping Room",
      const Icon(Icons.auto_fix_high),
      change: (bool value, webViewController, data) => {
        if(data.value){
          setShrPrefSwitches(ShrPrefKey.keepAlive, true, webViewController)
        }
      }),
];

var userAgent = "Mobile";
const Map<String, Icon> userAgents = const {
  'Bot': const Icon(Icons.build),
  'Tv': const Icon(Icons.tv),
  'Tablet': const Icon(Icons.tablet_android),
  'Mobile': const Icon(Icons.phone_android),
  'Desktop': const Icon(Icons.desktop_windows),
};
var userAgentKeys = userAgents.entries.map((u) => u.key);

// beg http
class BotClient extends http.BaseClient {
  String cookie = '', id = '';
  final http.Client _inner;
  BotClient(this._inner);

  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['user-agent'] = userAgent;
    return _inner.send(request);
  }

  Future<http.Response> doPost(url, cookie, body) async {
    Map<String, String> headers = {
      'user-agent': userAgent,
      'cookie': cookie ?? this.cookie ?? '',
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    return _inner.post(url, headers: headers, body: body);
  }

  Future<http.Response> doGet(url, cookie) async {
    Map<String, String> headers = {
      'user-agent': userAgent,
      'cookie': cookie ?? this.cookie ?? '',
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    return _inner.get(url, headers: headers);
  }

  Future<void> doLoad() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    this.id = prefs.getString('id') ?? '';
    this.cookie = prefs.getString('cookie') ?? '';
  }

  Future<void> doSave() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("id", this.id);
    prefs.setString("cookie", this.cookie);
  }
}

final httpClient = http.Client();
final BotClient botClient = BotClient(httpClient);

String getCookie(str){
  var cookie = Cookie.fromSetCookieValue(str);
  return '${cookie.name}=${cookie.value};';
}

void doLogin(name, avatar, lang, controller) async {

  var url = Uri.parse('https://drrr.com/?api=json');
  var res = await botClient.doGet(url, null);
  var token = json.decode(res.body)['token'];

  var cookieRaw = getCookie(res.headers['Set-Cookie'] ??
      res.headers['set-cookie'] ?? '') ;

  Map<String, String> bodyFields = {
    'name': name, 'login': 'ENTER',
    'token': token, 'language': lang, 'icon': avatar,
  };

  var resp = await botClient.doPost( url, cookieRaw, bodyFields, );

  cookieRaw = resp.headers['Set-Cookie'] ??
      resp.headers['set-cookie'] ?? '';

  botClient.cookie = getCookie(cookieRaw);

  var cookie = Cookie.fromSetCookieValue(cookieRaw);

  cookieManager.setCookie(
      url: Uri.parse('https://drrr.com/'),
      name: cookie.name,
      value: cookie.value,
      domain: cookie.domain,
      path: cookie.path ?? '',
      isSecure: cookie.secure,
      isHttpOnly: cookie.httpOnly,
      iosBelow11WebViewController: controller
  );

  controller?.reload();
  res = await botClient.doGet(Uri.parse('https://drrr.com/profile/?api=json'), null);
  botClient.id = json.decode(res.body)['profile']['id'];
  print("id is =======> ${botClient.id}");
  await botClient.doSave();
}

// beg background
final int helloAlarmID = 0;
// port passing may help https://stackoverflow.com/questions/62725890/flutter-how-to-pass-messages-to-the-isolate-created-by-android-alarmmanager
void start() async {
  // if (isolate != null)  return;
  // ReceivePort receivePort= ReceivePort(); //port for this main isolate to receive messages.
  // isolate = await Isolate.spawn(runTimer, receivePort.sendPort);
  // receivePort.listen(onData, onDone: onDone);
  stop(); // is it a good approach?

  showNotification();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  prefs.setInt("counter", 0);
  print('start!');
  await AndroidAlarmManager.periodic(
      const Duration(minutes: 1), helloAlarmID, runTimer);
}

void stop() {
  // if (isolate != null) {
  //   isolate!.kill(priority: Isolate.immediate);
  //   isolate = null;
  // }
  print("stopped");
  //headlessWebView?.dispose();
  AndroidAlarmManager.cancel(helloAlarmID);
}

void runTimer() async {

  initConfig();

  flutterLocalNotificationsPlugin.initialize(
      flutterInitSettings,
      onSelectNotification: (String? payload) async => {
        setShrPrefSwitches(
            ShrPrefKey.values.firstWhere((e) => e.toString() == payload),
            false, null)
      });

  showNotification();

  SharedPreferences prefs = await SharedPreferences.getInstance();
  var counter = prefs.getInt('counter') ?? 0;
  var update = prefs.getString('update') ??
      ((DateTime.now().millisecondsSinceEpoch / 1000) - 60).toString();

  final hClient = http.Client();
  final BotClient botClient = BotClient(hClient);

  await botClient.doLoad();

  var keep = assocSPS(ShrPrefKey.keepRoom).value;
  // option 1
  if(keep && counter % 10 == 9){
    Map<String, String> bodyFields = {
      'message': 'keep!',
      'to': botClient.id,
    };
    await botClient.doPost(
        Uri.parse("https://drrr.com/room/?ajax=1&api=json"),
        null, bodyFields);
  }
  else{
    // option 2
    var url = 'https://drrr.com/json.php?update=$update';
    var res = await botClient.doGet(
        Uri.parse(url), null);
    print(url);
    print(res.body);
    var upd = json.decode(res.body)['update'];
    update = upd == null ? update : upd.floor().toString();
  }

  prefs.setInt("counter", (counter + 1) % 60);
  prefs.setString("update", update);
}

// void runTimer(SendPort sendPort) {
//   int counter = 0;
//   Timer.periodic(new Duration(seconds: 10), (Timer t) {
//     counter = (counter + 1) % 60;
//     String msg = 'notification ' + counter.toString();
//     print('SEND: ' + msg + ' - ');
//     sendPort.send(counter.toString());
//   });
// }

// end background

// TODO: clear all notification on app terminated
// TODO: try ajax on webView

void initConfig() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  userAgent = prefs.getString('user-agent') ?? userAgent;
  for(var sps in shrPrefSwitches) await sps.init((){});
}

Future main() async {

  WidgetsFlutterBinding.ensureInitialized();

  await AndroidAlarmManager.initialize();

  if (Platform.isAndroid) {
    await AndroidInAppWebViewController
        .setWebContentsDebuggingEnabled(true);
  }

  initConfig();

  for(var sps in shrPrefSwitches) sps.start?.call(sps);

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
                                      if(location.href == "https://drrr.com/"){
                                        //window.addEventListener(
                                        //  "flutterInAppWebViewPlatformReady",
                                        //  function(event) {
                                        //     alert("bind");
                                             \$('form').submit(function(){
                                               window.flutter_inappwebview.callHandler(
                                                 'login', \$('#form-name').val(),
                                                 \$('.user-icon.active').attr('data-avatar'),
                                                 \$('#form-language-select').val())
                                                 .then(function(result) {
                                                 console.log(result);
                                               });
                                               return false;
                                             });
                                        //  }
                                        //);
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
                          controller.addJavaScriptHandler(
                              handlerName: 'login',
                              callback: (args) => {
                                doLogin(args[0], args[1], args[2], controller),
                                jsonEncode("done")
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
  // final CookieManager cookieManager = CookieManager();

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
          const Text('lambda.catノ#L/CaT//Hsk\na.k.a 浪打貓ノ，也有人叫我蘭達\n約於 2017 秋開始出沒於 drrr.com。\nmail: lambdacat.tw@gmail.com\n'),
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
        children:  [
          ListTile(
            leading: Icon(Icons.manage_accounts),
            title: Text('User Agent'),
            trailing: DropdownButton<String>(
              hint:  Text("Select item"),
              value: userAgent,
              onChanged: (String? uaKey) async {
                userAgent = uaKey ?? userAgent;
                SharedPreferences prefs = await SharedPreferences.getInstance();
                prefs.setString('user-agent', userAgent);
                setState((){});
              },
              items: userAgentKeys.map((uaKey) {
                return  DropdownMenuItem<String>(
                  value: uaKey,
                  child: Row(
                    children: <Widget>[
                      userAgents[uaKey]!,
                      SizedBox(width: 10,),
                      Text(
                        uaKey,
                        style:  TextStyle(color: Colors.black),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          )
        ].cast<Widget>() + shrPrefSwitches.map<Widget>(
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
