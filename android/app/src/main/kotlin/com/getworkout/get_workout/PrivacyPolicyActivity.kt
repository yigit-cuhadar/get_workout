package com.getworkout.get_workout

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle

// Health Connect's link to the app's privacy policy: opens it in the
// browser and closes, without starting Flutter. The address comes from
// LegalLinks.privacyUrl through the build (app/build.gradle.kts).
class PrivacyPolicyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val policy = Uri.parse(getString(R.string.privacy_policy_url))
            startActivity(Intent(Intent.ACTION_VIEW, policy))
        } catch (e: ActivityNotFoundException) {
            // No browser: nothing to show the policy in.
        }
        finish()
    }
}
