package de.circle_dev.flux_news

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent  
import android.net.Uri
import android.content.ActivityNotFoundException
import android.content.pm.PackageInfo
import androidx.browser.customtabs.*
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.view.WindowCompat

// this are the constants used in the dart code
private const val CHANNEL = "UrlLauncher"
private const val KEY_OPTIONS_URL = "url"
private const val KEY_OPTIONS_PREFERRED_PACKAGE_NAME = "preferredPackageName"
private const val KEY_OPTIONS_TOOLBAR_COLOR = "toolbarColor"
private const val KEY_OPTIONS_SHOW_PAGE_TITLE = "showPageTitle"
private const val KEY_OPTIONS_ENABLE_URL_BAR_HIDING = "enableUrlBarHiding"
private const val KEY_OPTIONS_DEFAULT_SHARE_MENU_ITEM = "enableDefaultShare"
private const val KEY_OPTIONS_ENABLE_INSTANT_APPS = "enableInstantApps"
class MainActivity: FlutterActivity() {

    // This is needed to hide the status bar and navigation bar
    override fun onPostResume() {
      super.onPostResume()
      WindowCompat.setDecorFitsSystemWindows(window, false)
      window.navigationBarColor = 0
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            // if the method call is launchURL then we will launch the url
            if (call.method == "launchURL") {
                // get the url from the arguments
                val url = call.argument<String>(KEY_OPTIONS_URL)
                if (url != null) {
                    if (url.startsWith("https")) {
                        // if the url is https then we will try to launch the url with a installed app
                        val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        browserIntent.addCategory(Intent.CATEGORY_BROWSABLE)
                        browserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK +
                                Intent.FLAG_ACTIVITY_REQUIRE_NON_BROWSER)
                        try {
                            // try to start an app that can handle the url
                            startActivity(browserIntent)
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            // if no app is installed that can handle the url then we will open the url in a custom tab
                            val builder = CustomTabsIntent.Builder()
                            
                            // set the toolbar color
                            if(call.argument<Int>(KEY_OPTIONS_TOOLBAR_COLOR) != null) {
                                val toolbarColorInt = call.argument<Long>(KEY_OPTIONS_TOOLBAR_COLOR)
                                val params = CustomTabColorSchemeParams.Builder()
                                if(toolbarColorInt != null) {
                                    params.setToolbarColor(toolbarColorInt.toInt())
                                    builder.setDefaultColorSchemeParams(params.build())
                                }
                            }

                            // set the flag to show the page title
                            val showPageTitle = call.argument<Boolean>(KEY_OPTIONS_SHOW_PAGE_TITLE) ?: true
                            builder.setShowTitle(showPageTitle)

                            // set the flag to enable instant apps
                            val enableInstantApps = call.argument<Boolean>(KEY_OPTIONS_ENABLE_INSTANT_APPS) ?: false
                            builder.setInstantAppsEnabled(enableInstantApps)
                            
                            // setShareState(CustomTabsIntent.SHARE_STATE_ON) will add a menu to share the web-page
                            val shareStateOn = call.argument<Boolean>(KEY_OPTIONS_DEFAULT_SHARE_MENU_ITEM) ?: true
                            if(shareStateOn) {
                                builder.setShareState(CustomTabsIntent.SHARE_STATE_ON)
                            } else {
                                builder.setShareState(CustomTabsIntent.SHARE_STATE_OFF)
                            }
                            
                            // set the flag to enable url bar hiding
                            val urlBarHidingEnabled = call.argument<Boolean>(KEY_OPTIONS_ENABLE_URL_BAR_HIDING) ?: false
                            builder.setUrlBarHidingEnabled(urlBarHidingEnabled)

                            // set the flag to enable instant apps
                            builder.setInstantAppsEnabled(true)
                            val customBuilder = builder.build()
                            // if the preferred package name is set then we will use that package to open the url
                            if(call.argument<String>(KEY_OPTIONS_PREFERRED_PACKAGE_NAME) != null) {
                                val preferredPackageName = call.argument<String>(KEY_OPTIONS_PREFERRED_PACKAGE_NAME) ?: ""
                                if (isPackageInstalled(preferredPackageName)) {
                                    // if the preferred package is available then we will use that package to open the url
                                    customBuilder.intent.setPackage(preferredPackageName)
                                    customBuilder.launchUrl(this, Uri.parse(url))
                                    result.success(true)
                                } else {
                                    // if the preferred package is not available then we will return an error
                                    result.error("UNAVAILABLE", "Preferred Package is not available.", null)
                                }
                            } else {
                                // if the preferred package is not set then we will use chrome custom tabs to open the url
                                customBuilder.launchUrl(this, Uri.parse(url))
                                result.success(true)
                            }                        
                        }
                    } else {
                        // if the url is not https then we will return false
                        result.success(false)
                    }
                } else {
                    // if the url is null then we will return an error
                    result.error("URL EMPTY", "The url parameter is empty.", null)
                }
            } else {
                // if the method call is not launchURL then we will return an error
                result.notImplemented()
            }
        }
    }
    private fun isPackageInstalled(packageName: String): Boolean {
        // check if the preferred package is installed
        return try {
            packageManager.getPackageInfoCompat(packageName)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }
}

// this is a helper function to get the package info
fun PackageManager.getPackageInfoCompat(packageName: String, flags: Int = 0): PackageInfo =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(flags.toLong()))
    } else {
        @Suppress("DEPRECATION") getPackageInfo(packageName, flags)
    }
