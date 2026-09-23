/// A pluggable OTP delivery channel — one implementation per real
/// provider (SMS via Termii, email via Resend/SendGrid, etc). OtpService
/// depends only on this interface, so swapping providers later is a
/// one-file change plus an env var, not a rewrite of the auth flow.
export interface OtpProvider {
  /// Sends [code] to [destination] (an email address or phone number).
  /// Should throw if delivery fails so the caller can surface an error
  /// instead of silently pretending the code went out.
  send(destination: string, code: string): Promise<void>;
}
