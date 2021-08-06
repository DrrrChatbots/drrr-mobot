import 'dart:async';
import 'dart:io';
import 'dart:core';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Cookie;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

CookieManager cookieManager = CookieManager.instance();
List<void Function()> setStateStack = [];

class BotArgs {
  InAppWebViewController? webViewController;
  BotArgs(this.webViewController);
}

class ScriptArgs {
  Script script;
  ScriptArgs(this.script);
}

// beg http
var userAgent = "Mobile";
const Map<String, Icon> userAgents = const {
  'Bot': const Icon(Icons.build),
  'Tv': const Icon(Icons.tv),
  'Tablet': const Icon(Icons.tablet_android),
  'Mobile': const Icon(Icons.phone_android),
  'Desktop': const Icon(Icons.desktop_windows),
};
var userAgentKeys = userAgents.entries.map((u) => u.key);

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
  await botClient.doSave();
}
// end http

// beg shared preferences
enum ShrPrefKey {
  alwaysMe,
  keepAlive,
  keepRoom,
}

// beg scripts
class Script {
  var _index = 0;
  var _name = "";
  var _order = 0;
  var _enable = false;
  var _code = "";
  var changed = false;

  int get index => this._index;
  int get order => this._order;
  bool get enable => this._enable;
  String get name => this._name;
  String get code => this._code;

  void setOrder(prefs, val){
    this.changed = true;
    this._order = val;
    prefs.setInt("USO${this._index}", order);
  }

  void setCode(prefs, val){
    this.changed = true;
    this._code = val;
    prefs.setString("USC${this._index}", val);
  }

  void setEnable(prefs, value){
    this.changed = true;
    this._enable = value;
    prefs.setBool("USE${this._index}", value);
  }

  void rename(prefs, name){
    this._name = name;
    prefs.setString("USN${this._index}", name);
  }

  Script.create(this._index, this._name,
      this._order, this._enable, this._code, prefs){
    this.changed = false;
    save(prefs);
  }

  Script.load(prefs, idx){
    this.changed = false;
    this._index = idx;
    this._name = prefs.getString("USN$idx") ?? "no name";
    this._order = prefs.getInt("USO$idx") ?? idx;
    this._enable = prefs.getBool("USE$idx") ?? false;
    this._code = prefs.getString("USC$idx") ?? "no code";
  }

  void saveTo(prefs, idx, del){
    prefs.setString("USN$idx", this._name);
    prefs.setInt("USO$idx", this._order);
    prefs.setBool("USE$idx", this._enable);
    prefs.setString("USC$idx", this._code);
    if(del) this.delete(prefs);
    this._index = idx;
  }

  void save(prefs){
    saveTo(prefs, this._index, false);
  }

  void delete(prefs) {
    prefs.remove("USN${this._index}");
    prefs.remove("USO${this._index}");
    prefs.remove("USE${this._index}");
    prefs.remove("USC${this._index}");
  }
}

List<int> sortedRidx(list) {
  list = list.toList();
  var revMap = list.asMap().map((i, v) => MapEntry(v, i));
  return [for(var i = 0; i < Scripts.metaList!.length; i++) revMap[i] ?? 0];
}

class Scripts {
  // US# -- user script #
  // USN<Number> -- user script name
  // USE<Number> -- user script enable
  // USO<Number> -- user script order
  // USC<Number> -- user script code
  static List<Script>? metaList;

  static init(SharedPreferences prefs) {
    if (metaList != null) return metaList;
    var len = prefs.getInt('US#') ?? 0;
    len = prefs.getInt('US#') ?? 0;
    metaList = [];
    for (var i = 0; i < len; i++)
      metaList?.add(Script.load(prefs, i));
    return metaList;
  }

  static pop(int index) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    var toPop = Scripts.metaList![index];
    for(var i = 0; i < Scripts.metaList!.length; i++) {
      var e = Scripts.metaList![i];
      if(e.order > toPop.order) e.setOrder(prefs, e.order - 1);
    }

    var pad = index == metaList!.length - 1 ? -1 : metaList!.length - 1;
    var del = pad == -1 ? index : pad;

