import 'dart:core';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Cookie;
import 'package:shared_preferences/shared_preferences.dart';
import 'LmdBotAppGlobal.dart';

class BotSettingsRoute extends StatefulWidget {
  const BotSettingsRoute({Key? key}) : super(key: key);

  @override
  State<BotSettingsRoute> createState() => _BotSettingsRouteState();
}

class _BotSettingsRouteState extends State<BotSettingsRoute> {

  InAppWebViewController? webViewController;

  @override
  void initState() {
    super.initState();
    setStateStack.add(() {setState((){});});
  }

  void commitView() { setState((){}); }

  @override
  Widget build(BuildContext context) {

    final args = ModalRoute.of(context)!.settings.arguments as BotArgs;
    this.webViewController = args.webViewController;

    return Scaffold(
      appBar: AppBar(
          // title: const Text("Settings"),
          title: const Icon(Icons.settings_applications),
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
