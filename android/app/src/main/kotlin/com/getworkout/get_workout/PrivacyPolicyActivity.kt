package com.getworkout.get_workout

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle

// Health Connect's link to the app's privacy policy: opens it in the
// browser and closes, without starting Flutter.
class PrivacyPolicyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_POLICY_URL)))
        } catch (e: ActivityNotFoundException) {
            // No browser: nothing to show the policy in.
        }
        finish()
    }

    private companion object {
        // Release blocker: a placeholder until the policy is published (see
        // SPEC's open questions); must match LegalLinks.privacy in
        // lib/app/legal_links.dart.
        const val PRIVACY_POLICY_URL = "https://example.com/getworkout/privacy"
    }
}
