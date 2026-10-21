# Flutter Wrapper & Plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Play Services & Location (Geolocator)
-keep class com.google.android.gms.location.** { *; }
-dontwarn com.google.android.gms.**

# Camera Plugin
-keep class io.flutter.plugins.camera.** { *; }

# General optimizations
-dontwarn io.flutter.embedding.**
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**

# Native Tracking Services & Receivers
-keep class com.fieldstaff.attendance.fieldstaff_attendance.** { *; }
-keepclassmembers class com.fieldstaff.attendance.fieldstaff_attendance.** { *; }
-keep class * extends android.app.Service { *; }
-keep class * extends android.content.BroadcastReceiver { *; }
-keep class **.R$* { *; }
-keep class **.R { *; }
