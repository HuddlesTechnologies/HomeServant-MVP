# flutter_secure_storage backs onto AndroidX Security Crypto (Tink), which
# registers its KeyManagers via reflection — R8 can strip those classes
# without ever seeing an explicit reference, breaking secure storage at
# runtime with no compile-time warning.
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# google_sign_in's Credential/Auth result objects are parceled and read back
# by the Play Services framework outside of app code, so R8 can't see that
# a field is still needed — keep them intact rather than risk a silent
# deserialization failure on the sign-in callback.
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }
