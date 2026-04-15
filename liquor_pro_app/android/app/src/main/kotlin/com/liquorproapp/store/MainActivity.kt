package com.liquorproapp.store

import android.os.Bundle
import com.google.firebase.auth.FirebaseAuth
import io.flutter.BuildConfig
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Enable phone auth test mode in debug builds
        // This allows test phone numbers to bypass rate limits on emulators
        if (BuildConfig.DEBUG) {
            FirebaseAuth.getInstance().firebaseAuthSettings
                .setAppVerificationDisabledForTesting(true)
            android.util.Log.d("LiquorPro", "✅ Firebase Phone Auth: test mode enabled (native Android)")
        }
    }
}
