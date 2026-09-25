import { BadRequestException, Injectable, InternalServerErrorException, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac, timingSafeEqual } from 'crypto';

export interface PaystackBank {
  name: string;
  code: string;
}

export interface PaystackInitializedTransaction {
  authorizationUrl: string;
  accessCode: string;
  reference: string;
}

export interface PaystackTransferRecipient {
  recipientCode: string;
}

/// Wraps the handful of Paystack "Miscellaneous"/"Verification" endpoints
/// used to let a landlord pick a real Nigerian bank and prove they own the
/// account number they're entering, without this app having to maintain
/// its own bank list or do account-name lookups itself.
@Injectable()
export class PaystackService {
  private readonly logger = new Logger('Paystack');
  private readonly secretKey: string;
  private banksCache: { banks: PaystackBank[]; fetchedAt: number } | null = null;
  private static readonly BANKS_CACHE_TTL_MS = 24 * 60 * 60 * 1000;

  constructor(private readonly config: ConfigService) {
    this.secretKey = this.config.getOrThrow<string>('PAYSTACK_SECRET_KEY');
  }

  /// Nigerian banks Paystack can resolve accounts against — cached in
  /// memory since this list changes rarely, so a landlord opening the bank
  /// picker doesn't cost a Paystack call every time.
  async listBanks(): Promise<PaystackBank[]> {
    const cached = this.banksCache;
    if (cached && Date.now() - cached.fetchedAt < PaystackService.BANKS_CACHE_TTL_MS) {
      return cached.banks;
    }

    const response = await fetch('https://api.paystack.co/bank?country=nigeria&currency=NGN', {
      headers: { Authorization: `Bearer ${this.secretKey}` },
    });
    const body = (await response.json()) as { status: boolean; message: string; data?: { name: string; code: string; active: boolean }[] };
    if (!response.ok || !body.status || !body.data) {
      throw new InternalServerErrorException('Could not load the bank list right now');
    }

    const banks = body.data.filter((b) => b.active).map((b) => ({ name: b.name, code: b.code }));
    this.banksCache = { banks, fetchedAt: Date.now() };
    return banks;
  }

  /// Resolves an account number + bank code to the account holder's name
  /// as it exists at the bank — this is what a landlord's `accountName`
  /// gets set from (see UsersService.updateBankDetails), never from
  /// anything the client claims directly.
  async resolveAccount(accountNumber: string, bankCode: string): Promise<{ accountNumber: string; accountName: string }> {
    const response = await fetch(
      `https://api.paystack.co/bank/resolve?account_number=${encodeURIComponent(accountNumber)}&bank_code=${encodeURIComponent(bankCode)}`,
      { headers: { Authorization: `Bearer ${this.secretKey}` } },
    );
    const body = (await response.json()) as { status: boolean; message: string; data?: { account_number: string; account_name: string } };
    if (!response.ok || !body.status || !body.data) {
      throw new BadRequestException(body.message || "Couldn't verify that account number — check the bank and number are correct");
    }
    return { accountNumber: body.data.account_number, accountName: body.data.account_name };
  }

