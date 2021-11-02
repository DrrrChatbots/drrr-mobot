import 'dart:io';
import 'dart:core';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Cookie;
import 'package:shared_preferences/shared_preferences.dart';
import 'LmdBotAppGlobal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

// TODO sytax view height check
// TODO cannot import
class UserSessionsRoute extends StatefulWidget {
  const UserSessionsRoute({Key? key}) : super(key: key);

  @override
  State<UserSessionsRoute> createState() => _UserSessionsRouteState();
}

var askCookie = (ctx, valueText, _textFieldController, controller, setState) =>
    AlertDialog(
      title: Text('Input new cookie'),
      content: TextField(
        autofocus: true,
        onChanged: (value) {
          //setState(() {
          valueText = value;
          //});
        },
        controller: _textFieldController..text = '$valueText',
        decoration: InputDecoration(hintText: "drrr-session-1"),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () async {
              _textFieldController.text = "";
              Navigator.pop(ctx);
            },
            child: Text("Cancel", style: TextStyle(color: Colors.red))
        ),
        TextButton(
            onPressed: () async {
              await botClient.doLoadCookie(
                  sessionCookie(_textFieldController.text),
                  controller, true, context);
              Navigator.pop(ctx);
              setState();
            },
            child: Text("Paste", style: TextStyle(color: Colors.green))
        ),
      ],
    );

var askDelete = (ctx, session, setState) => AlertDialog(
    title: Text("Are you sure to delete?"),
    //content: Text("Do you really want to delete the session?"),
    actions: [
      TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
          },
          child: Text("No", style: TextStyle(color: Colors.blue))
      ),
      TextButton(
          onPressed: () async {
            await Sessions.pop(session.index);
            Navigator.pop(ctx);
            setState();
          },
          child: Text("Yes", style: TextStyle(color: Colors.red))
      ),
    ]
);

var askDeleteCur = (ctx, controller, setState) => AlertDialog(
    title: Text("Quit the session?"),
    //content: Text("Do you really want to delete the session?"),
    actions: [
      TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
          },
          child: Text("No", style: TextStyle(color: Colors.blue))
      ),
      TextButton(
          onPressed: () async {
            botClient.appendToSessions();
            await botClient.doClear(controller);
            Navigator.pop(ctx);
            setState();
          },
          child: Text("Yes", style: TextStyle(color: Colors.red))
      ),
    ]
);

var askRename = (ctx, session, valueText, _textFieldController, setState) =>
    AlertDialog(
      title: Text('Rename "$valueText" to...'),
      content: TextField(
        autofocus: true,
        onChanged: (value) {
          //setState(() {
          valueText = value;
          //});
        },
        controller: _textFieldController..text = '$valueText',
        decoration: InputDecoration(hintText: "Input New Name"),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _textFieldController.text = "";
            },
            child: Text("Cancel", style: TextStyle(color: Colors.red))
        ),
        TextButton(
            onPressed: () async {
              SharedPreferences prefs = await SharedPreferences.getInstance();
              await session.rename(prefs, valueText);
              Navigator.pop(ctx);
              setState();
            },
            child: Text("Save", style: TextStyle(color: Colors.green))
        ),
      ],
    );

void onExit(context, webViewController){
  setStateStack.removeLast();
  Navigator.pop(context);
}

class _UserSessionsRouteState extends State<UserSessionsRoute> {

  InAppWebViewController? webViewController;
  var _textFieldController = TextEditingController();

  @override
  void initState() {
    super.initState();
    setStateStack.add(() {setState((){});});
    // useless
    //WidgetsBinding.instance
    //    ?.addPostFrameCallback((_) => _textFieldController.clear());
  }

  void commitView() { setState((){}); }

