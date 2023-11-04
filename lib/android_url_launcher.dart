import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// this class is used to implement the custom news launcher for android
// the custom news launcher was created, because no package delivered the following feature:
// if an url should be opened, check at first if another app is possible to handle this url
// this is called App Links.
// if there is an app installs, hand over the App Link.
// if there is no app installed, open the link within an in app browser window
// using the chrome custom tabs feature.
class AndroidUrlLauncher {
  // call the urlLauncher via the given MethodChanel from the MainActivity.kt file
  static const urlLauncher = MethodChannel('UrlLauncher');
  // create a method to launch a given url via the urlLauncher
  static Future<void> launchUrl(BuildContext context, String url) async {
    // define the arguments for the urlLauncher
    Map<String, Object?> arguments = {
      'url': url,
      'preferredPackageName': null,
      'toolbarColor': Theme.of(context).primaryColor.value,
      'showPageTitle': true,
      'enableUrlBarHiding': false,
      'enableDefaultShare': true,
      'enableInstantApps': false
    };
    // call the method to launch the url
    var canLaunch = await urlLauncher.invokeMethod('launchURL', arguments);
    // TBD: error handling of possible wrong url
    if (!canLaunch) {}
  }
}
