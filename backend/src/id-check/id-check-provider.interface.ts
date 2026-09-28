import { IdCheckStatus, IdType } from '@prisma/client';

/// Who this ID is supposed to belong to — taken from the account, never
/// from the same form as the ID number, so the check is actually
/// comparing two independent claims.
export interface IdCheckSubject {
  firstName: string | null;
  lastName: string | null;
  fullName: string | null;
  dateOfBirth: Date | null;
}

export interface IdCheckRequest {
  idType: IdType;
  /// Already normalised by VerificationService (no spaces or dashes,
  /// upper-cased).
  idNumber: string;
  subject: IdCheckSubject;
}

export interface IdCheckResult {
  /// MATCH is the only outcome that can verify an account on its own.
  outcome: IdCheckStatus;
  /// Which provider answered — stored on the submission so a decision can
  /// be traced back to them.
  provider: string;
  /// The provider's own reference for this check, when it gave one.
  reference?: string | null;
  /// The name the issuing authority holds against this ID number. Kept so
  /// a reviewer can see why a check matched or didn't.
  name?: string | null;
  /// One line a reviewer can read. Never put provider photo/signature
  /// payloads or the raw response in here.
  detail: string;
}

/// A pluggable identity-lookup channel — mirrors the OtpProvider and
/// DeliveryProvider patterns (see otp-provider.interface.ts):
/// VerificationService depends only on this interface, so swapping
/// providers is a one-file change plus an env var.
///
/// Unlike those two, [check] must NEVER throw. It runs inside signup, and
/// an ID provider being down, slow or out of credit must not stop someone
/// creating an account — it just leaves the submission for a moderator.
/// Implementations return `ERROR`/`UNSUPPORTED` instead of rejecting.
export interface IdCheckProvider {
  /// Stored as `idCheckProvider` on the submission.
  readonly name: string;

  /// Looks [request.idNumber] up with the issuing authority and compares
  /// the name it holds against [request.subject].
  check(request: IdCheckRequest): Promise<IdCheckResult>;
}

/// Shorthand for building a result without repeating the provider name.
export function idCheckResult(provider: string, outcome: IdCheckStatus, detail: string, extra: Partial<IdCheckResult> = {}): IdCheckResult {
  return { provider, outcome, detail, ...extra };
}
