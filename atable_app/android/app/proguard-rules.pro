# Flutter WebView ProGuard rules

# Keep WebView JavaScript interfaces
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# WebView Flutter plugin
-keep class io.flutter.plugins.webviewflutter.** { *; }

# Keep annotations
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable

# Connectivity Plus
-keep class dev.fluttercommunity.plus.connectivity.** { *; }
