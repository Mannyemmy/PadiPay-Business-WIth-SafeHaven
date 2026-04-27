# QoreID SDK
-keep class com.qoreid.sdk.** { *; }

# Keep the QoreID native callback classes if any
-keep class com.qoreid.** { *; }

# Tappa / Sudo Africa SDK — keep all classes, fields, and methods so R8 does not
# strip or rename the SDK's networking/reflection code at runtime.
-keep class com.mba.tappa.** { *; }
-keep interface com.mba.tappa.** { *; }
-keepclassmembers class com.mba.tappa.** { *; }
-dontwarn com.mba.tappa.**
