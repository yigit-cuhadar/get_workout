package com.getworkout.get_workout

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

// A fragment activity: Health Connect's permission dialog needs one.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Health Connect's privacy policy link opens this activity; show the
        // policy instead of the app.
        val action = intent?.action
        if (action != null && action in privacyPolicyActions) {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_POLICY_URL)))
            finish()
        }
    }

    private companion object {
        // Must match LegalLinks.privacy in lib/app/legal_links.dart.
        const val PRIVACY_POLICY_URL = "https://example.com/getworkout/privacy"

        val privacyPolicyActions = setOf(
            "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE",
            "android.intent.action.VIEW_PERMISSION_USAGE",
        )
    }
}