  @override
  Widget build(BuildContext context) {

    final args = ModalRoute.of(context)!.settings.arguments as BotArgs;
    this.webViewController = args.webViewController;

    return WillPopScope(
        onWillPop: () async {
          onExit(context, webViewController);
          return false;
        },
        child: Scaffold(
        appBar: AppBar(
            // title: const Text("Sessions"),
            title: const Icon(Icons.account_box),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Dollars',
              onPressed: () {
                onExit(context, webViewController);
              },
            ),
            actions: <Widget>[
              Row(
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.person_off),
                      onPressed: () async {
                        showDialog(
                            context: context,
                            builder: (BuildContext context){
                              return askDeleteCur(context,
                                  this.webViewController,
                                  this.commitView);
                            }
                        );
                        setState((){});
                      },
                    ),
                    IconButton(
                      // icon: const Icon(Icons.download),
                      icon: const Icon(Icons.person_pin),
                      onPressed: () async {
                        if(botClient.cookie.length != 0){
                          botClient.appendToSessions();
                        }
                        else {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text('No session, login first'),
                              ],
                            ),
                          ));
                        }
                        setState((){});
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.content_copy),
                      onPressed: () async {
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
                        setState((){});
                      },
                    ),
                    IconButton(
                      // icon: const Icon(Icons.content_paste),
                      icon: const Icon(Icons.person_add_alt_1),
                      onPressed: () async {
                        showDialog(
                            context: context,
                            builder: (BuildContext context){
                              return askCookie(context,
                                  "", _textFieldController,
                                  this.webViewController, this.commitView);
                              // return askCookie(
                              //     context,
                              //     session,
                              //     this.commitView);
                            }
                        );
                        setState((){});
                      },
                    ),
                  ])
            ]
        ),
        body: ReorderableListView(
          onReorder: (oldIndex, newIndex) async {
            var inc = oldIndex < newIndex ? 1 : 0;
            var update = newIndex - inc;
            var upper = max(oldIndex, newIndex) - inc;
            var lower = min(oldIndex, newIndex);
            print("$oldIndex, $newIndex");
            SharedPreferences prefs = await SharedPreferences.getInstance();
            for(var i = 0; i < Sessions.metaList!.length; i++){
              var e = Sessions.metaList![i];
              if(e.order == oldIndex){
                e.setOrder(prefs, update);
              }
              else if(e.order > lower - 1 && e.order <= upper){
                e.setOrder(prefs, e.order + 1 - inc * 2);
              }
            }
            setState((){});
          },
          children: Sessions.ordered((Session session){
            return ListTile(
              leading: ReorderableDragStartListener(
                index: session.order,
                child: getIcon(session.icon),
              ),
              key: Key('${session.order}'),
              tileColor: Colors.white,
              title: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyText2,
                  children: [
                    WidgetSpan(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.0),
                        child: getDeviceIcon(session.device),
                      ),
                    ),
                    TextSpan(text: ' ', style: TextStyle(fontSize: 25),),
                    TextSpan(text: '${session.name}', style: TextStyle(fontSize: 20),),
                    // Text('${session.name}'),
                  ],
                ),
              ),
              // subtitle: botClient.getDeviceIcon(),
              trailing: Switch(
                  value: session.code == botClient.cookie,
                  onChanged: (value) async {
                    if(value){
                      var code = session.code;
                      if(botClient.id.length != 0 && botClient.cookie.length != 0){
                        if(!Sessions.existSession(botClient.cookie))
                          botClient.appendToSessions();
                      }
                      await botClient.doLoadCookie(code, this.webViewController, false, context);
                    }
                    else{
                      await botClient.doClear(this.webViewController);
                    }
                    setState((){});
                  }
              ),
              onTap: () {
                showDialog(context: context, builder: (BuildContext context){
                  return AlertDialog(
                      title: Text("${session.name}"),
                      //content: Text("Dialog Content"),
                      actions: <Widget>[
                        Card(
                            child: ListTile(
                                leading: Icon(Icons.content_copy),
                                title: Text("Copy the Session"),
                                subtitle: Text("click to copy"),
                                onTap: () async {
                                  Navigator.pop(context);
                                  var cookie = sessionCookieValue(session.code);
                                  Clipboard.setData(ClipboardData(text: cookie));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Session: $cookie'),
                                    ),
                                  );
                                }
                            )
                        ),
                        Card(
                            child: ListTile(
                                leading: Icon(Icons.content_paste),
                                title: Text("Load the Session"),
                                subtitle: Text("click to load"),
                                onTap: () async {
                                  Navigator.pop(context);
                                  var code = session.code;
                                  if(botClient.id.length != 0 && botClient.cookie.length != 0){
                                    if(!Sessions.existSession(botClient.cookie))
                                      botClient.appendToSessions();
                                  }
                                  await botClient.doLoadCookie(code, this.webViewController, false, context);
                                  setState((){});
                                }
                            )
                        ),
                        Card(
                            child: ListTile(
                                leading: Icon(Icons.delete_sweep),
                                title: Text("Delete the Session",
                                  style: TextStyle(color: Colors.red),
                                ),
                                subtitle: Text("click to delete",
                                    style: TextStyle(color: Colors.red)),
                                onTap: () {
                                  Navigator.pop(context);
                                  showDialog(
                                      context: context,
                                      builder: (BuildContext context){
                                        return askDelete(
                                            context,
                                            session,
                                            this.commitView);
                                      }
                                  );
                                }
                            )
                        )
                      ]
                  );
                });
                // Handle tap
              },
            );
          }).cast<Widget>(),
        ),
      )
    );
  }
}
