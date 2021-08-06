import 'dart:core';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Cookie;
import 'package:shared_preferences/shared_preferences.dart';
import 'LmdBotAppGlobal.dart';
import 'package:code_editor/code_editor.dart';

var askEnable = (ctx, model, script, prefs) => AlertDialog(
    title: Text("Enable the code?"),
    //content: Text("Do you really want to delete the script?"),
    actions: [
      TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            Navigator.pop(ctx);
            setStateStack.removeLast();
          },
          child: Text("No", style: TextStyle(color: Colors.red))
      ),
      TextButton(
          onPressed: () async {
            await script.setEnable(prefs, true);
            Navigator.pop(ctx);
            Navigator.pop(ctx);
            setStateStack.removeLast();
            setStateStack.last();
          },
          child: Text("Yes", style: TextStyle(color: Colors.green))
      ),
    ]
);



var askSave = (ctx, model, script) => AlertDialog(
    title: Text("Save the code?"),
    //content: Text("Do you really want to delete the script?"),
    actions: [
      TextButton(
          onPressed: () { Navigator.pop(ctx); },
          child: Text("Cancel", style: TextStyle(color: Colors.black))
      ),
      TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.pop(ctx);
            setStateStack.removeLast();
          },
          child: Text("No", style: TextStyle(color: Colors.red))
      ),
      TextButton(
          onPressed: () async {
            SharedPreferences prefs = await SharedPreferences.getInstance();
            script.setCode(prefs, model.getCodeWithIndex(0) ?? "");
            Navigator.pop(ctx);

            if(script.enable){
              Navigator.pop(ctx);
              setStateStack.removeLast();
            }
            else{
              showDialog(
                  context: ctx,
                  builder: (BuildContext context){
                    return askEnable(context, model, script, prefs);
                  }
              );
            }
          },
          child: Text("Yes", style: TextStyle(color: Colors.green))
      ),
    ]
);

class EditScriptsRoute extends StatefulWidget {
  const EditScriptsRoute({Key? key}) : super(key: key);

  @override
  State<EditScriptsRoute> createState() => _EditScriptsRouteState();
}

void onExit (context, model, Script script) => {
  if(model?.getInvWithIndex(0) ?? false){
    showDialog(context: context,
        builder: (BuildContext context) =>
            askSave(context, model, script)
    )
  }
  else{
    Navigator.pop(context),
    setStateStack.removeLast()
  }
};

class _EditScriptsRouteState extends State<EditScriptsRoute> {

  InAppWebViewController? webViewController;


  // The model used by the CodeEditor widget, you need it in order to control it.
  // But, since 1.0.0, the model is not required inside the CodeEditor Widget.
  IconData modeIcon = Icons.edit;
  EditorModel? model;

  @override
  void initState() {
    super.initState();
    setStateStack.add(() {setState((){});});
  }

  void commitView() { setState((){}); }

  @override
  Widget build(BuildContext context) {

    final args = ModalRoute.of(context)!.settings.arguments as ScriptArgs;
    if(model == null){
      // The files displayed in the navigation bar of the editor.
      // You are not limited.
      // By default, [name] = "file.${language ?? 'txt'}", [language] = "text" and [code] = "",
      List<FileEditor> files = [
        new FileEditor(
          name: args.script.name,
          language: "javascript", // TODO detect language
          code: args.script.code, // [code] needs a string
        ),
      ];

      model = new EditorModel(
        files: files, // the files created above
        // you can customize the editor as you want
        styleOptions: new EditorModelStyleOptions(
          fontSize: 13,
          heightOfContainer: 600,
        ),
      );
    }
    // TODO assign script

    var editButton =  IconButton(
      //icon: const Icon(Icons.save),
      icon: Icon(modeIcon),
      onPressed: () async {
        //await Scripts.push();
        //setState((){});
        // TODO save script
        modeIcon = model!.isEditing ? Icons.edit : Icons.visibility;
        setState(() {
          model?.toggleEditing();
        });
      },
    );

    var codeEditor = CodeEditor(
      model: model, // the model created above, not required since 1.0.0
      edit: true, // can edit the files ? by default true
      disableNavigationbar: false, // hide the navigation bar ? by default false
      onSubmit: (String? language, String? value) {
      }, // when the user confirms changes in one of the files
    );

    return WillPopScope(
        onWillPop: () async {
          onExit(context, model, args.script);
          return false;
        },
        child: Scaffold(
          backgroundColor: Color(0xff2E3152),
          appBar: AppBar(
              title: const Text("Edit Scripts"),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to User Scripts',
                onPressed: () {
                  onExit(context, model, args.script);
                },
              ),
              actions: <Widget>[
                Row(
                    children: <Widget>[
                      editButton,
                    ])
              ]
          ),
          body: SingleChildScrollView(
            // /!\ important because of the telephone keypad which causes
            // a "RenderFlex overflowed by x pixels on the bottom" error
            // display the CodeEditor widget
            child: codeEditor
        ),
      )
    );
  }
}