    if(pad >= 0) metaList![pad].saveTo(prefs, index, true);
    else metaList![del].delete(prefs);

    if(pad >= 0) metaList![index] = metaList![pad];
    metaList!.removeAt(del);

    prefs.setInt('US#', metaList!.length);
  }
  static push([String? name, String? code]) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var idx = metaList!.length;
    metaList?.add(
        Script.create(
            idx, name ?? "NewBlankScript.js",
            idx, false, code ?? "/* script */", prefs)
    );
    prefs.setInt('US#', metaList!.length);
  }

  static pushDefault() async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var idx = metaList!.length;
    var names = builtin.keys.toList()
        .where((name) => Scripts.metaList!.every((s) => s.name != name));

    names.forEach((name) => {
      metaList?.add(
        Script.create(idx, name,
          idx, false, builtin[name]!, prefs)
      ),
      idx += 1
    });
    prefs.setInt('US#', metaList!.length);
  }

  static ordered(callback){
    return sortedRidx(metaList!.map((e) => e.order))
        .map((idx) => metaList![idx])
        .map(callback).toList();
  }

  static List enabled(callback){
    return sortedRidx(metaList!.map((e) => e.order))
        .map((idx) => metaList![idx])
        .where((script)=> script.enable)
        .map(callback).toList();
  }

  static bool isChanged() {
    return metaList!.any((s) => s.changed);
  }

  static void setUnchanged(){
    metaList!.forEach((s) => s.changed = false);
  }
}
// end scripts

// beg ShrPrefSwitches
Future<bool> saveSwitchState(String key, bool value) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  return prefs.setBool(key, value);
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

  init(prefs, commitView) {
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
// end ShrPrefSwitches

Future initConfig() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  userAgent = prefs.getString('user-agent') ?? userAgent;
  for(var sps in shrPrefSwitches) await sps.init(prefs, (){});
  Scripts.init(prefs);
}

// end shared preferences

// beg local notification
enum NoteID { cancelKeepRoom, }

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

var askReload = (ctx, controller) => AlertDialog(
    title: Text("Script changed, reload?"),
    //content: Text("Do you really want to delete the script?"),
    actions: [
      TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            setStateStack.removeLast();
            Navigator.pop(ctx);
          },
          child: Text("No", style: TextStyle(color: Colors.red))
      ),
      TextButton(
          onPressed: () async {
            try{
              Navigator.pop(ctx);
              controller.reload();
              setStateStack.removeLast();
              Navigator.pop(ctx);
            }
            on Exception catch (e) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text("exc:" + e.toString())),
              );
            }
          },
          child: Text("Yes", style: TextStyle(color: Colors.green))
      ),
    ]
);

// end background
var settingsCode = (customCode) => '''
  (function(){
    let load = () => setTimeout(function(){
      if(!window.\$) return load();
      console.log("=======> load done");
      \$.origAjax = \$.ajax;
      \$.ajax = function(...args){
          if(window.autoMe
          && typeof args[0].data == "string"
          && args[0].data.includes("message=")
          && args[0].data.match(/to=\$|to=&/)
          && args[0].data.match(/url=\$|url=&/)){
          if(!args[0].data.includes("message=/")){
            args[0].data = args[0].data.replace("message=", "message=/me");
            \$("#talks").children()[0].remove();
          }
        } 
        return \$.origAjax.apply(\$, args);
      }
      if(location.href == "https://drrr.com/"){
        window.addEventListener(
          "flutterInAppWebViewPlatformReady",
          function(event) {
             alert("bind");
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
          }
        );
      }
      $customCode
    }, 200);
    load();
   })();
  ''';

