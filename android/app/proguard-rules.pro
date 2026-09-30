# SQLCipher loads its native library reflectively, so R8 cannot see the
# references and would otherwise strip the classes that hold them.
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }

# Flutter's local-notifications plugin resolves scheduled callbacks by name.
-keep class com.dexterous.** { *; }

# Google Play Core is referenced by Flutter's deferred-components support, which
# this app does not use; without these the release build warns about missing
# classes that will never be loaded.
-dontwarn com.google.android.play.core.**