  /// Starts a Paystack Standard Transaction — the payer completes it at
  /// [authorizationUrl] (hosted checkout), and Paystack calls our webhook
  /// with `charge.success` once it clears. [amountKobo] is the full charge
  /// amount (never split at this layer — see PaymentsService for the
  /// escrow-then-Transfer design this app uses instead of Split Payments).
  /// [reference] must be unique per attempt; Paystack rejects a repeat.
  async initializeTransaction(
    email: string,
    amountKobo: number,
    reference: string,
    metadata?: Record<string, unknown>,
  ): Promise<PaystackInitializedTransaction> {
    const response = await fetch('https://api.paystack.co/transaction/initialize', {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.secretKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, amount: amountKobo, reference, metadata }),
    });
    const body = (await response.json()) as {
      status: boolean;
      message: string;
      data?: { authorization_url: string; access_code: string; reference: string };
    };
    if (!response.ok || !body.status || !body.data) {
      this.logger.error(`initializeTransaction failed for reference ${reference}: ${body.message}`);
      throw new InternalServerErrorException(body.message || 'Could not start this payment right now');
    }
    return {
      authorizationUrl: body.data.authorization_url,
      accessCode: body.data.access_code,
      reference: body.data.reference,
    };
  }

  /// HMAC-SHA512 of the raw request body, keyed by the secret key — the
  /// exact scheme Paystack documents for `x-paystack-signature`. Compared
  /// with a constant-time equality check so this can't be timed to leak
  /// how many leading bytes matched. Must run against the *raw* bytes
  /// Paystack sent, before any JSON parsing/re-serialization — see
  /// main.ts's `rawBody: true` bootstrap option and PaystackController.
  verifyWebhookSignature(rawBody: Buffer, signatureHeader: string | string[] | undefined): boolean {
    if (!signatureHeader || Array.isArray(signatureHeader)) return false;
    const expected = createHmac('sha512', this.secretKey).update(rawBody).digest('hex');
    const expectedBuf = Buffer.from(expected, 'utf8');
    const givenBuf = Buffer.from(signatureHeader, 'utf8');
    if (expectedBuf.length !== givenBuf.length) return false;
    return timingSafeEqual(expectedBuf, givenBuf);
  }

  /// Registers a payout destination with Paystack ahead of a Transfer —
  /// required once per (bankCode, accountNumber) pair before `/transfer`
  /// will accept it. [accountName] must already be the Paystack-resolved
  /// name (see UsersService.updateBankDetails / VendorsService.update),
  /// never anything a client typed directly.
  async createTransferRecipient(bankCode: string, accountNumber: string, accountName: string): Promise<string> {
    const response = await fetch('https://api.paystack.co/transferrecipient', {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.secretKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'nuban', name: accountName, account_number: accountNumber, bank_code: bankCode, currency: 'NGN' }),
    });
    const body = (await response.json()) as { status: boolean; message: string; data?: { recipient_code: string } };
    if (!response.ok || !body.status || !body.data) {
      this.logger.error(`createTransferRecipient failed: ${body.message}`);
      throw new InternalServerErrorException(body.message || 'Could not register the payout account right now');
    }
    return body.data.recipient_code;
  }

  /// Sends HomeServant's own Paystack balance to a previously-registered
  /// recipient — the "release" half of the hold-then-Transfer escrow
  /// design (see PaymentsService). [amountKobo] here is already the
  /// recipient's share (amount minus the platform fee) — this method does
  /// no fee math of its own.
  /// [reference] should be a value stable across retries of the *same*
  /// release (PaymentsService passes the Payment's own id) — Paystack
  /// treats a transfer request carrying a reference it's already seen as
  /// a retry of that same transfer rather than a new one, so if our own
  /// write marking the Payment RELEASED fails right after Paystack accepts
  /// the transfer, a subsequent retry with the same reference can't
  /// double-pay the recipient.
  async initiateTransfer(amountKobo: number, recipientCode: string, reason: string, reference: string): Promise<{ transferCode: string; status: string }> {
    const response = await fetch('https://api.paystack.co/transfer', {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.secretKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ source: 'balance', amount: amountKobo, recipient: recipientCode, reason, reference }),
    });
    const body = (await response.json()) as { status: boolean; message: string; data?: { transfer_code: string; status: string } };
    if (!response.ok || !body.status || !body.data) {
      this.logger.error(`initiateTransfer failed for recipient ${recipientCode}: ${body.message}`);
      throw new InternalServerErrorException(body.message || 'Could not release this payment right now');
    }
    return { transferCode: body.data.transfer_code, status: body.data.status };
  }

  /// Issues a Paystack refund for a previously-charged transaction.
  /// [amountKobo] omitted refunds the full original charge; passed, it
  /// refunds only that much (used for the rental pre-move-in refund path,
  /// which withholds HomeServant's 0.2% — see PaymentsService). Paystack
  /// does not return its own processing fee to the merchant on a refund by
  /// default, so that portion is simply never recovered by either side —
  /// nothing to compute here.
  async refundTransaction(reference: string, amountKobo?: number): Promise<void> {
    const response = await fetch('https://api.paystack.co/refund', {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.secretKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ transaction: reference, ...(amountKobo !== undefined ? { amount: amountKobo } : {}) }),
    });
    const body = (await response.json()) as { status: boolean; message: string };
    if (!response.ok || !body.status) {
      this.logger.error(`refundTransaction failed for reference ${reference}: ${body.message}`);
      throw new InternalServerErrorException(body.message || 'Could not process this refund right now');
    }
  }
}
