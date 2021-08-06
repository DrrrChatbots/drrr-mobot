import 'dart:io';
import 'dart:core';
import 'dart:math';
import 'package:path/path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Cookie;
import 'package:shared_preferences/shared_preferences.dart';
import 'LmdBotAppGlobal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

// TODO sytax view height check
// TODO cannot import
class UserScriptsRoute extends StatefulWidget {
  const UserScriptsRoute({Key? key}) : super(key: key);

  @override
  State<UserScriptsRoute> createState() => _UserScriptsRouteState();
}

var askDelete = (ctx, script, setState) => AlertDialog(
    title: Text("Are you sure to delete?"),
    //content: Text("Do you really want to delete the script?"),
    actions: [
      TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
          },
          child: Text("No", style: TextStyle(color: Colors.blue))
      ),
      TextButton(
          onPressed: () async {
            await Scripts.pop(script.index);
            Navigator.pop(ctx);
            setState();
          },
          child: Text("Yes", style: TextStyle(color: Colors.red))
      ),
    ]
);

var askRename = (ctx, script, valueText, _textFieldController, setState) =>
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
              await script.rename(prefs, valueText);
              Navigator.pop(ctx);
              setState();
            },
            child: Text("Save", style: TextStyle(color: Colors.green))
        ),
      ],
    );

void onExit(context, webViewController){
  if(Scripts.isChanged()){
    Scripts.setUnchanged();
    webViewController!.removeAllUserScripts();
    webViewController.addUserScript(userScript: UserScript(
        source: settingsCode(
            Scripts.enabled((s) => s.code)
                .cast<String>().join("\n")),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END));
    showDialog(
        context: context,
        builder: (BuildContext context) => askReload(context, webViewController)
    );
  }
  else {
    setStateStack.removeLast();
    Navigator.pop(context);
  }
}

class _UserScriptsRouteState extends State<UserScriptsRoute> {

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
            title: const Text("Scripts"),
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
                      icon: const Icon(Icons.get_app),
                      onPressed: () async {
                        FilePickerResult? result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['js'],
                        );
                        if(result != null && result.files.single.path != null) {
                          File file = File(result.files.single.path!);
                          file.readAsString().then((String contents) {
                            Scripts.push(basename(result.files.single.path!), contents);
                            setState((){});
                          });
                        }
                        //ScaffoldMessenger.of(context).showSnackBar(
                        //  const SnackBar(content: Text("To be continued...")),
                        //);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.book),
                      onPressed: () async {
                        await Scripts.pushDefault();
                        setState((){});
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.note_add),
                      onPressed: () async {
                        await Scripts.push();
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
            for(var i = 0; i < Scripts.metaList!.length; i++){
              var e = Scripts.metaList![i];
              if(e.order == oldIndex)
                e.setOrder(prefs, update);
              else if(e.order > lower - 1 && e.order <= upper)
                e.setOrder(prefs, e.order + 1 - inc * 2);
            }
            //for(var i = 0; i < Scripts.metaList!.length; i++) {
            //  var e = Scripts.metaList![i];
            //  print("$i => ${e.order}");
            //}
            setState((){});
          },
          children: Scripts.ordered((script){
            return ListTile(
              leading: ReorderableDragStartListener(
                index: script.order,
                child: const Icon(Icons.drag_handle),
              ),
              key: Key('${script.order}'),
              tileColor: Colors.white,
              title: Text('${script.name}'),
              trailing: Switch(
                  value: script.enable,
                  onChanged: (value) async {
                    SharedPreferences prefs = await SharedPreferences.getInstance();
                    script.setEnable(prefs, value);
                    setState((){});
                  }
              ),
              onTap: () {
                showDialog(context: context, builder: (BuildContext context){
                  return AlertDialog(
                      title: Text("${script.name}"),
                      //content: Text("Dialog Content"),
                      actions: <Widget>[
                        Card(
                            child: ListTile(
                                leading: Icon(Icons.tag),
                                title: Text("Rename Script"),
                                subtitle: Text("click to rename"),
                                onTap: () {
                                  Navigator.pop(context);
                                  showDialog(
                                      context: context,
                                      builder: (BuildContext context){
                                        var valueText = script.name;
                                        return askRename(context, script,
                                            valueText, _textFieldController,
                                            this.commitView);
                                      }
                                  );
                                }
                            )
                        ),
                        Card(
                            child: ListTile(
                                leading: Icon(Icons.mode_edit),
                                title: Text("Edit the Script"),
                                subtitle: Text("click to edit"),
                                onTap: () async {
                                  Navigator.pop(context);
                                  Navigator.pushNamed(
                                    context,
                                    '/editScripts',
                                    arguments: ScriptArgs(script),
                                  );
                                }
                            )
                        ),
                        Card(
                            child: ListTile(
                                leading: Icon(Icons.ios_share),
                                title: Text("Export the Script"),
                                subtitle: Text("click to export"),
                                onTap: () async {
                                  Navigator.pop(context);
                                  var name = script.name;
                                  if(!name.endsWith(".js")) name = name + ".js";
                                  final Directory? directory = await getExternalStorageDirectory();
                                  if(directory != null){
                                    final File file = File('${directory.path}/$name');
                                    await file.writeAsString(script.code);
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(directory == null ?
                                    "Cannot get directory QwQ" :
                                    "Exported as $name under ${directory.path}")),
                                  );
                                }
                            )
                        ),
                        Card(
                            child: ListTile(
                                leading: Icon(Icons.content_copy),
                                title: Text("Duplicate the Script"),
                                subtitle: Text("click to duplicate"),
                                onTap: () {
                                  Navigator.pop(context);
                                  Scripts.push("copy_" + script.name, script.code);
                                  setState((){});
                                }
                            )
                        ),
                        Card(
                            child: ListTile(
                                leading: Icon(Icons.delete_sweep),
                                title: Text("Delete the Script",
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
                                            script,
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