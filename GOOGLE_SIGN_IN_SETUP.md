# Google sign-in setup

This configures Google sign-in for the macOS and Windows NOVA Copilot desktop apps. It does not require a custom email domain or an SMTP password.

## 1. Create a Google OAuth client

1. Open [Google Auth Platform](https://console.cloud.google.com/auth/clients) and create an OAuth client ID with application type **Web application**.
2. Add this authorized redirect URI:

   ```text
   https://nhzpodixkjhynvcwnzok.supabase.co/auth/v1/callback
   ```

3. Save the client ID and client secret. The secret belongs in Supabase only; never add it to the app or repository.
4. In the Google Auth Platform audience settings, choose **External**. While the app is in **Testing**, add each friend's Google email as a test user. Testing supports up to 100 users, and Google currently expires test-user authorizations after seven days, so they may need to sign in again weekly. Publish the consent screen when you are ready for broader access. [Google's audience documentation](https://support.google.com/cloud/answer/15549945) describes these limits.

These are desktop clients, so they do not use a browser JavaScript origin. The Google OAuth redirect URI above is the only redirect that should be registered in the Google client.

## 2. Enable Google in Supabase

In the NOVA Supabase project, open **Authentication → Sign In / Providers → Google**, enable Google, and paste the client ID and secret.

Then open **Authentication → URL Configuration → Redirect URLs** and add both exact callback URLs:

```text
com.novatechnologies.novacopilot://auth-callback
http://127.0.0.1:8765/oauth/callback
```

The first is the macOS app's registered URL scheme. The second is a temporary loopback callback used only by the Windows app while it completes sign-in.

## 3. Restrict access to precreated accounts (owner-only setup)

If only accounts that already exist should be able to sign in, open **Authentication → Settings → General** in Supabase and turn off **Allow new users to sign up**. Supabase then allows existing accounts to sign in while rejecting new registrations. [Supabase Auth configuration](https://supabase.com/docs/guides/auth/general-configuration) documents this setting.

Use **Continue with Google** with the Google account whose verified email matches the precreated owner account. Supabase automatically links a verified OAuth identity to an existing user with the same email, so no shared owner code is needed. [Identity linking details](https://supabase.com/docs/guides/auth/auth-identity-linking).

## 4. Try it

Build or install the updated desktop app, choose **Continue with Google**, and finish in your system browser. The app exchanges the returned authorization code with Supabase using PKCE and stores its session in the OS-protected local credential store.

Email/password sign-in remains available for existing accounts. The app no longer offers account creation. The Google provider must be configured in Supabase before Google sign-in can work.