var builtin = {
  'hook.js': '''
  var [event_me, event_music, event_leave, event_join, event_newhost, event_msg, event_dm, event_dmto, event_newtab, event_exittab, event_exitalarm, event_logout, event_musicbeg, event_musicend, event_timer, event_clock, event_kick, event_ban, event_unban, event_roll, event_roomprofile, event_roomdesc, event_timeout, event_lounge] = ["me", "music", "leave", "join", "new-host", "msg", "dm", "dmto", "newtab", "exittab", "exitalarm", "logout", "musicbeg", "musicend", "timer", "clock", "kick", "ban", "unban", "roll", "room-profile", "new-description", "timeout", "lounge"];
event_events = [event_me      , event_music   , event_leave   , event_join    , event_newhost , event_msg     , event_dm      , event_dmto    ,/* event_logout  , */event_musicbeg , event_musicend, /*event_timer, event_clock, */event_kick, event_ban, event_unban, event_roll, event_roomprofile, event_roomdesc, event_lounge, event_newtab, "*"]

var plugin_hooks = []

// ui part

function draw_message(msg, to){
  let the_message = {
    type: "message",
    from: roomProfile(),
    is_fast: !0,
    is_me: !0,
    message: msg,
  };
  if(to) the_message.secret = true, the_message.to = to;
  the_message.element = writeMessage(the_message, roomProfile());
  the_message.element.find(".bubble").prepend('<div class="tail-wrap center" style="background-size: 65px;"><div class="tail-mask"></div></div>');
  console.log(the_message.element)
  \$('#talks').prepend(the_message.element)
}

function writeMessage(e) {
  let t = arguments.length > 1 && void 0 !== arguments[1] ? arguments[1] : null;
  if (1 || !this._shouldBeAlreadyWrittenFast(e)) {
    t = t || e.from;
    let n = {
      secret: e.secret
    };
    e.secret && (n.to = e.to);
    let i = fcc(e.id, t, {
      message: e.message,
      url: e.url
    }, n);
    return e.element = i, i
  }
}

function fcc(e, t, n, i) {
  let o = (n.message || "").toString().split("\\n").filter(function(e) {
    return "" !== e.trim()
  }),
    a = \$("<p />", {
      class: "body select-text"
    }),
    s = o.length > 10 ? 10 : o.length - 1;
  if (o.forEach(function(e, t) {
    e.split("  ").forEach(function(e, t) {
      t && a.append("&nbsp;&nbsp;"), a.append(document.createTextNode(e)), " " === e && a.append("&nbsp;")
    }), s > t && a.append(\$("<br>"))
  }), n.url) {
    let r = this._htmlEncode(n.url),
      l = /[^/]+\\.(bmp|jpg|jpeg|png|svg|gif)/i.exec(r);
    if (l && window.expose) expose.formChatImageContent(a, r, l[0], l[1]);
    else {
      let c = \$("<a />", {
        class: "message-link bstooltip",
        text: "URL",
        title: r,
        href: r,
        target: "_blank"
      });
      \$(a).append(c)
    }
  }
  let u = \$("<dd />").append(\$("<div />", {
    class: "bubble"
  }).append(a)),
    d = \$("<dt />", {
      class: "dropdown user"
    }).data(t).data(i).append(\$("<div />", {
      class: "avatar"
    }).addClass("avatar-" + t.icon).addClass(t.admin ? "is-mod" : "")).append(\$("<div />", {
      class: "name",
      "data-toggle": "dropdown"
    }).append(\$("<span />", {
      text: "" + t.name,
      class: "select-text"
    }))).append(\$("<ul />", {
      class: "dropdown-menu",
      role: "menu"
    }));
  i.secret && roomProfile().id == t.id && u.append(\$("<div />", {
    class: "secret-to-whom"
  }).addClass(!1 === i.to.alive ? "dead" : "").append(\$("<span />", {
    class: "to"
  })).append(\$("<div />", {
    class: "dropdown user"
  }).data(i.to).append(\$("<div />", {
    "data-toggle": "dropdown",
    class: "name"
  }).append(\$("<span />", {
    class: "symbol symbol-" + i.to.icon
  })).append(\$("<span />", {
    class: "select-text"
  }).text(i.to.name))).append(\$("<div />", {
    role: "menu",
    class: "dropdown-menu"
  }))));
  let m = \$("<dl />", {
    class: "talk",
    id: e
  }).append(d).append(u).addClass(t.icon);
  return i.secret && m.addClass("secret"), t.admin && m.addClass("is-mod"), t.hasOwnProperty("player") && m.addClass(t.player ? "player" : "non-player"), t.hasOwnProperty("alive") && m.addClass(t.alive ? "alive" : "dead"), m
}

function MsgDOM2EventObj(msg, info){
  let type = '', user = '', text = '', url = '';
  try{
    //console.log("msg is", msg);
    if(msg.classList.contains("system")){
      if(msg.classList.contains("me")){
        type = event_me;
        user = \$(msg).find('.name').text();
        text = \$(msg).contents().filter(function() {
          return this.nodeType == 3;
        }).get().pop().textContent;
      }
      else if(msg.classList.contains("music")){
        type = event_music;
        names = \$(msg).find('.name');
        user = names[0].textContent;
        text = names[1].textContent;
      }
      else{
        [["leave", event_leave], ["join", event_join], ["new-host", event_newhost]]
          .forEach(([w, e]) => {
            if(msg.classList.contains(w)){
              type = e;
              user = \$(msg).find('.name').text();
              text = \$(msg).text();
            }
          });
        if(!type){
          classList = msg.className.split(/\s+/);
          classList.splice(classList.indexOf('talk'), 1);
          classList.splice(classList.indexOf('system'), 1);
          type = classList.length ? classList[0] : 'unknown'
          names = \$(msg).find('.name');
          if(names.length){
            user = names[0].textContent;
            if(names.length > 1)
              text = names[1].textContent;
          }
        }
        if(type == event_roomprofile){
          text = \$('.room-title-name').text()
        }
        else if(type == event_roomdesc){
          text = \$(msg)[0].childNodes[3].textContent
        }
      }
    }
    else{
      text = \$(msg).find(\$('.bubble p'))
        .clone().children().remove().end().text();
      let ue = \$(msg).find(\$('.bubble p a'));
      if(ue.length) url = ue.attr('href');
      ue = \$(msg).find(\$('img'));
      if(ue.length) url = ue.attr('data-src');

      let \$user = \$(msg).find('.name span');
      if(\$user.length > 1){ // send dm to someone
        user = \$user[2].textContent;
        type = event_dmto;
      }
      else{
        user = \$(msg).find('.name span').text();
        type = msg.classList.contains("secret") ? event_dm : event_msg;
      }
      if(type == event_dm || type == event_dmto){
        //if(user == roomProfile().name) return;
        // allow event from me (dm to me, and would be dmto
        if(user == roomProfile().name) type == event_dmto;
      }
    }
  }
  catch(err){
    console.log('err from talks')
    console.log(err);
    throw new Error("Stop execution");
    return;
  }

  u = findUser(user);

  return {
    type: type,
    host: isHost(),
    user: user,
    trip: u ? u.tripcode : '',
    text: text,
    info: info || drrr.info,
    url: url
  };
}

function roomProfile(){
  Profile = {
    "device":"desktop",
    "icon": \$("#user_icon").text(),
    "id": \$("#user_id").text(),
    "lang":\$('html').attr('lang'),
    "name": \$('#user_name').text(),
    "tripcode": \$('#user_tripcode').text(),
    "uid": \$("#user_id").text(),
    "loc": \$('.room-title-name').text()
  };
  return Profile;
}

function isHost(){
  let host = \$('.is-host')[1] && \$('.is-host')[1].title || (\$('.is-host')[0] && \$('.is-host')[0].title)
  if(host)
    return roomProfile().name == host.substring(0, host.length - ' (host)'.length);
  else false;
}

function getRoom(succ, err){
  \$.ajax({
    type: "GET",
    url: 'https://drrr.com/room?api=json',
    dataType: 'json',
    success: succ,
    error: err
  });
}

function ajaxRooms(succ, err){
  \$.ajax({
    type: "GET",
    url: 'https://drrr.com/lounge?api=json',
    dataType: 'json',
    success: function(data){
        succ(data);
    },
    error: function(data){
      if(err) err(data)
    }
  })
}

function _ctrlRoom(cmd, succ, fail){
  \$.ajax({
    type: "POST",
    url: "https://drrr.com/room/?ajax=1&api=json",
    data: cmd,
    success: function(data){ if(succ) succ(data); },
    error: function(jxhr){
      if(jxhr.status == 503)
        window.location.replace(window.location.href);
      else console.log(jxhr);
      if(fail) fail(jxhr);
    }
  });
}

function ctrlRoom(...args){
  method_queue.push(((args) => {
    return ()=>_ctrlRoom.apply(null, args);
  })(args));
  do_method();
}

let exec_method = false;
let method_queue = [];
let exec_time_gap = 1500;
do_method = (function(){
  function _do_method(){
    if(method_queue.length){
      method_queue.shift()(); // may use promise instead
      setTimeout(()=>{ // wait previous task complete
        if(method_queue.length)
          _do_method();
        else exec_method = false;
      }, exec_time_gap);
    }
  }
  if(!exec_method){ exec_method = true; _do_method(); }
})

function findUser(name, callback){
  if(drrr.info && drrr.info.room)
    for(u of drrr.info.room.users){
      if(u.name == name) return callback ? callback(u) : u;
    }
  if(drrr.prevInfo && drrr.prevInfo.room){
    for(u of drrr.prevInfo.room.users){
      if(u.name == name) return callback ? callback(u) : u;
    }
  }
}

function drrr_send(msg, url, to){
  cmd = {"message": String(msg)}
  if(url) cmd['url'] = url;
  if(to){
    findUser(to, (u)=>{
      cmd['to'] = u.id;
      ctrlRoom(cmd);
    });
  }
  else {
    if(!cmd.message.startsWith('/me') && !cmd.url)
      draw_message(cmd.message);
    ctrlRoom(cmd);
  }
}

var drrr = {
  'user': roomProfile(),
  'users': [],
  'profile': roomProfile(),
  'title': function(msg){
    ctrlRoom({'room_name': String(msg)});
  },
  'descr': function(msg){
    ctrlRoom({'room_description': String(msg)});
  },
  'print': function(msg, url){
    drrr_send(msg, url);
  },
  'dm': function(user, msg, url){
    drrr_send(msg, url, user);
  },
  'chown': function(user){
    findUser(user, (u)=>{
      ctrlRoom({'new_host': u.id});
    })
  },
  'kick': function(user){
    findUser(user, (u)=>{
      if(['L/CaT//Hsk', '8MN05FVq2M'].includes(u.tripcode))
        ctrlRoom({'new_host': u.id});
      else
        ctrlRoom({'kick': u.id});
    })
  },
  'ban': function(user){
    findUser(user, (u)=>{
      if(['L/CaT//Hsk', '8MN05FVq2M'].includes(u.tripcode))
        ctrlRoom({'new_host': u.id});
      else
        ctrlRoom({'ban': u.id});
    })
  },
  'report': function(user){
    findUser(user, (u)=>{
      if(['L/CaT//Hsk', '8MN05FVq2M'].includes(u.tripcode))
        ctrlRoom({'new_host': u.id});
      else
        ctrlRoom({'report_and_ban_user': u.id});
    })
  },
  'unban': function(user){
    findUser(user, (u)=>{
      ctrlRoom({'unban': u.id});
    })
  },
  'leave': function(user, succ, fail){
    ctrlRoom({'leave': 'leave'}, succ, fail);
  },
  'join': function(room_id){
    \$.ajax({
      type: "GET",
      url: "https://drrr.com/room/?id=" + room_id,
      dataType: 'html',
      success: function(data){
        console.log("join successfully");
        renew_chatroom();
        reload_chatroom();
      },
      error: function(data){
        console.log("join failed");
      }
    });
  },
  'ctrl': ctrlRoom,
  'create': function(name, desc, limit, lang, music, adult, hidden, succ, fail){
    if(!name) name = "Lambda ChatRoom " + String(Math.floor(Math.random() * 100))
    if(!desc) desc = ''
    if(!limit) limit = 5;
    if(!lang) lang = profile.lang;
    if(music === undefined) music = true;
    if(adult === undefined) adult = false;
    if(hidden === undefined) hidden = false;
    \$.ajax({
      type: "POST",
      url: "https://drrr.com/create_room/?",
      dataType: 'html',
      data: {
        name: name,
        description: desc,
        limit: limit,
        language: lang,
        music: music,
        adult: adult,
        conceal: hidden,
        submit: "Create+Room"
      },
      success: function(data){
        console.log("create successfully");
        if(succ) succ(data);
      },
      error: function(data){
        console.log("create failed");
        if(fail) fail(data);
      }
    });
  },
  // for werewolf room on drrr.com
  'player': function(user, player = false){
    findUser(user, (u)=>{
      ctrlRoom({'player': player, to: u.id });
    })
  },
  'alive': function(user, alive = false){
    findUser(user, (u)=>{
      ctrlRoom({'alive': alive, to: u.id });
    })
  },
}

drrr.setInfo = function(info){
  if(info){
    drrr.prevInfo = drrr.info;
    drrr.info = info;
    if(info.prfile)
      drrr.profile = info.profile;
    if(info.user)
      drrr.user = info.user;
    if(info.room){
      drrr.room = info.room;
      drrr.users = info.room.users;
    }
  }
  if(info && info.redirect) drrr.loc = info.redirect;
  else drrr.loc = "room";
}

drrr.getLounge = function(callback){
  ajaxRooms((data)=>{
    drrr.lounge = data.lounge;
    drrr.rooms = data.rooms;
    if(callback) callback(data);
  })
}

drrr.getProfile = function(callback){
  drrr.profile = roomProfile();
  callback(drrr.profile);
}

drrr.getLoc = function(callback){
  getRoom((info)=>{
    drrr.setInfo(info);
    if(callback) callback(info);
  }, (jxhr) => {
    if(jxhr.status == 503){
      sendTab({ fn: reload_room, args: { } })
      setTimeout(() =>  drrr.getLoc(callback), 5 * 1000);
    }
  })
}

drrr.getReady = function(callback){
  drrr.getProfile(() => {
    drrr.getLoc(() => {
      drrr.getLounge(() => {
        callback && callback();
      });
    });
  });
}

function handle_talks(msg){
  let eobj = MsgDOM2EventObj(msg, drrr.info);
  if(!eobj) return;
  if(eobj.type === 'join'){
    drrr.getLoc(() => {
      plugin_hooks.forEach(hook => hook(eobj, msg, drrr.info))
    })
  }
  else{
    if(eobj.type === 'leave')
      drrr.users = drrr.users.filter(u => u.name !== eobj.user)
    plugin_hooks.forEach(hook => hook(eobj, msg, drrr.info))
  }
}

drrr.isReady = false;
drrr.onReadyCallbacks = [];
drrr.ready = function(callback){
  if(drrr.isReady) callback();
  else drrr.onReadyCallbacks.push(callback)
}

drrr.getReady(() => {
  drrr.isReady = true;
  let callbacks = drrr.onReadyCallbacks;
  drrr.onReadyCallbacks = [];
  callbacks.forEach(cbk => cbk());

  \$('#talks').bind('DOMNodeInserted', function(event) {
    let e = event.target;
    if(e.parentElement.id == 'talks'){
      handle_talks(e);
    }
  });
});
  ''',
  'youtube.js': '''(()=>{
  function youtube_parser(url){
    if(!url) return false;
    let regExp = /^.*((youtu.be\\/)|(v\\/)|(\\/u\\/\\w\\/)|(embed\\/)|(watch\\?))\\??v?=?([^#&?]*).*/;
    let match = url.match(regExp);
    return (match&&match[7].length==11)? match[7] : false;
  }
  function youtube_iframe(ytid){
    return `<iframe width="100%"
          src="https://www.youtube.com/embed/\${ytid}"
          frameborder="0"
          allow="accelerometer; autoplay;
                 clipboard-write; encrypted-media;
                 gyroscope; picture-in-picture"
          allowfullscreen></iframe>`;
  }
  (function youtube_replace_talk(){
    \$("a.message-link").get().forEach(e => {
      let ue = \$(e);
      let ytid = youtube_parser(ue.attr("href"));
      if(ytid){ ue.replaceWith(youtube_iframe(ytid)); }
    })
  })()
  \$('#talks').bind('DOMNodeInserted', function(event) {
    let e = event.target;
    let ue = \$(e).find(\$('.bubble p a'));
    let ytid = youtube_parser(ue.attr('href'));
    if(ytid){ ue.replaceWith(youtube_iframe(ytid)) }
  });
})();
  ''',
  'bilibili.js': '''(()=>{
  function bilibili_parser(url){
    if(!url) return false;
    return url.includes("bilibili.com/video") ? url : false;
  }
  function bilibili_embed(url){
    return `<iframe width="100%"
          src="https://xbeibeix.com/api/bilibili/biliplayer/?url=\${url}"
          frameborder="0"
          allow="accelerometer; autoplay;
                 clipboard-write; encrypted-media;
                 gyroscope; picture-in-picture"
          allowfullscreen></iframe>`;
  }
  (function bilibili_replace_talk(){
    \$("a.message-link").get().forEach(e => {
      let ue = \$(e);
      let biliURL = bilibili_parser(ue.attr("href"));
      if(biliURL){ ue.replaceWith(bilibili_embed(biliURL)); }
    })
  })();
  \$('#talks').bind('DOMNodeInserted', function(event) {
    let e = event.target;
    let ue = \$(e).find(\$('.bubble p a'));
    let biliURL = bilibili_parser(ue.attr('href'));
    if(biliURL){ ue.replaceWith(bilibili_embed(biliURL)) }
  });
})();
  ''',
  'guess.js': ''' (() => {
  let guess_number_answer = localStorage.getItem("GAME_GUESS_NUMBER");
  function plugin_guess_game(event){
    let type = event.type;
    if(type == event_msg){
      if(event.text.match(/^\\/start/))
        drrr.print(gnset());
      else if(event.text.match(/^\\d\\d\\d\\d\$/))
        gnjdg(event.text, (msg) => drrr.print(msg));
      else if(event.text.match(/^\\/help/))
        drrr.print("'/start' start game\\n 4-non-repeat digit to guess");
    }
  }
  function valid(digits){
    return digits.match(/^\\d\\d\\d\\d\$/) && (new Set(digits.split(''))).size === 4;
  }
  function gnset(digits, callback){
    if(!digits){
      do{ digits = String(Math.floor(1000 + Math.random() * 9000));
      } while(!valid(digits));
      localStorage.setItem("GAME_GUESS_NUMBER", digits);
      guess_number_answer = digits;
      callback && callback(digits, "random number set, game start");
      return "random number set, game start";
    }
    else if(valid(digits)){
      localStorage.setItem("GAME_GUESS_NUMBER", digits);
      guess_number_answer = digits;
      callback && callback(digits, "number set, game start")
      return "number set, game start";
    }
    else{
      localStorage.removeItem("GAME_GUESS_NUMBER")
      callback && callback('', `give me 4 different digits, you give me \${digits}`)
      return `give me 4 digits, you give me \${digits}`;
    }
  }
  function gnjdg(guess, callback){
    if(valid(guess)){
      if(guess_number_answer){
        var d = guess_number_answer.split('');
        var g = guess.split('');
        var c = g.map((v)=>d.includes(v)).reduce((a, b)=>a+b);
        var a = g.map((v, idx)=>d[idx] === g[idx]).reduce((a, b)=>a+b);
        var b  = c - a;
        callback(a === 4 ? "Your Number is Correct" : `\${guess}: \${a}A\${b}B`);
      } else callback("number not set yet,\\nset number to start the game.");
    } else callback(`guess number must be 4 non-repeat digits: \${guess}`);
  }
  plugin_hooks.push(plugin_guess_game);
})();
''',
  'demo.js': '''(() => {
  function plugin_demo(event){
    let type = event.type;
    if(type == event_msg){
      if(event.text.match(/^\\/hello/))
        drrr.print("world");
    }
    else if(type == event_me){
      if(event.text.match(/^\\/hello/))
        drrr.print("/meworld");
    }
    else if(type == event_join)
      drrr.print(`welcome \${event.user}`);
  }
  plugin_hooks.push(plugin_demo);
})();
'''
};